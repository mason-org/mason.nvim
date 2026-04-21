local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local common = require "mason-core.installer.managers.common"
local expr = require "mason-core.installer.compiler.expr"
local providers = require "mason-core.providers"
local settings = require "mason.settings"
local util = require "mason-core.installer.compiler.util"

---@class GitHubReleaseSourceAsset : FileDownloadSpec
---@field target? Platform | Platform[]

---@class GitHubReleaseSource : RegistryPackageSource
---@field asset GitHubReleaseSourceAsset | GitHubReleaseSourceAsset[]

local M = {}

---@param source GitHubReleaseSource
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(source, purl, opts)
    return Result.try(function(try)
        local expr_ctx = { version = purl.version }
        ---@type GitHubReleaseSourceAsset
        local asset = try(util.coalesce_by_target(try(expr.tbl_interpolate(source.asset, expr_ctx)), opts))

        local downloads = common.parse_downloads(asset, function(file)
            return settings.current.github.download_url_template:format(
                ("%s/%s"):format(purl.namespace, purl.name),
                purl.version,
                file
            )
        end)

        ---@class ParsedGitHubReleaseSource : ParsedPackageSource
        local parsed_source = {
            repo = ("%s/%s"):format(purl.namespace, purl.name),
            asset = common.normalize_files(asset),
            downloads = downloads,
        }
        return parsed_source
    end)
end

---@async
---@param ctx InstallContext
---@param source ParsedGitHubReleaseSource
function M.install(ctx, source)
    return common.download_files(ctx, source.downloads)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return providers.github.get_all_release_versions(("%s/%s"):format(purl.namespace, purl.name))
end

return M
