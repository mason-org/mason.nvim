local InstallContext = require "mason-core.installer.context"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local compiler = require "mason-core.installer.compiler"
local control = require "mason-core.async.control"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local registry = require "mason-registry"

local OneShotChannel = control.OneShotChannel

---@class UninstallRunner
---@field handle InstallHandle
---@field global_semaphore Semaphore
---@field package_permit Permit?
---@field global_permit Permit?
local UninstallRunner = {}
UninstallRunner.__index = UninstallRunner

---@param handle InstallHandle
---@param global_semaphore Semaphore
---@return UninstallRunner
function UninstallRunner:new(handle, global_semaphore)
    local instance = {}
    setmetatable(instance, self)
    instance.handle = handle
    instance.global_semaphore = global_semaphore
    return instance
end

---@param opts PackageUninstallOpts
---@param callback? InstallRunnerCallback
function UninstallRunner:execute(opts, callback)
    local pkg = self.handle.package
    local location = self.handle.location
    log.fmt_info("Executing uninstaller for %s %s", pkg, opts)
    a.run(function()
        Result.try(function(try)
            if not opts.bypass_permit then
                try(self:acquire_permit()):receive()
            end
            ---@type InstallReceipt?
            local receipt = pkg:get_receipt(location):or_else(nil)
            if receipt == nil then
                log.fmt_warn("Receipt not found when uninstalling %s", pkg)
            else
                try(pkg:unlink(location))
            end
            fs.sync.rmrf(location:package(pkg.name))
            return receipt
        end):get_or_throw()
    end, function(success, result)
        if not self.handle:is_closing() then
            self.handle:close()
        end
        self:release_permit()

        if success then
            local receipt = result
            log.fmt_info("Uninstallation succeeded for %s", pkg)
            if callback then
                callback(true, receipt)
            end
            pkg:emit("uninstall:success", receipt)
            registry:emit("package:uninstall:success", pkg, receipt)
        else
            log.fmt_error("Uninstallation failed for %s error=%s", pkg, result)
            if callback then
                callback(false, result)
            end
            pkg:emit("uninstall:failed", result)
            registry:emit("package:uninstall:failed", pkg, result)
        end
    end)
end

---@private
function UninstallRunner:acquire_permit()
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
function UninstallRunner:release_permit()
    if self.global_permit then
        self.global_permit:forget()
        self.global_permit = nil
    end
    if self.package_permit then
        self.package_permit:forget()
        self.package_permit = nil
    end
end

return UninstallRunner
