local InstallContext = require "mason-core.installer.context"
local InstallHandle = require "mason-core.installer.InstallHandle"
local InstallLocation = require "mason-core.installer.InstallLocation"
local Result = require "mason-core.result"
local a = require "mason-core.async"
local registry = require "mason-registry"
local spy = require "luassert.spy"

local M = {}

---@param opts? { install_opts?: PackageInstallOpts, package?: string }
function M.create_context(opts)
    local pkg = registry.get_package(opts and opts.package or "dummy")
    local handle = InstallHandle:new(pkg, InstallLocation.global())
    local context = InstallContext:new(handle, opts and opts.install_opts or {})
    context.spawn = setmetatable({}, {
        __index = function(s, cmd)
            s[cmd] = spy.new(function()
                return Result.success { stdout = nil, stderr = nil }
            end)
            return s[cmd]
        end,
    })
    context.cwd:initialize():get_or_throw()
    return context
end

---@param pkg AbstractPackage
---@param opts? PackageInstallOpts
function M.sync_install(pkg, opts)
    return a.run_blocking(function()
        return a.wait(function(resolve, reject)
            pkg:install(opts, function(success, result)
                (success and resolve or reject)(result)
            end)
        end)
    end)
end

---@param pkg AbstractPackage
---@param opts? PackageUninstallOpts
function M.sync_uninstall(pkg, opts)
    return a.run_blocking(function()
        return a.wait(function(resolve, reject)
            pkg:uninstall(opts, function(success, result)
                (success and resolve or reject)(result)
            end)
        end)
    end)
end

---@param runner InstallRunner
---@param opts PackageInstallOpts
function M.sync_runner_execute(runner, opts)
    local callback = spy.new()
    runner:execute(opts, callback)
    assert.wait(function()
        assert.spy(callback).was_called()
    end)
    return callback
end

return M
