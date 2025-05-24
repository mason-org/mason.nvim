local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local providers = require "mason-core.providers"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@param purl Purl
local function get_package_name(purl)
    if purl.subpath then
        return ("%s/%s/%s"):format(purl.namespace, purl.name, purl.subpath)
    else
        return ("%s/%s"):format(purl.namespace, purl.name)
    end
end

---@class GolangSource : RegistryPackageSource
---@field extra_packages? string[]

---@param source GolangSource
---@param purl Purl
function M.parse(source, purl)
    ---@class ParsedGolangSource : ParsedPackageSource
    local parsed_source = {
        package = get_package_name(purl),
        version = purl.version,
        extra_packages = source.extra_packages,
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedGolangSource
function M.install(ctx, source)
    local golang = require "mason-core.installer.managers.golang"

    return golang.install(source.package, source.version, {
        extra_packages = source.extra_packages,
    })
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.golang.get_all_versions(("%s/%s"):format(purl.namespace, purl.name))
end

return M
