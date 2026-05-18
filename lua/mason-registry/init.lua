local EventEmitter = require "mason-core.EventEmitter"
local InstallLocation = require "mason-core.installer.InstallLocation"
local log = require "mason-core.log"
local path = require "mason-core.path"
local settings = require "mason.settings"
local uv = vim.loop
local LazySourceCollection = require "mason-registry.sources"

-- singleton
local Registry = EventEmitter:new()

Registry.sources = LazySourceCollection:new(path.concat { vim.fn.stdpath "cache", "mason-registry-update" })
Registry.system_sources =
    LazySourceCollection:new(path.concat { vim.fn.stdpath "cache", "mason-system-registry-update" }, true)

---@type table<string, string[]>
Registry.aliases = {}

---@param pkg_name string
function Registry.is_installed(pkg_name)
    local stat = uv.fs_stat(InstallLocation.global():package(pkg_name))
    return stat ~= nil and stat.type == "directory"
end

---Returns an instance of the Package class if the provided package name exists. This function errors if a package
---cannot be found.
---@param pkg_name string
---@return Package
function Registry.get_package(pkg_name)
    for source in Registry.sources:iterate() do
        local pkg = source:get_package(pkg_name)
        if pkg then
            return pkg
        end
    end
    log.fmt_error("Cannot find package %q.", pkg_name)
    error(("Cannot find package %q."):format(pkg_name))
end

function Registry.has_package(pkg_name)
    local ok = pcall(Registry.get_package, pkg_name)
    return ok
end

---Returns an instance of the Package class if the provided package name exists. This function errors if a package
---cannot be found.
---@param pkg_name string
---@return Package
function Registry.get_system_package(pkg_name)
    for source in Registry.system_sources:iterate() do
        local pkg = source:get_package(pkg_name)
        if pkg then
            return pkg
        end
    end
    log.fmt_error("Cannot find system package %q.", pkg_name)
    error(("Cannot find system package %q."):format(pkg_name))
end

function Registry.get_installed_package_names()
    local fs = require "mason-core.fs"
    if not fs.sync.dir_exists(InstallLocation.global():package()) then
        return {}
    end
    local entries = fs.sync.readdir(InstallLocation:global():package())
    local directories = {}
    for _, entry in ipairs(entries) do
        if entry.type == "directory" then
            directories[#directories + 1] = entry.name
        end
    end
    return directories
end

function Registry.get_installed_packages()
    return vim.tbl_map(Registry.get_package, Registry.get_installed_package_names())
end

function Registry.get_all_package_names()
    local pkgs = {}
    for source in Registry.sources:iterate() do
        for _, name in ipairs(source:get_all_package_names()) do
            pkgs[name] = true
        end
    end
    return vim.tbl_keys(pkgs)
end

function Registry.get_all_packages()
    local _ = require "mason-core.functional"
    local packages =
        _.uniq_by(_.identity, _.concat(Registry.get_all_package_names(), Registry.get_installed_package_names()))
    return vim.tbl_map(Registry.get_package, packages)
end

function Registry.get_all_package_specs()
    local specs = {}
    for source in Registry.sources:iterate() do
        for _, spec in ipairs(source:get_all_package_specs()) do
            if not specs[spec.name] then
                specs[spec.name] = spec
            end
        end
    end
    return vim.tbl_values(specs)
end

---Register aliases for the specified packages
---@param new_aliases table<string, string[]>
function Registry.register_package_aliases(new_aliases)
    for pkg_name, pkg_aliases in pairs(new_aliases) do
        Registry.aliases[pkg_name] = Registry.aliases[pkg_name] or {}
        for _, alias in pairs(pkg_aliases) do
            if alias ~= pkg_name then
                table.insert(Registry.aliases[pkg_name], alias)
            end
        end
    end
end

---@param name string
function Registry.get_package_aliases(name)
    return Registry.aliases[name] or {}
end

---@async
---@param sources LazySourceCollection
local function update(sources)
    local installer = require "mason-registry.installer"

    if sources.install_channel then
        log.debug "Registry update already in progress."
        return sources.install_channel:receive():get_or_throw()
    else
        log.debug "Updating the registry."
        Registry:emit("update:start", sources)
        return installer
            .install(sources, function(finished, all)
                Registry:emit("update:progress", finished, all)
            end)
            :on_success(function(updated_registries)
                log.fmt_debug("Successfully updated %d registries.", #updated_registries)
                Registry:emit("update:success", updated_registries)
            end)
            :on_failure(function(errors)
                log.error("Failed to update registries.", errors)
                Registry:emit("update:failed", errors)
            end)
            :get_or_throw()
    end
end

---@alias RegistryUpdateCallback fun(success: boolean, updated_registries: RegistrySource[])

---@param callback? RegistryUpdateCallback
function Registry.update_system(callback)
    local a = require "mason-core.async"
    local noop = function() end
    a.run(update, callback or noop, Registry.system_sources)
end

---@param callback? RegistryUpdateCallback
function Registry.update(callback)
    local a = require "mason-core.async"
    local noop = function() end
    a.run(update, callback or noop, Registry.sources)
end

---@param sources LazySourceCollection
---@param callback? RegistryUpdateCallback
local function refresh(sources, callback)
    if not settings.current.registry_cache.refresh then
        log.debug "Not performing a registry refresh as it's disabled in settings."
        if callback then
            return callback(true, {})
        end
        return true, {}
    end
    local a = require "mason-core.async"

    local state = sources:get_install_state()
    if state and sources:is_all_installed() then
        local registry_age = os.time() - state.timestamp

        if registry_age <= settings.current.registry_cache.duration and state.checksum == sources:checksum() then
            log.fmt_debug(
                "Registry refresh is not necessary yet. Registry age=%d, checksum=%s",
                registry_age,
                state.checksum
            )
            if callback then
                return callback(true, {})
            end
            return true, {}
        end
    end

    if not callback then
        -- We don't want to error in the synchronous version because of how this function is recommended to be used in
        -- 3rd party code. If accessing the update result is required, users are recommended to pass a callback.
        return pcall(a.run_blocking, update, sources)
    else
        a.run(update, callback, sources)
    end
end

---@param callback? RegistryUpdateCallback
function Registry.refresh(callback)
    log.debug "Refreshing the registry."
    return refresh(Registry.sources, callback)
end

---@param callback? RegistryUpdateCallback
function Registry.refresh_system(callback)
    log.debug "Refreshing the system registry."
    return refresh(Registry.system_sources, callback)
end

return Registry
