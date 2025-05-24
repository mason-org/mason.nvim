local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local providers = require "mason-core.providers"

---@param purl Purl
local function purl_to_npm(purl)
    if purl.namespace then
        return ("%s/%s"):format(purl.namespace, purl.name)
    else
        return purl.name
    end
end

local M = {}

---@class NpmSource : RegistryPackageSource
---@field extra_packages? string[]

---@param source NpmSource
---@param purl Purl
function M.parse(source, purl)
    ---@class ParsedNpmSource : ParsedPackageSource
    local parsed_source = {
        package = purl_to_npm(purl),
        version = purl.version,
        extra_packages = source.extra_packages,
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedNpmSource
function M.install(ctx, source)
    local npm = require "mason-core.installer.managers.npm"

    return Result.try(function(try)
        try(npm.init())
        try(npm.install(source.package, source.version, {
            extra_packages = source.extra_packages,
        }))
    end)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.npm.get_all_versions(purl_to_npm(purl))
end

return M
