local _ = require "mason-core.functional"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local registry = require "mason-registry"
local settings = require "mason.settings"
local sources = require "mason-registry.sources"

local LOCKFILE_BACKUP_DIR = path.concat { vim.fn.stdpath "cache", "mason", "lockfiles" }

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

---@param file string
local function backup_lockfile(file)
    if not fs.sync.dir_exists(LOCKFILE_BACKUP_DIR) then
        fs.sync.mkdirp(LOCKFILE_BACKUP_DIR)
    end
    -- TODO needs more unique name
    local backup_file = path.concat { LOCKFILE_BACKUP_DIR, ("mason-%s.lock"):format(os.date "%Y%m%d") }
    fs.sync.copy_file(file, backup_file)
    -- TODO gzip and rotate old backups?
    return backup_file
end

---@param file string
---@param contents Lockfile
function M.write_lockfile(file, contents)
    local parser = require "mason-core.lock.parser"
    if fs.sync.file_exists(file) and settings.current.lock.backup then
        backup_lockfile(file)
    end
    local lockfile_dir = vim.fs.dirname(settings.current.lock.file)
    if not fs.sync.dir_exists(lockfile_dir) then
        fs.sync.mkdirp(lockfile_dir)
    end
    fs.sync.write_file(file, parser.serialize(contents))
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
        -- TODO error if not present
        -- TODO also set registry, if registry is not in receipt do error
        local version = pkg:get_installed_version()
        if version then
            pkg:get_receipt():map(_.prop "registry"):if_present(function(registry)
                if registry.proto == "github" then
                    registry.integrity = registry.version .. "~" .. registry.checksums["registry.json"]
                    registry.version = nil
                    registry.checksums = nil
                end
                lockfile.body[pkg.name] = {
                    version = version,
                    registry = registry,
                }
            end)
        end
    end

    return lockfile
end

function M.create_lockfile()
    local file = settings.current.lock.file
    local lockfile = M.generate_lockfile()
    M.write_lockfile(file, lockfile)
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
    error("No lockfile TODO FIXME")
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
            if opts.lockfile == false or settings.current.lock.enabled == false then
                return
            end
            pkg:get_installed_version():if_present(function(version)
                local lockfile = M.get_lockfile() or M.create_lockfile()
                lockfile.packages[pkg.name] = version
                set_registries(lockfile)
                M.write_lockfile(settings.current.lock.file, lockfile)
            end)
        end)
    )

    registry:on(
        "package:uninstall:success",
        ---@param pkg Package
        _.scheduler_wrap(function(pkg)
            if opts.lockfile == false or settings.current.lock.enabled == false then
                return
            end
            local lockfile = M.get_lockfile() or M.create_lockfile()
            lockfile.packages[pkg.name] = nil
            M.write_lockfile(settings.current.lock.file, lockfile)
        end)
    )
end

return M
