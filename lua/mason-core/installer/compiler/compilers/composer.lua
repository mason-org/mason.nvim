local Result = require "mason-core.result"
local providers = require "mason-core.providers"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@param source RegistryPackageSource
---@param purl Purl
function M.parse(source, purl)
    ---@class ParsedComposerSource : ParsedPackageSource
    local parsed_source = {
        package = ("%s/%s"):format(purl.namespace, purl.name),
        version = purl.version,
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedComposerSource
function M.install(ctx, source)
    local composer = require "mason-core.installer.managers.composer"
    return composer.install(source.package, source.version)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.packagist.get_all_versions(("%s/%s"):format(purl.namespace, purl.name))
end

return M
