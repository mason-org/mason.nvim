local EventEmitter = require "mason-core.EventEmitter"
local Optional = require "mason-core.optional"
local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"
local registry = require "mason-registry"

local is_not_nil = _.complement(_.is_nil)
local is_registry_schema_id = _.matches "^registry%+v[1-9]+$"
local is_registry_spec = _.prop_satisfies(_.all_pass { is_not_nil, is_registry_schema_id }, "schema")

---@class Package : EventEmitter
---@field name string
---@field spec RegistryPackageSpec | PackageSpec
---@field private handle InstallHandle The currently associated handle.
local Package = setmetatable({}, { __index = EventEmitter })

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

local PackageMt = { __index = Package }

---@class PackageSpec
---@field name string
---@field desc string
---@field homepage string
---@field categories PackageCategory[]
---@field languages PackageLanguage[]
---@field install async fun(ctx: InstallContext)

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

---@class RegistryPackageSpec
---@field schema '"registry+v1"'
---@field name string
---@field description string
---@field homepage string
---@field licenses string[]
---@field languages string[]
---@field categories string[]
---@field source RegistryPackageSource
---@field deprecation RegistryPackageDeprecation?
---@field schemas RegistryPackageSchemas?
---@field bin table<string, string>?
---@field share table<string, string>?
---@field opt table<string, string>?

---@param spec PackageSpec | RegistryPackageSpec
local function validate_spec(spec)
    if platform.cached_features["nvim-0.11"] ~= 1 then
        return
    end
    if is_registry_spec(spec) then
        vim.validate("name", spec.name, "string")
        vim.validate("description", spec.description, "string")
        vim.validate("homepage", spec.homepage, "string")
        vim.validate("licenses", spec.licenses, "table")
        vim.validate("categories", spec.categories, "table")
        vim.validate("languages", spec.languages, "table")
        vim.validate("source", spec.source, "table")
        vim.validate("bin", spec.bin, { "table", "nil" })
        vim.validate("share", spec.share, { "table", "nil" })
    else
        vim.validate("name", spec.name, "string")
        vim.validate("desc", spec.desc, "string")
        vim.validate("homepage", spec.homepage, "string")
        vim.validate("categories", spec.categories, "table")
        vim.validate("languages", spec.languages, "table")
        vim.validate("install", spec.install, "function")
    end
end

---@param spec PackageSpec | RegistryPackageSpec
function Package.new(spec)
    validate_spec(spec)
    return EventEmitter.init(setmetatable({
        name = spec.name, -- for convenient access
        spec = spec,
    }, PackageMt))
end

