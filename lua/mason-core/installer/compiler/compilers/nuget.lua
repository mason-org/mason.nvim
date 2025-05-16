local Result = require "mason-core.result"
local common = require "mason-core.installer.managers.common"
local util = require "mason-core.installer.compiler.util"
local expr = require "mason-core.installer.compiler.expr"
local nuget = require "mason-core.installer.managers.nuget"
local _ = require "mason-core.functional"

local M = {}

---@class NugetPackageSource : RegistryPackageSource
---@field download FileDownloadSpec

---@param source NugetPackageSource
---@param purl Purl
function M.parse(source, purl)
    return Result.try(function (try)
        local repository_url = _.path({ "qualifiers", "repository_url" }, purl)

        local download_item = nil
        if source.download then

            if not repository_url then
                -- if not set we need to provide repository url because we need it for
                -- download url discovery
                repository_url = "https://api.nuget.org/v3/index.json"
            end

            local index_file = try(nuget.fetch_nuget_endpoint(repository_url))

            local resource = vim.iter(index_file.resources)
                :find(function (v)
                    return v['@type'] == 'PackageBaseAddress/3.0.0'
                end)

            assert(resource, "could not get PackageBaseAddress resource from nuget index file")

            local package_base_address = resource["@id"]
            local package_lowercase = purl.name:lower()

            local nupkg_download_url = string.format("%s%s/%s/%s.%s.nupkg",
                package_base_address,
                package_lowercase,
                purl.version,
                package_lowercase,
                purl.version)

            local expr_ctx = { version = purl.version }

            ---@type FileDownloadSpec
            local download_spec = try(util.coalesce_by_target(try(expr.tbl_interpolate(source.download, expr_ctx)), {}))

            download_item = {
                download_url = nupkg_download_url,
                out_file = download_spec.file
            }
        end

        ---@class ParsedNugetSource : ParsedPackageSource
        ---@field download? DownloadItem
        ---@field repository_url string Custom repository URL to pull from
        local parsed_source = {
            package = purl.name,
            version = purl.version,
            download = download_item,
            repository_url = repository_url
        }

        return parsed_source
    end)
end

---@async
---@param ctx InstallContext
---@param source ParsedNugetSource
function M.install(ctx, source)
    if source.download then
        return common.download_files(ctx, {source.download})
    else
        return nuget.install(source.package, source.version, source.repository_url)
    end
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return Result.failure "Unimplemented."
end

return M
