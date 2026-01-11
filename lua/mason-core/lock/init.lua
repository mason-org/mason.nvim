local _ = require "mason-core.functional"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
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

local LOCKFILE_BACKUP_DIR = path.concat { vim.fn.stdpath "cache", "mason", "lockfiles" }

---@param file string
local function backup_lockfile(file)
    if not fs.sync.dir_exists(LOCKFILE_BACKUP_DIR) then
        fs.sync.mkdirp(LOCKFILE_BACKUP_DIR)
    end
    local base_backup_file = path.concat { LOCKFILE_BACKUP_DIR, ("mason-%s.lock"):format(os.date "%Y%m%d-%H%M%S") }
    local backup_file = base_backup_file
    local i = 1
    while i < 10 and fs.sync.file_exists(backup_file) do
        backup_file = base_backup_file .. "." .. i
        i = i + 1
    end
    fs.sync.copy_file(file, backup_file)
    return backup_file
end

---@param contents Lockfile
function M.write_lockfile(contents)
    local file = settings.current.lock.file
    local parser = require "mason-core.lock.parser"
    if settings.current.lock.backup and fs.sync.file_exists(file) then
        backup_lockfile(file)
    end
    local lockfile_dir = vim.fs.dirname(settings.current.lock.file)
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

    return lockfile
end

function M.create_lockfile()
    local file = settings.current.lock.file
    local lockfile = M.generate_lockfile()
    M.write_lockfile(lockfile)
    return lockfile
end

function M.get_lockfile_path()
    return settings.current.lock.file
end

---@return Lockfile?
function M.get_lockfile()
    local file = settings.current.lock.file
    if fs.sync.file_exists(file) then
        return require("mason-core.lock.parser").deserialize(file)
    end
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
        _.scheduler_wrap(function(pkg, receipt)
            if receipt:get_install_options().no_lock == true or settings.current.lock.enabled == false then
                return
            end
            local lockfile = M.get_lockfile() or M.create_lockfile()
            local ok, entry = pcall(generate_lockfile_entry, pkg)
            if ok then
                lockfile.body[pkg.name] = entry
                M.write_lockfile(lockfile)
            else
                log.error("Failed to generate lockfile entry for", pkg, entry)
            end
        end)
    )

    registry:on(
        "package:uninstall:success",
        ---@param pkg Package
        ---@param receipt InstallReceipt
        _.scheduler_wrap(function(pkg, receipt)
            if receipt:get_install_options().no_lock == true or settings.current.lock.enabled == false then
                return
            end
            local lockfile = M.get_lockfile() or M.create_lockfile()
            lockfile.body[pkg.name] = nil
            M.write_lockfile(lockfile)
        end)
    )
end

return M
