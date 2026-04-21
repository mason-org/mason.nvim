local Package = require "mason-core.package"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local InstallReceipt = require("mason-core.receipt").InstallReceipt
local InstallLocation = require "mason-core.installer.InstallLocation"
local fs = require "mason-core.fs"
local log = require "mason-core.log"

---@class SynthesizedRegistrySource : RegistrySource
---@field buffer table<string, Package>
local SynthesizedRegistrySource = {}
SynthesizedRegistrySource.__index = SynthesizedRegistrySource

function SynthesizedRegistrySource:new()
    ---@type SynthesizedRegistrySource
    local instance = {}
    setmetatable(instance, self)
    instance.buffer = {}
    return instance
end

function SynthesizedRegistrySource:is_installed()
    return true
end

---@return RegistryPackageSpec[]
function SynthesizedRegistrySource:get_all_package_specs()
    return {}
end

---@param pkg_name string
---@param receipt InstallReceipt
---@return Package
function SynthesizedRegistrySource:load_package(pkg_name, receipt)
    local installed_version = receipt:get_installed_package_version()
    local source = {
        id = ("pkg:mason/%s@%s"):format(pkg_name, installed_version or "N%2FA"), -- N%2FA = N/A
        install = function()
            error("This package can no longer be installed because it has been removed from the registry.", 0)
        end,
    }
    ---@type RegistryPackageSpec
    local spec = {
        schema = "registry+v1",
        name = pkg_name,
        description = "",
        categories = {},
        languages = {},
        homepage = "",
        licenses = {},
        deprecation = {
            since = installed_version or "N/A",
            message = "This package has been removed from the registry.",
        },
        source = source,
    }
    local existing_pkg = self.buffer[pkg_name]
    if existing_pkg then
        existing_pkg:update(spec, self)
        return existing_pkg
    else
        local pkg = Package:new(spec, self)
        self.buffer[pkg_name] = pkg
        return pkg
    end
end

---@param pkg_name string
---@return Package?
function SynthesizedRegistrySource:get_package(pkg_name)
    local receipt_path = InstallLocation.global():receipt(pkg_name)
    if fs.sync.file_exists(receipt_path) then
        local ok, receipt_json = pcall(vim.json.decode, fs.sync.read_file(receipt_path))
        if ok then
            local receipt = InstallReceipt.from_json(receipt_json)
            return self:load_package(pkg_name, receipt)
        else
            log.error("Failed to decode package receipt", pkg_name, receipt_json)
        end
    end
end

function SynthesizedRegistrySource:get_all_package_names()
    return vim.tbl_keys(self.buffer)
end

---@async
function SynthesizedRegistrySource:install()
    return Result.success()
end

function SynthesizedRegistrySource:get_display_name()
    return "SynthesizedRegistrySource"
end

function SynthesizedRegistrySource:serialize()
    return {}
end

---@param other SynthesizedRegistrySource
function SynthesizedRegistrySource:is_same_location(other)
    return true
end

function SynthesizedRegistrySource:__tostring()
    return "SynthesizedRegistrySource"
end

return SynthesizedRegistrySource
