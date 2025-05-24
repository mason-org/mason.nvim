local InstallContextCwd = require "mason-core.installer.context.InstallContextCwd"
local InstallContextFs = require "mason-core.installer.context.InstallContextFs"
local InstallContextSpawn = require "mason-core.installer.context.InstallContextSpawn"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local fetch = require "mason-core.fetch"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"
local receipt = require "mason-core.receipt"

---@class InstallContext
---@field receipt InstallReceiptBuilder
---@field fs InstallContextFs
---@field location InstallLocation
---@field spawn InstallContextSpawn
---@field handle InstallHandle
---@field package AbstractPackage
---@field cwd InstallContextCwd
---@field opts PackageInstallOpts
---@field stdio_sink StdioSink
---@field links { bin: table<string, string>, share: table<string, string>, opt: table<string, string> }
local InstallContext = {}
InstallContext.__index = InstallContext

---@param handle InstallHandle
---@param opts PackageInstallOpts
function InstallContext:new(handle, opts)
    local cwd = InstallContextCwd:new(handle)
    local spawn = InstallContextSpawn:new(handle, cwd, false)
    local fs = InstallContextFs:new(cwd)
    return setmetatable({
        cwd = cwd,
        spawn = spawn,
        handle = handle,
        location = handle.location, -- for convenience
        package = handle.package, -- for convenience
        fs = fs,
        receipt = receipt.InstallReceiptBuilder:new(),
        stdio_sink = handle.stdio_sink,
        links = {
            bin = {},
            share = {},
            opt = {},
        },
        opts = opts,
    }, InstallContext)
end

---@async
---@param url string
---@param opts? FetchOpts
function InstallContext:fetch(url, opts)
    opts = opts or {}
    if opts.out_file then
        opts.out_file = path.concat { self.cwd:get(), opts.out_file }
    end
    return fetch(url, opts):get_or_throw()
end

---@async
function InstallContext:promote_cwd()
    local cwd = self.cwd:get()
    local install_path = self:get_install_path()
    if install_path == cwd then
        log.fmt_debug("cwd %s is already promoted", cwd)
        return
    end
    log.fmt_debug("Promoting cwd %s to %s", cwd, install_path)

    -- 1. Uninstall any existing installation
    if self.handle.package:is_installed() then
        a.wait(function(resolve, reject)
            self.handle.package:uninstall({ bypass_permit = true }, function(success, result)
                if not success then
                    reject(result)
                else
                    resolve()
                end
            end)
        end)
    end

    -- 2. Prepare for renaming cwd to destination
    if platform.is.unix then
        -- Some Unix systems will raise an error when renaming a directory to a destination that does not already exist.
        fs.async.mkdir(install_path)
    end
    -- 3. Update cwd
    self.cwd:set(install_path)
    -- 4. Move the cwd to the final installation directory
    fs.async.rename(cwd, install_path)
end

---@param rel_path string The relative path from the current working directory to change cwd to. Will only restore to the initial cwd after execution of fn (if provided).
---@param fn async (fun(): any)? The function to run in the context of the given path.
function InstallContext:chdir(rel_path, fn)
    local old_cwd = self.cwd:get()
    self.cwd:set(path.concat { old_cwd, rel_path })
    if fn then
        local ok, result = pcall(fn)
        self.cwd:set(old_cwd)
        if not ok then
            error(result, 0)
        end
        return result
    end
end

---@async
---@param fn fun(resolve: fun(result: any), reject: fun(error: any))
function InstallContext:await(fn)
    return a.wait(fn)
end

---@param new_executable_rel_path string Relative path to the executable file to create.
---@param script_rel_path string Relative path to the Node.js script.
function InstallContext:write_node_exec_wrapper(new_executable_rel_path, script_rel_path)
    if not self.fs:file_exists(script_rel_path) then
        error(("Cannot write Node exec wrapper for path %q as it doesn't exist."):format(script_rel_path), 0)
    end
    return self:write_shell_exec_wrapper(
        new_executable_rel_path,
        ("node %q"):format(path.concat {
            self:get_install_path(),
            script_rel_path,
        })
    )
end

---@param new_executable_rel_path string Relative path to the executable file to create.
---@param script_rel_path string Relative path to the Node.js script.
function InstallContext:write_ruby_exec_wrapper(new_executable_rel_path, script_rel_path)
    if not self.fs:file_exists(script_rel_path) then
        error(("Cannot write Ruby exec wrapper for path %q as it doesn't exist."):format(script_rel_path), 0)
    end
    return self:write_shell_exec_wrapper(
        new_executable_rel_path,
        ("ruby %q"):format(path.concat {
            self:get_install_path(),
            script_rel_path,
        })
    )
end

