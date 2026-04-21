local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local util = require "mason-registry.sources.util"

---@class LuaRegistrySourceSpec
---@field id string
---@field mod string

---@class LuaRegistrySource : RegistrySource
---@field private spec LuaRegistrySourceSpec
---@field buffer { specs: RegistryPackageSpec[], instances: table<string, Package> }?
local LuaRegistrySource = {}
LuaRegistrySource.__index = LuaRegistrySource

---@param spec LuaRegistrySourceSpec
function LuaRegistrySource:new(spec)
    ---@type LuaRegistrySource
    local instance = {}
    setmetatable(instance, LuaRegistrySource)
    instance.id = spec.id
    instance.spec = spec
    return instance
end

---@param pkg_name string
---@return Package?
function LuaRegistrySource:get_package(pkg_name)
    return self:get_buffer().instances[pkg_name]
end

---@param specs RegistryPackageSpec[]
function LuaRegistrySource:reload(specs)
    self.buffer = _.assoc("specs", specs, self.buffer or {})
    self.buffer.instances = _.compose(
        _.index_by(_.prop "name"),
        _.map(util.hydrate_package(self, self.buffer.instances or {}))
    )(self:get_all_package_specs())
    return self.buffer
end

function LuaRegistrySource:install()
    return Result.try(function(try)
        local index = try(Result.pcall(require, self.spec.mod))
        ---@type RegistryPackageSpec[]
        local specs = {}

        for _, mod in pairs(index) do
            table.insert(specs, try(Result.pcall(require, mod)))
        end

        try(Result.pcall(self.reload, self, specs))
    end)
end

---@return string[]
function LuaRegistrySource:get_all_package_names()
    return _.map(_.prop "name", self:get_all_package_specs())
end

---@return RegistryPackageSpec[]
function LuaRegistrySource:get_all_package_specs()
    return _.filter_map(util.map_registry_spec, self:get_buffer().specs)
end

function LuaRegistrySource:get_buffer()
    return self.buffer or {
        specs = {},
        instances = {},
    }
end

function LuaRegistrySource:is_installed()
    return self.buffer ~= nil
end

function LuaRegistrySource:get_display_name()
    if self:is_installed() then
        return ("require(%q)"):format(self.spec.mod)
    else
        return ("require(%q) [uninstalled]"):format(self.spec.mod)
    end
end

function LuaRegistrySource:serialize()
    return {
        proto = "lua",
        mod = self.id,
    }
end

---@param other LuaRegistrySource
function LuaRegistrySource:is_same_location(other)
    return self.id == other.id
end

function LuaRegistrySource:__tostring()
    return ("LuaRegistrySource(mod=%s)"):format(self.spec.mod)
end

return LuaRegistrySource
