local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local registry = require "mason-registry"
local settings = require "mason.settings"
local OneShotChannel = require("mason-core.async.control").OneShotChannel

---@class SystemPackage
---@field name string
---@field condition? fun(): bool
local SystemPackage = {}
SystemPackage.__index = SystemPackage

---@type table<string, OneShotChannel>
SystemPackage.channels = {}

function SystemPackage:new(system_pkg_name)
    ---@type SystemPackage
    local instance = {}
    setmetatable(instance, self)
    instance.name = system_pkg_name
    return instance
end

function SystemPackage:conditional(fn)
    self.condition = fn
    return self
end

---@async
function SystemPackage:get_package()
    a.scheduler()
    pcall(a.wait, registry.refresh_system)
    if not registry.has_system_package(self.name) then
        -- Force update to the very latest registry version
        pcall(a.wait, registry.update)
    end
    if not registry.has_system_package(self.name) then
        return Result.failure("Unable to find system package " .. self.name)
    end
    return Result.pcall(registry.get_system_package, self.name)
end

---@async
---@return Result<boolean>
function SystemPackage:needs_install()
    return Result.try(function(try)
        if self.condition and not self.condition() then
            return false
        end
        local pkg = try(self:get_package())
        if not pkg:is_installed() or pkg:is_installing() then
            return true
        end
        if pkg:get_installed_version() ~= pkg:get_latest_version() then
            return true
        end
        return false
    end)
end

---@async
function SystemPackage:await_channel()
    assert(SystemPackage.channels[self.name], "Tried to await non-existing channel.")
    local success, result = SystemPackage.channels[self.name]:receive()
    if not success then
        return Result.failure("Failed to install system package " .. self.name .. ". Error: " .. result)
    end
    return Result.success()
end

---@async
---@return Result
function SystemPackage:install()
    return Result.try(function(try)
        local pkg = try(self:get_package())
        if not pkg:is_installing() then
            local channel = OneShotChannel:new()
            SystemPackage.channels[self.name] = channel
            pkg:install({}, function(success, result)
                channel:send(success, result)
            end)
        end
        return self:await_channel()
    end)
end

function SystemPackage:__tostring()
    return ("SystemPackage(name=%s)"):format(self.name)
end

SystemPackage.sfw = SystemPackage:new("sfw@latest"):conditional(function()
    return settings.current.firewall.enabled and settings.current.firewall.auto_managed
end)

return SystemPackage
