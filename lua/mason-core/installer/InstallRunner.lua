local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local compiler = require "mason-core.installer.compiler"
local control = require "mason-core.async.control"
local fs = require "mason-core.fs"
local linker = require "mason-core.installer.linker"
local log = require "mason-core.log"
local registry = require "mason-registry"

local OneShotChannel = control.OneShotChannel

local InstallContext = require "mason-core.installer.context"

---@class InstallRunner
---@field handle InstallHandle
---@field global_semaphore Semaphore
---@field global_permit Permit?
---@field package_permit Permit?
local InstallRunner = {}
InstallRunner.__index = InstallRunner

---@param handle InstallHandle
---@param semaphore Semaphore
function InstallRunner:new(handle, semaphore)
    ---@type InstallRunner
    local instance = {}
    setmetatable(instance, self)
    instance.global_semaphore = semaphore
    instance.handle = handle
    return instance
end

---@alias InstallRunnerCallback fun(success: true, receipt: InstallReceipt) | fun(success: false, error: any)

---@param opts PackageInstallOpts
---@param callback? InstallRunnerCallback
function InstallRunner:execute(opts, callback)
    local handle = self.handle
    log.fmt_info("Executing installer for %s %s", handle.package, opts)

    local context = InstallContext:new(handle, opts)

    local tailed_output = {}

    if opts.debug then
        local function append_log(chunk)
            tailed_output[#tailed_output + 1] = chunk
        end
        handle:on("stdout", append_log)
        handle:on("stderr", append_log)
    end

    ---@async
    local function finalize_logs(success, result)
        if not success then
            context.stdio_sink:stderr(tostring(result))
            context.stdio_sink:stderr "\n"
        end

        if opts.debug then
            context.fs:write_file("mason-debug.log", table.concat(tailed_output, ""))
            context.stdio_sink:stdout(("[debug] Installation directory retained at %q.\n"):format(context.cwd:get()))
        end
    end

    ---@async
    local finalize = a.scope(function(success, result)
        finalize_logs(success, result)

        if not opts.debug and not success then
            -- clean up installation dir
            pcall(function()
                fs.async.rmrf(context.cwd:get())
            end)
        end

        if not handle:is_closing() then
            handle:close()
        end

        self:release_lock()
        self:release_permit()

        if success then
            log.fmt_info("Installation succeeded for %s", handle.package)
            if callback then
                callback(true, result.receipt)
            end
            handle.package:emit("install:success", result.receipt)
            registry:emit("package:install:success", handle.package, result.receipt)
        else
            log.fmt_error("Installation failed for %s error=%s", handle.package, result)
            if callback then
                callback(false, result)
            end
            handle.package:emit("install:failed", result)
            registry:emit("package:install:failed", handle.package, result)
        end
    end)

    local cancel_execution = a.run(function()
        return Result.try(function(try)
            try(self.handle.location:initialize())
            try(self:acquire_permit()):receive()
            try(self:acquire_lock(opts.force))

            context.receipt:with_start_time(vim.loop.gettimeofday())
            context.receipt:with_registry(context.package.registry:serialize())

            -- 1. initialize working directory
            try(context.cwd:initialize())

            -- 2. run installer
            ---@type async fun(ctx: InstallContext): Result
            local installer = try(compiler.compile_installer(handle.package.spec, opts))
            try(context:execute(installer))

            -- 3. promote temporary installation dir
            try(Result.pcall(function()
                context:promote_cwd()
            end))

            -- 4. link package & write receipt
            try(linker.link(context):on_failure(function()
                -- unlink any links that were made before failure
                context:build_receipt():on_success(
                    ---@param receipt InstallReceipt
                    function(receipt)
                        linker.unlink(handle.package, receipt, self.handle.location):on_failure(function(err)
                            log.error("Failed to unlink failed installation.", err)
                        end)
                    end
                )
            end))
            ---@type InstallReceipt
            local receipt = try(context:build_receipt())
            try(Result.pcall(fs.sync.write_file, handle.location:receipt(handle.package.name), receipt:to_json()))
            return {
                receipt = receipt,
            }
        end):get_or_throw()
    end, finalize)

    handle:once("terminate", function()
        cancel_execution()
        local function on_close()
            finalize(false, "Installation was aborted.")
        end
        if handle:is_closed() then
            on_close()
        else
            handle:once("closed", on_close)
        end
    end)
end

---@async
---@private
function InstallRunner:release_lock()
    pcall(fs.async.unlink, self.handle.location:lockfile(self.handle.package.name))
end

---@async
---@param force boolean?
---@private
function InstallRunner:acquire_lock(force)
    local pkg = self.handle.package
    log.debug("Attempting to lock package", pkg)
    local lockfile = self.handle.location:lockfile(pkg.name)
    if force ~= true and fs.async.file_exists(lockfile) then
        log.error("Lockfile already exists.", pkg)
        return Result.failure(
            ("Lockfile exists, installation is already running in another process (pid: %s). Run with :MasonInstall --force to bypass."):format(
                fs.async.read_file(lockfile)
            )
        )
    end
    a.scheduler()
    fs.async.write_file(lockfile, vim.fn.getpid())
    log.debug("Wrote lockfile", pkg)
    return Result.success(lockfile)
end

---@private
function InstallRunner:acquire_permit()
    local channel = OneShotChannel:new()
    log.fmt_debug("Acquiring permit for %s", self.handle.package)
    local handle = self.handle
    if handle:is_active() or handle:is_closing() then
        log.fmt_debug("Received active or closing handle %s", handle)
        return Result.failure "Invalid handle state."
    end

    handle:queued()
    a.run(function()
        self.global_permit = self.global_semaphore:acquire()
        self.package_permit = handle.package:acquire_permit()
    end, function(success, err)
        if not success or handle:is_closing() then
            if not success then
                log.error("Acquiring permits failed", err)
            end
            self:release_permit()
        else
            log.fmt_debug("Activating handle %s", handle)
            handle:active()
            channel:send()
        end
    end)

    return Result.success(channel)
end

---@private
function InstallRunner:release_permit()
    if self.global_permit then
        self.global_permit:forget()
        self.global_permit = nil
    end
    if self.package_permit then
        self.package_permit:forget()
        self.package_permit = nil
    end
end

return InstallRunner