---@param new_executable_rel_path string Relative path to the executable file to create.
---@param script_rel_path string Relative path to the PHP script.
function InstallContext:write_php_exec_wrapper(new_executable_rel_path, script_rel_path)
    if not self.fs:file_exists(script_rel_path) then
        error(("Cannot write PHP exec wrapper for path %q as it doesn't exist."):format(script_rel_path), 0)
    end
    return self:write_shell_exec_wrapper(
        new_executable_rel_path,
        ("php %q"):format(path.concat {
            self:get_install_path(),
            script_rel_path,
        })
    )
end

---@param new_executable_rel_path string Relative path to the executable file to create.
---@param module string The python module to call.
function InstallContext:write_pyvenv_exec_wrapper(new_executable_rel_path, module)
    local pypi = require "mason-core.installer.managers.pypi"
    local module_exists, module_err = pcall(function()
        local result =
            self.spawn.python { "-c", ("import %s"):format(module), with_paths = { pypi.venv_path(self.cwd:get()) } }
        if not self.spawn.strict_mode then
            result:get_or_throw()
        end
    end)
    if not module_exists then
        log.fmt_error("Failed to find module %q for package %q. %s", module, self.package, module_err)
        error(("Cannot write Python exec wrapper for module %q as it doesn't exist."):format(module), 0)
    end
    return self:write_shell_exec_wrapper(
        new_executable_rel_path,
        ("%q -m %s"):format(
            path.concat {
                pypi.venv_path(self:get_install_path()),
                "python",
            },
            module
        )
    )
end

---@param new_executable_rel_path string Relative path to the executable file to create.
---@param target_executable_rel_path string
function InstallContext:write_exec_wrapper(new_executable_rel_path, target_executable_rel_path)
    if not self.fs:file_exists(target_executable_rel_path) then
        error(("Cannot write exec wrapper for path %q as it doesn't exist."):format(target_executable_rel_path), 0)
    end
    if platform.is.unix then
        self.fs:chmod_exec(target_executable_rel_path)
    end
    return self:write_shell_exec_wrapper(
        new_executable_rel_path,
        ("%q"):format(path.concat {
            self:get_install_path(),
            target_executable_rel_path,
        })
    )
end

local BASH_TEMPLATE = _.dedent [[
#!/usr/bin/env bash
%s
exec %s "$@"
]]

local BATCH_TEMPLATE = _.dedent [[
@ECHO off
%s
%s %%*
]]

---@param new_executable_rel_path string Relative path to the executable file to create.
---@param command string The shell command to run.
---@param env table<string, string>?
---@return string # The created executable filename.
function InstallContext:write_shell_exec_wrapper(new_executable_rel_path, command, env)
    if self.fs:file_exists(new_executable_rel_path) or self.fs:dir_exists(new_executable_rel_path) then
        error(("Cannot write exec wrapper to %q because the file already exists."):format(new_executable_rel_path), 0)
    end
    return platform.when {
        unix = function()
            local formatted_envs = _.map(function(pair)
                local var, value = pair[1], pair[2]
                return ("export %s=%q"):format(var, value)
            end, _.to_pairs(env or {}))

            self.fs:write_file(new_executable_rel_path, BASH_TEMPLATE:format(_.join("\n", formatted_envs), command))
            self.fs:chmod_exec(new_executable_rel_path)
            return new_executable_rel_path
        end,
        win = function()
            local executable_file = ("%s.cmd"):format(new_executable_rel_path)
            local formatted_envs = _.map(function(pair)
                local var, value = pair[1], pair[2]
                return ("SET %s=%s"):format(var, value)
            end, _.to_pairs(env or {}))

            self.fs:write_file(executable_file, BATCH_TEMPLATE:format(_.join("\n", formatted_envs), command))
            return executable_file
        end,
    }
end

---@param executable string
---@param rel_path string
function InstallContext:link_bin(executable, rel_path)
    self.links.bin[executable] = rel_path
    return self
end

InstallContext.CONTEXT_REQUEST = {}

---@generic T
---@param fn fun(context: InstallContext): T
---@return T
function InstallContext:execute(fn)
    local thread = coroutine.create(function(...)
        -- We wrap the function to allow it to be a spy instance (in which case it's not actually a function, but a
        -- callable metatable - coroutine.create strictly expects functions only)
        return fn(...)
    end)
    local step
    local ret_val
    step = function(...)
        local ok, result = coroutine.resume(thread, ...)
        if not ok then
            error(result, 0)
        elseif result == InstallContext.CONTEXT_REQUEST then
            step(self)
        elseif coroutine.status(thread) == "suspended" then
            -- yield to parent coroutine
            step(coroutine.yield(result))
        else
            ret_val = result
        end
    end
    step(self)
    return ret_val
end

---@async
function InstallContext:build_receipt()
    log.fmt_debug("Building receipt for %s", self.package)
    return Result.pcall(function()
        return self.receipt:with_name(self.package.name):with_completion_time(vim.loop.gettimeofday()):build()
    end)
end

function InstallContext:get_install_path()
    return self.location:package(self.package.name)
end

return InstallContext
