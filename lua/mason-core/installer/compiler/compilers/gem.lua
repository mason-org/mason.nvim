local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local providers = require "mason-core.providers"

local M = {}

---@class GemSource : RegistryPackageSource
---@field extra_packages? string[]

---@param source GemSource
---@param purl Purl
function M.parse(source, purl)
    ---@class ParsedGemSource : ParsedPackageSource
    local parsed_source = {
        package = purl.name,
        version = purl.version,
        extra_packages = source.extra_packages,
    }
    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedGemSource
function M.install(ctx, source)
    local gem = require "mason-core.installer.managers.gem"
    return gem.install(source.package, source.version, {
        extra_packages = source.extra_packages,
    })
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.rubygems.get_all_versions(purl.name)
end

return M
