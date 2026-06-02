local EventEmitter = require "mason-core.EventEmitter"
local FileRegistrySource = require "mason-registry.sources.file"
local GitHubRegistrySource = require "mason-registry.sources.github"
local LuaRegistrySource = require "mason-registry.sources.lua"
local Optional = require "mason-core.optional"
local Registry = require "mason-registry"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"

local providers = {
    ---@param registry_info LockfileRegistryGitHub
    ---@return GitHubRegistrySource
    github = function(registry_info, cache)
        local version, checksum = unpack(_.split("~", registry_info.integrity))
        local cache_key = registry_info.name .. registry_info.namespace .. version
        return cache(cache_key, function()
            return GitHubRegistrySource:new {
                id = ("%s/%s"):format(registry_info.namespace, registry_info.name),
                name = registry_info.name,
                namespace = registry_info.namespace,
                version = version,
            }
        end)
    end,
    ---@param registry_info LockfileRegistryFile
    ---@return FileRegistrySource
    file = function(registry_info, cache)
        return cache(registry_info.path, function()
            return FileRegistrySource:new {
                id = registry_info.path,
                path = registry_info.path,
            }
        end)
    end,
    ---@param registry_info LockfileRegistryLua
    ---@return LuaRegistrySource
    lua = function(registry_info, cache)
        return cache(registry_info.mod, function()
            return LuaRegistrySource:new {
                id = registry_info.mod,
                mod = registry_info.mod,
            }
        end)
    end,
}

---@class LockfileInstallGroup
---@field packages table<Package, LockfilePackage>
---@field unavailable_packages table<string, { error: string, metadata: LockfilePackage }>
local LockfileInstallGroup = {}
LockfileInstallGroup.__index = LockfileInstallGroup

---@param packages table<Package, LockfilePackage>
---@param unavailable_packages table<string, { error: string, metadata: LockfilePackage }>
function LockfileInstallGroup:new(packages, unavailable_packages)
    ---@type LockfileInstallGroup
    local instance = {}
    setmetatable(instance, self)
    instance.packages = packages
    instance.unavailable_packages = unavailable_packages
    instance.handles = {}
    instance.installed = {
        completed = {},
        failed = {},
    }
    return instance
end

---@async
---@param handlers { on_handle: fun(handle: InstallHandle), on_completion: fun(pkg: Package, success: boolean, result: any) }
function LockfileInstallGroup:install(handlers, callback)
    local thunks = {}
    local sorted_packages = _.sort_by(_.prop "name", _.keys(self.packages))
    for __, pkg in ipairs(sorted_packages) do
        table.insert(thunks, function()
            local metadata = self.packages[pkg]
            a.wait(function(resolve)
                self.handles[pkg] = pkg:install({
                    no_lock = true,
                    version = metadata.version,
                }, function(success, result)
                    if success then
                        table.insert(self.installed.completed, pkg)
                    else
                        table.insert(self.installed.failed, pkg)
                    end
                    if handlers and handlers.on_completion then
                        handlers.on_completion(pkg, success, result)
                    end
                    resolve()
                end)
                if handlers and handlers.on_handle then
                    handlers.on_handle(self.handles[pkg])
                end
            end)
        end)
    end
    a.wait_all(thunks)
end

local RegistryCache = {
    __index = function(self, root_key)
        self[root_key] = {}
        setmetatable(self[root_key], {
            __call = function(cache, key, init)
                if not cache[key] then
                    cache[key] = init()
                end
                return cache[key]
            end,
        })
        return self[root_key]
    end,
}

---@class LockfileRestore
---@field lockfile Lockfile
---@field registry_cache table
local LockfileRestore = {}
LockfileRestore.__index = LockfileRestore

---@param lockfile Lockfile
function LockfileRestore:new(lockfile)
    ---@type LockfileRestore
    local instance = {}
    setmetatable(instance, self)
    instance.lockfile = lockfile
    instance.registry_cache = setmetatable({}, RegistryCache)
    return instance
end

function LockfileRestore:get_package_count()
    return _.size(self.lockfile.body)
end

function LockfileRestore:get_packages()
    return self.lockfile.body
end

---@param registry_info LockfileRegistry
---@return RegistrySource
function LockfileRestore:get_registry(registry_info)
    if registry_info.proto == "github" then
        return providers.github(registry_info, self.registry_cache.github)
    elseif registry_info.proto == "lua" then
        return providers.lua(registry_info, self.registry_cache.lua)
    elseif registry_info.proto == "file" then
        return providers.file(registry_info, self.registry_cache.file)
    end
end

---@async
---@param pkg_name string
---@param metadata LockfilePackage
function LockfileRestore:resolve_package(pkg_name, metadata)
    return Result.try(function(try)
        local ephemeral_registry = self:get_registry(metadata.registry)
        if not ephemeral_registry:is_installed() then
            if metadata.registry.proto == "github" then
                local _, checksum = unpack(_.split("~", metadata.registry.integrity))
                try(ephemeral_registry:install { checksum = checksum })
            else
                try(ephemeral_registry:install())
            end
        end
        return Optional.of_nilable(ephemeral_registry:get_package(pkg_name)):ok_or "Unable to find package."
    end)
end

---@async
function LockfileRestore:prepare()
    local available = {}
    local unavailable = {}
    for pkg_name, metadata in pairs(self.lockfile.body) do
        self:resolve_package(pkg_name, metadata)
            :on_success(function(pkg)
                available[pkg] = metadata
            end)
            :on_failure(function(err)
                unavailable[pkg_name] = {
                    error = err,
                    metadata = metadata,
                }
            end)
    end
    return LockfileInstallGroup:new(available, unavailable)
end

function LockfileRestore:cleanup()
    for _, registry in pairs(self.registry_cache.github) do
        if not Registry.sources:contains(registry) then
            registry:uninstall()
        end
    end
end

return LockfileRestore
