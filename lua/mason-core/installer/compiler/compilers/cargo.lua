local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local providers = require "mason-core.providers"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@class CargoSource : RegistryPackageSource
---@field supported_platforms? string[]

---@param source CargoSource
---@param purl Purl
function M.parse(source, purl)
    return Result.try(function(try)
        if source.supported_platforms then
            try(util.ensure_valid_platform(source.supported_platforms))
        end

        local repository_url = _.path({ "qualifiers", "repository_url" }, purl)

        local git
        if repository_url then
            git = {
                url = repository_url,
                rev = _.path({ "qualifiers", "rev" }, purl) == "true",
            }
        end

        ---@type string?
        local features = _.path({ "qualifiers", "features" }, purl)
        local locked = _.path({ "qualifiers", "locked" }, purl)

        ---@class ParsedCargoSource : ParsedPackageSource
        local parsed_source = {
            crate = purl.name,
            version = purl.version,
            features = features,
            locked = locked ~= "false",
            git = git,
        }
        return parsed_source
    end)
end

---@async
---@param ctx InstallContext
---@param source ParsedCargoSource
function M.install(ctx, source)
    local cargo = require "mason-core.installer.managers.cargo"

    return cargo.install(source.crate, source.version, {
        git = source.git,
        features = source.features,
        locked = source.locked,
    })
end

---@async
---@param purl Purl
function M.get_versions(purl)
    ---@type string?
    local repository_url = _.path({ "qualifiers", "repository_url" }, purl)
    local rev = _.path({ "qualifiers", "rev" }, purl)
    if repository_url then
        if rev == "true" then
            -- When ?rev=true we're targeting a commit SHA. It's not feasible to retrieve all commit SHAs for a
            -- repository so we fail instead.
            return Result.failure "Unable to retrieve commit SHAs."
        end

        ---@type Result?
        local git_tags = _.cond {
            {
                _.matches "github.com/(.+)",
                _.compose(providers.github.get_all_tags, _.head, _.match "github.com/(.+)"),
            },
        }(repository_url)
        if git_tags then
            return git_tags
        end
    end
    return providers.crates.get_all_versions(purl.name)
end

return M
