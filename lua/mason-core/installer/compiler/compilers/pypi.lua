local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local providers = require "mason-core.providers"
local settings = require "mason.settings"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@class PypiSource : RegistryPackageSource
---@field extra_packages? string[]
---@field supported_platforms? string[]

---@param source PypiSource
---@param purl Purl
function M.parse(source, purl)
    return Result.try(function(try)
        if source.supported_platforms then
            try(util.ensure_valid_platform(source.supported_platforms))
        end

        ---@class ParsedPypiSource : ParsedPackageSource
        local parsed_source = {
            package = purl.name,
            version = purl.version --[[ @as string ]],
            extra = _.path({ "qualifiers", "extra" }, purl),
            extra_packages = source.extra_packages,
            pip = {
                upgrade = settings.current.pip.upgrade_pip,
                extra_args = settings.current.pip.install_args,
            },
        }

        return parsed_source
    end)
end

---@async
---@param ctx InstallContext
---@param source ParsedPypiSource
function M.install(ctx, source)
    local pypi = require "mason-core.installer.managers.pypi"

    return Result.try(function(try)
        try(pypi.init {
            package = {
                name = source.package,
                version = source.version,
            },
            upgrade_pip = source.pip.upgrade,
            install_extra_args = source.pip.extra_args,
        })
        try(pypi.install(source.package, source.version, {
            extra = source.extra,
            extra_packages = source.extra_packages,
            install_extra_args = source.pip.extra_args,
        }))
    end)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.pypi.get_all_versions(purl.name)
end

return M
