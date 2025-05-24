local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local async_uv = require "mason-core.async.uv"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local platform = require "mason-core.platform"
local powershell = require "mason-core.installer.managers.powershell"
local std = require "mason-core.installer.managers.std"

local M = {}

---@class DownloadItem
---@field download_url string
---@field out_file string

---@class FileDownloadSpec
---@field file string | string[]

local get_source_file = _.compose(_.head, _.split ":")
local get_outfile = _.compose(_.last, _.split ":")

---Normalizes file paths from e.g. "file:out-dir/" to "out-dir/file".
---@param file string
local function normalize_file_path(file)
    local source_file = get_source_file(file)
    local new_path = get_outfile(file)

    -- a dir expression (e.g. "libexec/")
    if _.matches("/$", new_path) then
        return new_path .. source_file
    end
    return new_path
end

---@generic T : FileDownloadSpec
---@type fun(download: T): T
M.normalize_files = _.evolve {
    file = _.cond {
        { _.is "string", normalize_file_path },
        { _.T, _.map(normalize_file_path) },
    },
}

---@param download FileDownloadSpec
---@param url_generator fun(file: string): string
---@return DownloadItem[]
function M.parse_downloads(download, url_generator)
    local files = download.file
    if type(files) == "string" then
        files = { files }
    end

    return _.map(function(file)
        local source_file = get_source_file(file)
        local out_file = normalize_file_path(file)
        return {
            download_url = url_generator(source_file),
            out_file = out_file,
        }
    end, files)
end

---@async
---@param ctx InstallContext
---@param downloads DownloadItem[]
---@nodiscard
function M.download_files(ctx, downloads)
    return Result.try(function(try)
        for __, download in ipairs(downloads) do
            a.scheduler()
            local out_dir = vim.fn.fnamemodify(download.out_file, ":h")
            local out_file = vim.fn.fnamemodify(download.out_file, ":t")
            if out_dir ~= "." then
                try(Result.pcall(function()
                    ctx.fs:mkdirp(out_dir)
                end))
            end
            try(ctx:chdir(out_dir, function()
                return Result.try(function(try)
                    try(std.download_file(download.download_url, out_file))
                    try(std.unpack(out_file))
                end)
            end))
        end
    end)
end

---@class BuildInstruction
---@field target? Platform | Platform[]
---@field run string
---@field staged? boolean
---@field env? table<string, string>

---@async
---@param build BuildInstruction
---@return Result
---@nodiscard
function M.run_build_instruction(build)
    log.fmt_debug("build: run %s", build)
    local ctx = installer.context()
    if build.staged == false then
        ctx:promote_cwd()
    end
    return platform.when {
        unix = function()
            return ctx.spawn.bash {
                on_spawn = a.scope(function(_, stdio)
                    local stdin = stdio[1]
                    async_uv.write(stdin, "set -euxo pipefail;\n")
                    async_uv.write(stdin, build.run)
                    async_uv.shutdown(stdin)
                    async_uv.close(stdin)
                end),
                env = build.env,
            }
        end,
        win = function()
            return powershell.command(build.run, {
                env = build.env,
            }, ctx.spawn)
        end,
    }
end

return M
