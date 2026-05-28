local Path = require "mason-core.path"
local _ = require "mason-core.functional"
local log = require "mason-core.log"
local settings = require "mason.settings"

local function make_module(uv)
    local M = {}

    ---@param path string
    function M.stat(path)
        log.trace("fs: stat", path)
        return assert(uv.fs_stat(path))
    end

    ---@param path string
    function M.file_exists(path)
        log.trace("fs: file_exists", path)
        local ok, stat = pcall(M.stat, path)
        if not ok then
            return false
        end
        return stat.type == "file"
    end

    ---@param path string
    function M.dir_exists(path)
        log.trace("fs: dir_exists", path)
        local ok, stat = pcall(M.stat, path)
        if not ok then
            return false
        end
        return stat.type == "directory"
    end

    ---@param path string
    ---@param fn fun(abs_path: string, entry: string, type: "directory" | "file")
    function M.ls(path, fn)
        local handle = vim.uv.fs_scandir(path)
        while handle do
            local entry, t = vim.uv.fs_scandir_next(handle)
            if not entry then
                break
            end

            ---@type string
            local abs_path
            if vim.fn.has "win32" == 1 and path:sub(1, 4) == [[\\?\]] then
                -- Extended-length paths are used, we cannot use vim.fs.joinpath.
                abs_path = path .. "\\" .. entry
            else
                abs_path = vim.fs.joinpath(path, entry)
            end
            t = t or vim.uv.fs_stat(abs_path).type

            if fn(abs_path, entry, t) == false then
                break
            end
        end
    end

    ---@param path string
    ---@param fn fun(abs_path: string, entry: string, type: "directory" | "file")
    function M.walk(path, fn)
        M.ls(path, function(abs_path, entry, type)
            if type == "directory" then
                M.walk(abs_path, fn)
            end
            fn(abs_path, entry, type)
        end)
    end

    ---@param path string
    function M.rmrf(path)
        assert(
            Path.is_subdirectory(settings.current.install_root_dir, path),
            ("Refusing to rmrf %q which is outside of the allowed boundary %q. Please report this error at https://github.com/mason-org/mason.nvim/issues/new"):format(
                path,
                settings.current.install_root_dir
            )
        )
        log.debug("fs: rmrf", path)
        if vim.fn.has "win32" == 1 then
            -- Use extended-length path (ELP) on Windows. We have no easy way to check if the current system has
            -- LongPathsEnabled, so we enforce extended-length paths always.
            --
            -- This is currently only done in this function (rmrf) because we walk the entire file tree under `path`,
            -- which may result in deeply nested file paths that exceed MAX_PATH (260 characters). Other fs operations
            -- don't reach so deeply into the file tree and pose minimal risk of exceeding the MAX_PATH.
            -- NOTE: When using the ELP prefix Windows doesn't normalize file paths, meaning path separators (\) need to
            -- be correct.
            --
            -- See https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation
            local extended_length_prefix = [[\\?\]]
            path = extended_length_prefix .. path:gsub("/", "\\")
        end
        M.walk(path, function(abs_path, _, type)
            if type == "directory" then
                log.trace("fs: rmdir", abs_path)
                vim.uv.fs_rmdir(abs_path)
            else
                log.trace("fs: unlink", abs_path)
                vim.uv.fs_unlink(abs_path)
            end
        end)
        M.rmdir(path)
    end

    ---@param path string
    function M.unlink(path)
        log.debug("fs: unlink", path)
        uv.fs_unlink(path)
    end

    ---@param path string
    function M.mkdir(path)
        log.debug("fs: mkdir", path)
        uv.fs_mkdir(path, 493) -- 493(10) == 755(8)
    end

    ---@param path string
    function M.mkdirp(path)
        log.debug("fs: mkdirp", path)
        local normalized_path = vim.fs.normalize(path)
        local path_components = vim.split(normalized_path, "/", { plain = true })
        if vim.fn.has "win32" ~= 1 then
            path_components[1] = "/"
        end
        for i = 1, #path_components, 1 do
            local current_path = vim.fs.joinpath(unpack(_.take(i, path_components)))
            if not M.dir_exists(current_path) then
                M.mkdir(current_path)
            end
        end
    end

    ---@param path string
    function M.rmdir(path)
        log.debug("fs: rmdir", path)
        uv.fs_rmdir(path)
    end

    ---@param path string
    ---@param new_path string
    function M.rename(path, new_path)
        log.debug("fs: rename", path, new_path)
        uv.fs_rename(path, new_path)
    end

    ---@param path string
    ---@param new_path string
    ---@param flags table? { excl?: boolean, ficlone?: boolean, ficlone_force?: boolean }
    function M.copy_file(path, new_path, flags)
        log.debug("fs: copy_file", path, new_path, flags)
        uv.fs_copyfile(path, new_path, flags)
    end

    ---@param path string
    ---@param contents string
    ---@param flags string? Defaults to "w".
    function M.write_file(path, contents, flags)
        log.trace("fs: write_file", path)
        local fd = uv.fs_open(path, flags or "w", 438)
        uv.fs_write(fd, contents, -1)
        uv.fs_close(fd)
    end

    ---@param path string
    ---@param contents string
    function M.append_file(path, contents)
        M.write_file(path, contents, "a")
    end

    ---@param path string
    function M.read_file(path)
        log.trace("fs: read_file", path)
        local fd = uv.fs_open(path, "r", 438)
        local fstat = uv.fs_fstat(fd)
        local contents = uv.fs_read(fd, fstat.size, 0)
        uv.fs_close(fd)
        return contents
    end

    ---@alias ReaddirEntry {name: string, type: string}

    ---@param path string: The full path to the directory to read.
    ---@return ReaddirEntry[]
    function M.readdir(path)
        local all_entries = {}
        M.ls(path, function(_, entry, type)
            all_entries[#all_entries + 1] = {
                name = entry,
                type = type,
            }
        end)
        return all_entries
    end

    ---@param path string
    ---@param new_path string
    function M.symlink(path, new_path)
        log.trace("fs: symlink", path, new_path)
        uv.fs_symlink(path, new_path)
    end

    ---@param path string
    ---@param mode integer
    function M.chmod(path, mode)
        log.trace("fs: chmod", path, mode)
        uv.fs_chmod(path, mode)
    end

    return M
end

return {
    async = make_module(require "mason-core.async.uv"),
    sync = make_module(vim.loop),
}
