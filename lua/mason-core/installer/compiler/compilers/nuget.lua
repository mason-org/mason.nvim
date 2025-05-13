local Result = require "mason-core.result"
local _ = require "mason-core.functional"

local M = {}

---@param source RegistryPackageSource
---@param purl Purl
function M.parse(source, purl)

    local repository_url = _.path({ "qualifiers", "repository_url" }, purl)

    if not repository_url then
        repository_url = "https://api.nuget.org/v3/index.json"
    end

    ---@class ParsedNugetSource : ParsedPackageSource
    ---@field repository_url string Custom repository URL to pull from
    local parsed_source = {
        package = purl.name,
        version = purl.version,
        repository_url = repository_url
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedNugetSource
function M.install(ctx, source)
    local nuget = require "mason-core.installer.managers.nuget"
    return nuget.install(source.package, source.version, source.repository_url)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return Result.failure "Unimplemented."
end

return M
