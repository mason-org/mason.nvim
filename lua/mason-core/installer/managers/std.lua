local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local fetch = require "mason-core.fetch"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"
local powershell = require "mason-core.installer.managers.powershell"

local M = {}

---@async
---@param rel_path string
---@nodiscard
local function unpack_7z(rel_path)
    log.fmt_debug("std: unpack_7z %s", rel_path)
    local ctx = installer.context()
    return ctx.spawn["7z"] { "x", "-y", "-r", rel_path }
end

---@async
---@param rel_path string
---@nodiscard
local function unpack_peazip(rel_path)
    log.fmt_debug("std: unpack_peazip %s", rel_path)
    local ctx = installer.context()
    return ctx.spawn.peazip { "-ext2here", path.concat { ctx.cwd:get(), rel_path } } -- peazip requires absolute paths
end

---@async
---@param rel_path string
---@nodiscard
local function wzunzip(rel_path)
    log.fmt_debug("std: wzunzip %s", rel_path)
    local ctx = installer.context()
    return ctx.spawn.wzunzip { rel_path }
end

---@async
---@param rel_path string
---@nodiscard
local function unpack_winrar(rel_path)
    log.fmt_debug("std: unpack_winrar %s", rel_path)
    local ctx = installer.context()
    return ctx.spawn.winrar { "e", rel_path }
end

---@async
---@param rel_path string
---@nodiscard
local function gunzip_unix(rel_path)
    log.fmt_debug("std: gunzip_unix %s", rel_path)
    local ctx = installer.context()
    return ctx.spawn.gzip { "-d", rel_path }
end

---@async
---@param rel_path string
---@nodiscard
local function unpack_arc(rel_path)
    log.fmt_debug("std: unpack_arc %s", rel_path)
    local ctx = installer.context()
    return ctx.spawn.arc { "unarchive", rel_path }
end

---@param rel_path string
---@return Result
local function win_decompress(rel_path)
    local ctx = installer.context()
    return gunzip_unix(rel_path)
        :or_else(function()
            return unpack_7z(rel_path)
        end)
        :or_else(function()
            return unpack_peazip(rel_path)
        end)
        :or_else(function()
            return wzunzip(rel_path)
        end)
        :or_else(function()
            return unpack_winrar(rel_path)
        end)
        :on_success(function()
            pcall(function()
                ctx.fs:unlink(rel_path)
            end)
        end)
end

---@async
---@param url string
---@param out_file string
---@nodiscard
function M.download_file(url, out_file)
    log.fmt_debug("std: downloading file %s", url, out_file)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Downloading file %q…\n"):format(url))
    return fetch(url, {
        out_file = path.concat { ctx.cwd:get(), out_file },
    }):map_err(function(err)
        return ("%s\nFailed to download file %q."):format(err, url)
    end)
end

---@async
---@param rel_path string
---@nodiscard
local function untar(rel_path)
    log.fmt_debug("std: untar %s", rel_path)
    local ctx = installer.context()
    a.scheduler()
    local tar = vim.fn.executable "gtar" == 1 and "gtar" or "tar"
    return ctx.spawn[tar]({ "--no-same-owner", "-xvf", rel_path }):on_success(function()
        pcall(function()
            ctx.fs:unlink(rel_path)
        end)
    end)
end

---@async
---@param rel_path string
---@nodiscard
local function unzip(rel_path)
    log.fmt_debug("std: unzip %s", rel_path)
    local ctx = installer.context()
    return platform.when {
        unix = function()
            return ctx.spawn.unzip({ "-d", ".", rel_path }):on_success(function()
                pcall(function()
                    ctx.fs:unlink(rel_path)
                end)
            end)
        end,
        win = function()
            return Result.pcall(function()
                -- Expand-Archive seems to be hard-coded to only allow .zip extensions. Bit weird but ok.
                if not _.matches("%.zip$", rel_path) then
                    local zip_file = ("%s.zip"):format(rel_path)
                    ctx.fs:rename(rel_path, zip_file)
                    return zip_file
                end
                return rel_path
            end):and_then(function(zip_file)
                return powershell
                    .command(
                        ("Microsoft.PowerShell.Archive\\Expand-Archive -Path %q -DestinationPath ."):format(zip_file),
                        {},
                        ctx.spawn
                    )
                    :on_success(function()
                        pcall(function()
                            ctx.fs:unlink(zip_file)
                        end)
                    end)
            end)
        end,
    }
end

---@async
---@param rel_path string
---@nodiscard
local function gunzip(rel_path)
    log.fmt_debug("std: gunzip %s", rel_path)
    return platform.when {
        unix = function()
            return gunzip_unix(rel_path)
        end,
        win = function()
            return win_decompress(rel_path)
        end,
    }
end

---@async
---@param rel_path string
---@return Result
---@nodiscard
local function untar_compressed(rel_path)
    log.fmt_debug("std: untar_compressed %s", rel_path)
    return platform.when {
        unix = function()
            return untar(rel_path)
        end,
        win = function()
            return win_decompress(rel_path)
                :and_then(function()
                    return untar(_.gsub("%.tar%..*$", ".tar", rel_path))
                end)
                :or_else(function()
                    -- arc both decompresses and unpacks tar in one go
                    return unpack_arc(rel_path)
                end)
        end,
    }
end

---@async
---@param rel_path string
---@return Result
---@nodiscard
local function untar_zst(rel_path)
    return platform.when {
        unix = function()
            return untar(rel_path)
        end,
        win = function()
            local ctx = installer.context()
            local uncompressed_tar = rel_path:gsub("%.zst$", "")
            ctx.spawn.zstd { "-dfo", uncompressed_tar, rel_path }
            ctx.fs:unlink(rel_path)
            return untar(uncompressed_tar)
        end,
    }
end

-- Order is important.
local unpack_by_filename = _.cond {
    { _.matches "%.tar$", untar },
    { _.matches "%.tar%.gz$", untar },
    { _.matches "%.tar%.bz2$", untar },
    { _.matches "%.tar%.xz$", untar_compressed },
    { _.matches "%.tar%.zst$", untar_zst },
    { _.matches "%.zip$", unzip },
    { _.matches "%.vsix$", unzip },
    { _.matches "%.gz$", gunzip },
    { _.T, _.compose(Result.success, _.format "%q doesn't need unpacking.") },
}

---@async
---@param rel_path string The relative path to the file to unpack.
---@nodiscard
function M.unpack(rel_path)
    log.fmt_debug("std: unpack %s", rel_path)
    local ctx = installer.context()
    ctx.stdio_sink:stdout((("Unpacking %q…\n"):format(rel_path)))
    return unpack_by_filename(rel_path)
end

---@async
---@param git_url string
---@param opts? { rev?: string, recursive?: boolean }
---@nodiscard
function M.clone(git_url, opts)
    opts = opts or {}
    log.fmt_debug("std: clone %s %s", git_url, opts)
    local ctx = installer.context()
    ctx.stdio_sink:stdout((("Cloning git repository %q…\n"):format(git_url)))
    return Result.try(function(try)
        try(ctx.spawn.git {
            "clone",
            "--depth",
            "1",
            opts.recursive and "--recursive" or vim.NIL,
            git_url,
            ".",
        })
        if opts.rev then
            try(ctx.spawn.git { "fetch", "--depth", "1", "origin", opts.rev })
            try(ctx.spawn.git { "checkout", "--quiet", "FETCH_HEAD" })
        end
    end)
end

return M
