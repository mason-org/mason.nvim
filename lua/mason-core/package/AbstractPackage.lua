local EventEmitter = require "mason-core.EventEmitter"
local InstallLocation = require "mason-core.installer.InstallLocation"
local Optional = require "mason-core.optional"
local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local settings = require "mason.settings"
local Semaphore = require("mason-core.async.control").Semaphore

---@alias PackageInstallOpts { version?: string, debug?: boolean, target?: string, force?: boolean, strict?: boolean, location?: InstallLocation }
---@alias PackageUninstallOpts { bypass_permit?: boolean, location?: InstallLocation }

---@class AbstractPackage : EventEmitter
---@field name string
---@field spec RegistryPackageSpec
---@field registry RegistrySource
---@field private install_handle InstallHandle? The currently associated installation handle.
---@field private uninstall_handle InstallHandle? The currently associated uninstallation handle.
local AbstractPackage = {}
AbstractPackage.__index = AbstractPackage
setmetatable(AbstractPackage, { __index = EventEmitter })

AbstractPackage.SEMAPHORE = Semaphore:new(settings.current.max_concurrent_installers)
---@type PackageInstallOpts
AbstractPackage.DEFAULT_INSTALL_OPTS = {
    debug = false,
    force = false,
    strict = false,
    target = nil,
    version = nil,
}

---@param spec RegistryPackageSpec
---@param reg RegistrySource
function AbstractPackage:new(spec, reg)
    local instance = EventEmitter.new(self)
    instance.name = spec.name -- for convenient access
    instance.spec = spec
    instance.registry = reg
    return instance
end

---@param spec RegistryPackageSpec
---@param reg RegistrySource
function AbstractPackage:update(spec, reg)
    self.name = spec.name -- shouldn't be necessary but might as well
    self.spec = spec
    self.registry = reg
    return self
end

---@return boolean
function AbstractPackage:is_installing()
    return self:get_install_handle()
        :map(
            ---@param handle InstallHandle
            function(handle)
                return not handle:is_closed()
            end
        )
        :or_else(false)
end

---@return boolean
function AbstractPackage:is_uninstalling()
    return self:get_uninstall_handle()
        :map(
            ---@param handle InstallHandle
            function(handle)
                return not handle:is_closed()
            end
        )
        :or_else(false)
end

function AbstractPackage:get_install_handle()
    return Optional.of_nilable(self.install_handle)
end

function AbstractPackage:get_uninstall_handle()
    return Optional.of_nilable(self.uninstall_handle)
end

---@param location InstallLocation
function AbstractPackage:new_handle(location)
    assert(location, "Cannot create new handle without a location.")
    local InstallHandle = require "mason-core.installer.InstallHandle"
    local handle = InstallHandle:new(self, location)
    -- Ideally we'd decouple this and leverage Mason's event system, but to allow loading as little as possible during
    -- setup (i.e. not load modules related to Mason's event system) of the mason.nvim plugin we explicitly call into
    -- terminator here.
    require("mason-core.terminator").register(handle)
    return handle
end

---@param location? InstallLocation
function AbstractPackage:new_install_handle(location)
    location = location or InstallLocation.global()
    log.fmt_trace("Creating new installation handle for %s", self)
    self:get_install_handle():if_present(function(handle)
        assert(handle:is_closed(), "Cannot create new install handle because existing handle is not closed.")
    end)
    self.install_handle = self:new_handle(location)
    self:emit("install:handle", self.install_handle)
    return self.install_handle
end

---@param location? InstallLocation
function AbstractPackage:new_uninstall_handle(location)
    location = location or InstallLocation.global()
    log.fmt_trace("Creating new uninstallation handle for %s", self)
    self:get_uninstall_handle():if_present(function(handle)
        assert(handle:is_closed(), "Cannot create new uninstall handle because existing handle is not closed.")
    end)
    self.uninstall_handle = self:new_handle(location)
    self:emit("uninstall:handle", self.uninstall_handle)
    return self.uninstall_handle
end

---@param opts? PackageInstallOpts
function AbstractPackage:is_installable(opts)
    return require("mason-core.installer.compiler").parse(self.spec, opts or {}):is_success()
end

---@param location? InstallLocation
---@return Optional # Optional<InstallReceipt>
function AbstractPackage:get_receipt(location)
    location = location or InstallLocation.global()
    local receipt_path = location:receipt(self.name)
    if fs.sync.file_exists(receipt_path) then
        local receipt = require "mason-core.receipt"
        return Optional.of(receipt.InstallReceipt.from_json(vim.json.decode(fs.sync.read_file(receipt_path))))
    end
    return Optional.empty()
end

---@param location? InstallLocation
---@return boolean
function AbstractPackage:is_installed(location)
    error "Unimplemented."
end

---@return Result # Result<string[]>
function AbstractPackage:get_all_versions()
    local compiler = require "mason-core.installer.compiler"
    return Result.try(function(try)
        ---@type Purl
        local purl = try(Purl.parse(self.spec.source.id))
        ---@type InstallerCompiler
        local compiler = try(compiler.get_compiler(purl))
        return compiler.get_versions(purl, self.spec.source)
    end)
end

---@return string
function AbstractPackage:get_latest_version()
    return Purl.parse(self.spec.source.id)
        :map(_.prop "version")
        :get_or_throw(("Unable to retrieve version from malformed purl: %s."):format(self.spec.source.id))
end

---@param location? InstallLocation
---@return string?
function AbstractPackage:get_installed_version(location)
    return self:get_receipt(location)
        :and_then(
            ---@param receipt InstallReceipt
            function(receipt)
                local source = receipt:get_source()
                if source.id then
                    return Purl.parse(source.id):map(_.prop "version"):ok()
                else
                    return Optional.empty()
                end
            end
        )
        :or_else(nil)
end

---@param opts? PackageInstallOpts
---@param callback? InstallRunnerCallback
---@return InstallHandle
function AbstractPackage:install(opts, callback)
    error "Unimplemented."
end

---@param opts? PackageUninstallOpts
---@param callback? InstallRunnerCallback
---@return InstallHandle
function AbstractPackage:uninstall(opts, callback)
    error "Unimplemented."
end

---@private
---@param location? InstallLocation
function AbstractPackage:unlink(location)
    location = location or InstallLocation.global()
    log.fmt_trace("Unlinking", self, location)
    local linker = require "mason-core.installer.linker"
    return self:get_receipt(location):ok_or("Unable to find receipt."):and_then(function(receipt)
        return linker.unlink(self, receipt, location)
    end)
end

---@async
---@private
---@return Permit
function AbstractPackage:acquire_permit()
    error "Unimplemented."
end

return AbstractPackage
