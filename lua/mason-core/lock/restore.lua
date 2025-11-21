local FileRegistrySource = require "mason-registry.sources.file"
local GitHubRegistrySource = require "mason-registry.sources.github"
local LuaRegistrySource = require "mason-registry.sources.lua"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local lock = require "mason-core.lock"

local M = {}

local providers = {
    ---@param registry_info LockfileRegistryGitHub
    ---@return GitHubRegistrySource
    github = function(registry_info, cache)
        local version, checksum = unpack(_.split("~", registry_info.integrity))
        local cache_key = registry_info.name .. registry_info.namespace .. version
        return cache(cache_key, function()
            local registry = GitHubRegistrySource:new {
                id = ("%s/%s"):format(registry_info.namespace, registry_info.name),
                name = registry_info.name,
                namespace = registry_info.namespace,
                version = version,
            }
            registry:install()
            return registry
        end)
    end,
    ---@param registry_info LockfileRegistryFile
    ---@return FileRegistrySource
    file = function(registry_info, cache)
        return cache(registry_info.path, function()
            local registry = FileRegistrySource:new {
                id = registry_info.path,
                path = registry_info.path,
            }
            registry:install()
            return registry
        end)
    end,
    ---@param registry_info LockfileRegistryLua
    ---@return LuaRegistrySource
    lua = function(registry_info, cache)
        return cache(registry_info.mod, function()
            local registry = LuaRegistrySource:new {
                id = registry_info.mod,
                mod = registry_info.mod,
            }
            registry:install()
            return registry
        end)
    end,
}

local IndexedCache = {
    __index = function(self, root_key)
        self[root_key] = {}
        setmetatable(self[root_key], {
            __call = function(cache, key, init)
                if not cache[key] then
                    local ok, registry = pcall(init)
                    if ok then
                        cache[key] = registry
                    else
                        error(registry)
                    end
                end
                return cache[key]
            end,
        })
        return self[root_key]
    end,
}

M.restore = a.scope(function()
    local lockfile = lock.get_lockfile()
    -- TODO probably do somewhere else
    assert(lockfile, "Lockfile is nil!")
    assert(lockfile.header and lockfile.header.version == "1", "Unknown lockfile version.")

    local cache = setmetatable({}, IndexedCache)

    ---@param pkg_name string
    ---@param metadata LockfilePackage
    local function get_package(pkg_name, metadata)
        local registry = metadata.registry
        if registry.proto == "github" then
            return providers.github(registry, cache.github):get_package(pkg_name)
        elseif registry.proto == "lua" then
            return providers.lua(registry, cache.lua):get_package(pkg_name)
        elseif registry.proto == "file" then
            return providers.file(registry, cache.file):get_package(pkg_name)
        end
        error(("Unknown registry protocol: %s."):format(registry.proto))
    end

    for pkg_name, metadata in pairs(lockfile.body) do
        ---@type Package
        local pkg = assert(get_package(pkg_name, metadata), ("Package %s not found."):format(pkg_name))
        assert(metadata.version, "Package version not specified in lockfile.")
        print("Installing", pkg_name, metadata.version)
        pkg:install({
            version = metadata.version,
            no_lock = true,
        }, function(success, err)
            print(pkg_name, "finished installing", success, err)
        end)
    end

    for _, registry in pairs(cache.github) do
        registry:uninstall()
    end
end)

M.restore()

return M
