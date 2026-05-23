local _ = require "mason-core.functional"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local registry = require "mason-registry"
local settings = require "mason.settings"

local M = {}

---@class LockfileHeader
---@field version '"1"'

---@class LockfileRegistryGitHub
---@field proto '"github"'
---@field integrity string
---@field namespace string
---@field name string

---@class LockfileRegistryFile
---@field proto '"file"'
---@field path string

---@class LockfileRegistryLua
---@field proto '"lua"'
---@field mod string

---@alias LockfileRegistry LockfileRegistryGitHub | LockfileRegistryFile | LockfileRegistryLua

---@class LockfilePackage
---@field version string
---@field registry LockfileRegistry

---@class Lockfile
---@field header LockfileHeader
---@field body table<string, LockfilePackage>

local LOCKFILE_BACKUP_DIR = vim.fs.joinpath(vim.fn.stdpath "cache", "mason", "lockfiles")

---@param file string
local function gzip(file)
    if vim.fn.executable "gzip" == 1 then
        vim.system({ "gzip", file }, { text = true }, function(obj)
            if obj.code ~= 0 or obj.signal ~= 0 then
                log.warn("Failed to gzip backup file.", obj.stdout, obj.stderr)
            end
        end)
    end
end

---@param file string
local function backup_lockfile(file)
    if not fs.sync.dir_exists(LOCKFILE_BACKUP_DIR) then
        fs.sync.mkdirp(LOCKFILE_BACKUP_DIR)
    end
    -- We store the contents in memory and write a new file in the backup location in order to avoid race conditions.
    local contents = fs.sync.read_file(file)
    local seconds, microseconds = vim.uv.gettimeofday()
    local milliseconds = seconds * 1000 + math.floor(microseconds / 1000)
    local base_backup_file = vim.fs.joinpath(LOCKFILE_BACKUP_DIR, ("mason-%s.lock"):format(milliseconds))
    local backup_file = base_backup_file
    local i = 1
    while i < 5 and fs.sync.file_exists(backup_file) do
        backup_file = base_backup_file .. "." .. i
        i = i + 1
    end
    fs.sync.write_file(backup_file, contents)
    gzip(backup_file)
    return backup_file
end

---@param contents Lockfile
function M.write_lockfile(contents)
    log.debug "Writing lockfile"
    local file = settings.current.lockfile.path
    local parser = require "mason-core.lock.parser"
    if settings.current.lockfile.backup.enabled and fs.sync.file_exists(file) then
        backup_lockfile(file)
    end
    local lockfile_dir = vim.fs.dirname(settings.current.lockfile.path)
    if not fs.sync.dir_exists(lockfile_dir) then
        fs.sync.mkdirp(lockfile_dir)
    end
    fs.sync.write_file(file, parser.serialize(contents))
end

---@param pkg Package
---@return LockfilePackage
local function generate_lockfile_entry(pkg)
    local version = assert(pkg:get_installed_version(), "Unable to retrieve package version.")
    local registry = pkg:get_receipt():map(_.prop "registry"):or_else_throw "Unable to retrieve registry from receipt."
    if registry.proto == "github" then
        registry.integrity = registry.version .. "~" .. registry.checksums["registry.json"]
        registry.version = nil
        registry.checksums = nil
    end
    return {
        version = version,
        registry = registry,
    }
end

---@return Lockfile
function M.generate_lockfile()
    local lockfile = {
        header = {
            version = "1",
        },
        body = {},
    }

    for __, pkg in ipairs(registry.get_installed_packages()) do
        local ok, entry = pcall(generate_lockfile_entry, pkg)
        if ok then
            lockfile.body[pkg.name] = entry
        else
            log.warn("Unable to generate lockfile entry for", pkg, entry)
        end
    end

    log.fmt_debug("Generating lockfile with %d packages.", _.size(lockfile.body))

    return lockfile
end

function M.create_lockfile()
    local file = settings.current.lockfile.path
    log.fmt_debug("Creating lockfile at %s.", file)
    local lockfile = M.generate_lockfile()
    M.write_lockfile(lockfile)
    return lockfile
end

function M.get_lockfile_path()
    return settings.current.lockfile.path
end

---@return Lockfile?
function M.get_lockfile()
    local file = settings.current.lockfile.path
    if fs.sync.file_exists(file) then
        return require("mason-core.lock.parser").deserialize_file(file)
    end
end

function M.has_lockfile()
    return fs.sync.file_exists(settings.current.lockfile.path)
end

local has_init = false
function M.init()
    if has_init then
        return
    end
    has_init = true

    registry:on(
        "package:install:success",
        ---@param pkg Package
        ---@param receipt InstallReceipt
        function(pkg, receipt)
            if receipt:get_install_options().no_lock == true then
                return log.debug "Package was installed but not updating lockfile because no_lock was enabled."
            end
            if settings.current.lockfile.enabled == false then
                return log.debug "Package was installed but not updating lockfile because lockfile is disabled via settings."
            end
            local lockfile = M.get_lockfile()
            if not lockfile then
                return log.fmt_warn(
                    "Lockfile is enabled but a lockfile could not be found at %s. Create a lockfile first through :MasonLock.",
                    settings.current.lockfile.path
                )
            end
            local ok, entry = pcall(generate_lockfile_entry, pkg)
            if ok then
                lockfile.body[pkg.name] = entry
                M.write_lockfile(lockfile)
            else
                log.error("Failed to generate lockfile entry for", pkg, entry)
            end
        end
    )

    registry:on(
        "package:uninstall:success",
        ---@param pkg Package
        ---@param receipt InstallReceipt
        ---@param opts PackageUninstallOpts
        function(pkg, receipt, opts)
            if opts.no_lock then
                return
            end
            if settings.current.lockfile.enabled == false then
                return log.debug "Package was uninstalled but not updating lockfile because lockfile is disabled via settings."
            end
            local lockfile = M.get_lockfile()
            if not lockfile then
                return log.fmt_warn(
                    "Lockfile is enabled but a lockfile could not be found at %s. Create a lockfile first through :MasonLock.",
                    settings.current.lockfile.path
                )
            end
            lockfile.body[pkg.name] = nil
            M.write_lockfile(lockfile)
        end
    )
end

return M
