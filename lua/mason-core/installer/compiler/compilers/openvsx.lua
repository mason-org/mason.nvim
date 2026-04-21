local Result = require "mason-core.result"
local common = require "mason-core.installer.managers.common"
local expr = require "mason-core.installer.compiler.expr"
local providers = require "mason-core.providers"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@class OpenVSXSourceDownload : FileDownloadSpec
---@field target? Platform | Platform[]
---@field target_platform? string

---@class OpenVSXSource : RegistryPackageSource
---@field download OpenVSXSourceDownload | OpenVSXSourceDownload[]

---@param source OpenVSXSource
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(source, purl, opts)
    return Result.try(function(try)
        local expr_ctx = { version = purl.version }
        ---@type OpenVSXSourceDownload
        local download = try(util.coalesce_by_target(try(expr.tbl_interpolate(source.download, expr_ctx)), opts))

        local downloads = common.parse_downloads(download, function(file)
            if download.target_platform then
                return ("https://open-vsx.org/api/%s/%s/%s/%s/file/%s"):format(
                    purl.namespace,
                    purl.name,
                    download.target_platform,
                    purl.version,
                    file
                )
            else
                return ("https://open-vsx.org/api/%s/%s/%s/file/%s"):format(
                    purl.namespace,
                    purl.name,
                    purl.version,
                    file
                )
            end
        end)

        ---@class ParsedOpenVSXSource : ParsedPackageSource
        local parsed_source = {
            download = common.normalize_files(download),
            downloads = downloads,
        }
        return parsed_source
    end)
end

---@param ctx InstallContext
---@param source ParsedOpenVSXSource
function M.install(ctx, source)
    return common.download_files(ctx, source.downloads)
end

---@param purl Purl
function M.get_versions(purl)
    return providers.openvsx.get_all_versions(purl.namespace, purl.name)
end

return M