function Package:new_handle()
    self:get_handle():if_present(function(handle)
        assert(handle:is_closed(), "Cannot create new handle because existing handle is not closed.")
    end)
    log.fmt_trace("Creating new handle for %s", self)
    local InstallationHandle = require "mason-core.installer.handle"
    local handle = InstallationHandle.new(self)
    self.handle = handle

    -- Ideally we'd decouple this and leverage Mason's event system, but to allow loading as little as possible during
    -- setup (i.e. not load modules related to Mason's event system) of the mason.nvim plugin we explicitly call into
    -- terminator here.
    require("mason-core.terminator").register(handle)

    self:emit("handle", handle)
    registry:emit("package:handle", self, handle)

    return handle
end

---@alias PackageInstallOpts { version?: string, debug?: boolean, target?: string, force?: boolean, strict?: boolean }

---@param opts? PackageInstallOpts
---@return InstallHandle
function Package:install(opts)
    opts = opts or {}
    return self:get_handle()
        :map(function(handle)
            if not handle:is_closed() then
                log.fmt_debug("Handle %s already exist for package %s", handle, self)
                return handle
            end
        end)
        :or_else_get(function()
            local handle = self:new_handle()
            a.run(
                require("mason-core.installer").execute,
                ---@param success boolean
                ---@param result Result
                function(success, result)
                    if not success then
                        -- Installer failed abnormally (i.e. unexpected exception in the installer code itself).
                        log.error("Unexpected error", result)
                        handle.stdio.sink.stderr(tostring(result))
                        handle.stdio.sink.stderr "\nInstallation failed abnormally. Please report this error."
                        self:emit("install:failed", handle)
                        registry:emit("package:install:failed", self, handle)

                        -- We terminate _after_ emitting failure events because [termination -> failed] have different
                        -- meaning than [failed -> terminate] ([termination -> failed] is interpreted as a triggered
                        -- termination).
                        if not handle:is_closed() and not handle.is_terminated then
                            handle:terminate()
                        end
                        return
                    end
                    result
                        :on_success(function()
                            self:emit("install:success", handle)
                            registry:emit("package:install:success", self, handle)
                        end)
                        :on_failure(function()
                            self:emit("install:failed", handle)
                            registry:emit("package:install:failed", self, handle)
                        end)
                end,
                handle,
                opts
            )
            return handle
        end)
end

function Package:uninstall()
    local was_unlinked = self:unlink()
    if was_unlinked then
        self:emit "uninstall:success"
        registry:emit("package:uninstall:success", self)
    end
    return was_unlinked
end

function Package:unlink()
    log.fmt_trace("Unlinking %s", self)
    local install_path = self:get_install_path()
    -- 1. Unlink
    self:get_receipt():if_present(function(receipt)
        local linker = require "mason-core.installer.linker"
        linker.unlink(self, receipt):get_or_throw()
    end)

    -- 2. Remove installation artifacts
    if fs.sync.dir_exists(install_path) then
        fs.sync.rmrf(install_path)
        return true
    end
    return false
end

function Package:is_installed()
    return registry.is_installed(self.name)
end

function Package:get_handle()
    return Optional.of_nilable(self.handle)
end

function Package:get_install_path()
    return path.package_prefix(self.name)
end

---@return Optional # Optional<InstallReceipt>
function Package:get_receipt()
    local receipt_path = path.concat { self:get_install_path(), "mason-receipt.json" }
    if fs.sync.file_exists(receipt_path) then
        local receipt = require "mason-core.receipt"
        return Optional.of(receipt.InstallReceipt.from_json(vim.json.decode(fs.sync.read_file(receipt_path))))
    end
    return Optional.empty()
end

---@param callback fun(success: boolean, version_or_err: string)
function Package:get_installed_version(callback)
    self:get_receipt()
        :if_present(
            ---@param receipt InstallReceipt
            function(receipt)
                if is_registry_schema_id(receipt.primary_source.type) then
                    local resolve = _.curryN(callback, 2)
                    Purl.parse(receipt.primary_source.id)
                        :map(_.prop "version")
                        :on_success(resolve(true))
                        :on_failure(resolve(false))
                else
                    a.run(function()
                        local version_checks = require "mason-core.package.version-check"
                        return version_checks.get_installed_version(receipt, self:get_install_path()):get_or_throw()
                    end, callback)
                end
            end
        )
        :if_not_present(function()
            callback(false, "Unable to get receipt.")
        end)
end

---@param callback fun(success: boolean, result_or_err: NewPackageVersion)
function Package:check_new_version(callback)
    if self:is_registry_spec() then
        self:get_installed_version(_.scheduler_wrap(function(success, installed_version)
            if not success then
                return callback(false, installed_version)
            end
            local resolve = _.curryN(callback, 2)
            Result.try(function(try)
                -- This is a bit goofy, but it's done to verify that a new version is supported by the
                -- current platform (parse fails if it's not). We don't want to surface new versions that
                -- are unsupported.
                try(require("mason-core.installer.registry").parse(self.spec, {}))

                ---@type Purl
                local purl = try(Purl.parse(self.spec.source.id))
                if purl.version and installed_version ~= purl.version then
                    return {
                        name = purl.name,
                        current_version = installed_version,
                        latest_version = purl.version,
                    }
                else
                    return Result.failure "Package is not outdated."
                end
            end)
                :on_success(resolve(true))
                :on_failure(resolve(false))
        end))
    else
        a.run(function()
            local receipt = self:get_receipt():or_else_throw "Unable to get receipt."
            local version_checks = require "mason-core.package.version-check"
            return version_checks.get_new_version(receipt, self:get_install_path()):get_or_throw()
        end, callback)
    end
end

function Package:get_lsp_settings_schema()
    local schema_file = path.share_prefix(path.concat { "mason-schemas", "lsp", ("%s.json"):format(self.name) })
    if fs.sync.file_exists(schema_file) then
        return Result.pcall(vim.json.decode, fs.sync.read_file(schema_file), {
            luanil = { object = true, array = true },
        }):ok()
    end
    return Optional.empty()
end

---@return boolean
function Package:is_registry_spec()
    return is_registry_spec(self.spec)
end

function PackageMt.__tostring(self)
    return ("Package(name=%s)"):format(self.name)
end

function Package:get_aliases()
    return require("mason-registry").get_package_aliases(self.name)
end

return Package
