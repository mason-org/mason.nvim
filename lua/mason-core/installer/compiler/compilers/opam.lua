local Result = require "mason-core.result"

local M = {}

---@param source RegistryPackageSource
---@param purl Purl
function M.parse(source, purl)
    ---@class ParsedOpamSource : ParsedPackageSource
    local parsed_source = {
        package = purl.name,
        version = purl.version,
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedOpamSource
function M.install(ctx, source)
    local opam = require "mason-core.installer.managers.opam"
    return opam.install(source.package, source.version)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return Result.failure "Unimplemented."
end

return M
