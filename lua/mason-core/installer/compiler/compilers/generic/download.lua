local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local common = require "mason-core.installer.managers.common"
local expr = require "mason-core.installer.compiler.expr"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@class GenericDownload
---@field target (Platform | Platform[])?
---@field files table<string, string>

---@class GenericDownloadSource : RegistryPackageSource
---@field download GenericDownload | GenericDownload[]

---@param source GenericDownloadSource
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(source, purl, opts)
    return Result.try(function(try)
        local download = try(util.coalesce_by_target(source.download, opts))

        local expr_ctx = { version = purl.version }
        ---@type { files: table<string, string> }
        local interpolated_download = try(expr.tbl_interpolate(download, expr_ctx))

        ---@type DownloadItem[]
        local downloads = _.map(function(pair)
            ---@type DownloadItem
            return {
                out_file = pair[1],
                download_url = pair[2],
            }
        end, _.to_pairs(interpolated_download.files))

        ---@class ParsedGenericDownloadSource : ParsedPackageSource
        local parsed_source = {
            download = interpolated_download,
            downloads = downloads,
        }
        return parsed_source
    end)
end

---@async
---@param ctx InstallContext
---@param source ParsedGenericDownloadSource
function M.install(ctx, source)
    return common.download_files(ctx, source.downloads)
end

return M
