local AbstractPackage = require "mason-core.package.AbstractPackage"
local InstallLocation = require "mason-core.installer.InstallLocation"
local InstallRunner = require "mason-core.installer.InstallRunner"
local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local UninstallRunner = require "mason-core.installer.UninstallRunner"
local _ = require "mason-core.functional"
local fs = require "mason-core.fs"
local path = require "mason-core.path"
local platform = require "mason-core.platform"
local registry = require "mason-registry"
local Semaphore = require("mason-core.async.control").Semaphore

---@class Package : AbstractPackage
---@field spec RegistryPackageSpec
---@field local_semaphore Semaphore
local Package = {}
Package.__index = Package
setmetatable(Package, { __index = AbstractPackage })

---@param package_identifier string
---@return string, string?
Package.Parse = function(package_identifier)
    local name, version = unpack(vim.split(package_identifier, "@"))
    return name, version
end

---@alias PackageLanguage string

---@type table<PackageLanguage, PackageLanguage>
Package.Lang = setmetatable({}, {
    __index = function(s, lang)
        s[lang] = lang
        return s[lang]
    end,
})

---@enum PackageCategory
Package.Cat = {
    Compiler = "Compiler",
    Runtime = "Runtime",
    DAP = "DAP",
    LSP = "LSP",
    Linter = "Linter",
    Formatter = "Formatter",
}

---@alias PackageLicense string

---@type table<PackageLicense, PackageLicense>
Package.License = setmetatable({}, {
    __index = function(s, license)
        s[license] = license
        return s[license]
    end,
})

---@class RegistryPackageSourceVersionOverride : RegistryPackageSource
---@field constraint string

---@class RegistryPackageSource
---@field id string PURL-compliant identifier.
---@field version_overrides? RegistryPackageSourceVersionOverride[]

---@class RegistryPackageSchemas
---@field lsp string?

---@class RegistryPackageDeprecation
---@field since string
---@field message string

---@alias RegistryPackageSpecSchema
--- | '"registry+v1"'

---@class RegistryPackageSpec
---@field schema RegistryPackageSpecSchema
---@field name string
---@field description string
---@field homepage string
---@field licenses string[]
---@field languages string[]
---@field categories string[]
---@field deprecation RegistryPackageDeprecation?
---@field source RegistryPackageSource
---@field schemas RegistryPackageSchemas?
---@field bin table<string, string>?
---@field share table<string, string>?
---@field opt table<string, string>?

---@param spec RegistryPackageSpec
local function validate_spec(spec)
    if platform.cached_features["nvim-0.11"] ~= 1 then
        return
    end
    vim.validate("schema", spec.schema, _.equals "registry+v1", "registry+v1")
    vim.validate("name", spec.name, "string")
    vim.validate("description", spec.description, "string")
    vim.validate("homepage", spec.homepage, "string")
    vim.validate("licenses", spec.licenses, "table")
    vim.validate("categories", spec.categories, "table")
    vim.validate("languages", spec.languages, "table")
    vim.validate("source", spec.source, "table")
    vim.validate("bin", spec.bin, { "table", "nil" })
    vim.validate("share", spec.share, { "table", "nil" })
end

---@param spec RegistryPackageSpec
---@param reg RegistrySource
function Package:new(spec, reg)
    validate_spec(spec)
    ---@type Package
    local instance = AbstractPackage.new(self, spec, reg)
    instance.local_semaphore = Semaphore:new(1)
    return instance
end

---@param opts? PackageInstallOpts
---@param callback? InstallRunnerCallback
---@return InstallHandle
function Package:install(opts, callback)
    opts = opts or {}
    assert(not self:is_installing(), "Package is already installing.")
    assert(not self:is_uninstalling(), "Package is uninstalling.")
    opts = vim.tbl_extend("force", self.DEFAULT_INSTALL_OPTS, opts or {})

    local handle = self:new_install_handle(opts.location)
    registry:emit("package:install:handle", handle)
    local runner = InstallRunner:new(handle, AbstractPackage.SEMAPHORE)

    runner:execute(opts, callback)

    return handle
end

---@param opts? PackageUninstallOpts
---@param callback? fun(success: boolean, error: any)
function Package:uninstall(opts, callback)
    opts = opts or {}
    assert(self:is_installed(opts.location), "Package is not installed.")
    assert(not self:is_uninstalling(), "Package is already uninstalling.")
    local handle = self:new_uninstall_handle(opts.location)
    registry:emit("package:uninstall:handle", handle)
    local runner = UninstallRunner:new(handle, AbstractPackage.SEMAPHORE)
    runner:execute(opts, callback)
    return handle
end

---@param location? InstallLocation
function Package:is_installed(location)
    location = location or InstallLocation.global()
    local ok, stat = pcall(vim.loop.fs_stat, location:package(self.name))
    if not ok or not stat then
        return false
    end
    return stat.type == "directory"
end

function Package:get_lsp_settings_schema()
    local schema_file = InstallLocation.global()
        :share(path.concat { "mason-schemas", "lsp", ("%s.json"):format(self.name) })
    if fs.sync.file_exists(schema_file) then
        return Result.pcall(vim.json.decode, fs.sync.read_file(schema_file), {
            luanil = { object = true, array = true },
        }):ok()
    end
    return Optional.empty()
end

function Package:get_aliases()
    return require("mason-registry").get_package_aliases(self.name)
end

---@async
---@private
function Package:acquire_permit()
    return self.local_semaphore:acquire()
end

function Package:__tostring()
    return ("Package(name=%s)"):format(self.name)
end

return Package
