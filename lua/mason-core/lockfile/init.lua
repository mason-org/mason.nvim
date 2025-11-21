local _ = require "mason-core.functional"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local registry = require "mason-registry"
local settings = require "mason.settings"
local sources = require "mason-registry.sources"

local LOCKFILE_BACKUP_DIR = path.concat { vim.fn.stdpath "cache", "mason", "lockfiles" }

local M = {}

---@class Lockfile
---@field schema_version 1
---@field registries table<string, string>
---@field packages table<string, string>

---@param file string
local function backup_lockfile(file)
    if not fs.sync.dir_exists(LOCKFILE_BACKUP_DIR) then
        fs.sync.mkdirp(LOCKFILE_BACKUP_DIR)
    end
    local old_content = fs.sync.read_file(file)
    local ok, minified_json = pcall(_.compose(vim.json.encode, vim.json.decode), old_content)
    local backup_file = path.concat { LOCKFILE_BACKUP_DIR, ("mason-lock.%s.json"):format(os.date "%Y%m%d") }
    if ok then
        fs.sync.write_file(backup_file, minified_json)
    end
    return backup_file
end

---@param file string
---@param contents Lockfile
function M.write_lockfile(file, contents)
    local pretty_json = require "mason-core.pretty_json"
    if fs.sync.file_exists(file) then
        backup_lockfile(file)
    end
    local lockfile_dir = vim.fn.fnamemodify(settings.current.lock.file, ":p:h")
    if not fs.sync.dir_exists(lockfile_dir) then
        fs.sync.mkdirp(lockfile_dir)
    end
    fs.sync.write_file(file, pretty_json(contents))
end

---@param lockfile Lockfile
local function set_registries(lockfile)
    for source in sources.iter() do
        source:get_installed_version():if_present(function(version)
            lockfile.registries[source.id] = version
        end)
    end
end

---@return Lockfile
function M.generate_lockfile()
    local lockfile = {
        schema_version = 1,
        registries = vim.empty_dict(),
        packages = vim.empty_dict(),
    }

    set_registries(lockfile)

    for _, pkg in ipairs(registry.get_installed_packages()) do
        pkg:get_installed_version():if_present(function(version)
            lockfile.packages[pkg.name] = version
        end)
    end

    return lockfile
end

function M.create_lockfile()
    local file = settings.current.lock.file
    local lockfile = M.generate_lockfile()
    M.write_lockfile(file, lockfile)
    return lockfile
end

---@return Lockfile?
function M.get_lockfile()
    local file = settings.current.lock.file
    if fs.sync.file_exists(file) then
        ---@type boolean, Lockfile
        local ok, lockfile = pcall(vim.json.decode, fs.sync.read_file(file))
        if ok then
            return lockfile
        else
            log.error("Failed to read corrupt lockfile.", lockfile)
            vim.notify(("Failed to read corrupt lockfile at %s."):format(file), vim.log.levels.ERROR)
        end
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
