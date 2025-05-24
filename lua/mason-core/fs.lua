local Path = require "mason-core.path"
local a = require "mason-core.async"
local log = require "mason-core.log"
local settings = require "mason.settings"

local function make_module(uv)
    local M = {}

    ---@param path string
    function M.fstat(path)
        log.trace("fs: fstat", path)
        local fd = uv.fs_open(path, "r", 438)
        local fstat = uv.fs_fstat(fd)
        uv.fs_close(fd)
        return fstat
    end

    ---@param path string
    function M.file_exists(path)
        log.trace("fs: file_exists", path)
        local ok, fstat = pcall(M.fstat, path)
        if not ok then
            return false
        end
        return fstat.type == "file"
    end

    ---@param path string
    function M.dir_exists(path)
        log.trace("fs: dir_exists", path)
        local ok, fstat = pcall(M.fstat, path)
        if not ok then
            return false
        end
        return fstat.type == "directory"
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
        if vim.in_fast_event() then
            a.scheduler()
        end
        if vim.fn.delete(path, "rf") ~= 0 then
            log.debug "fs: rmrf failed"
            error(("rmrf: Could not remove directory %q."):format(path))
        end
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
        if vim.in_fast_event() then
            a.scheduler()
        end
        if vim.fn.mkdir(path, "p") ~= 1 then
            log.debug "fs: mkdirp failed"
            error(("mkdirp: Could not create directory %q."):format(path))
        end
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
        log.trace("fs: fs_opendir", path)
        local dir = assert(vim.loop.fs_opendir(path, nil, 25))
        local all_entries = {}
        local exhausted = false

        repeat
            local entries = uv.fs_readdir(dir)
            log.trace("fs: fs_readdir", path, entries)
            if entries and #entries > 0 then
                for i = 1, #entries do
                    if entries[i].name and not entries[i].type then
                        -- See https://github.com/luvit/luv/issues/660
                        local full_path = Path.concat { path, entries[i].name }
                        log.trace("fs: fs_readdir falling back to fs_stat to find type", full_path)
                        local stat = uv.fs_stat(full_path)
                        entries[i].type = stat.type
                    end
                    all_entries[#all_entries + 1] = entries[i]
                end
            else
                log.trace("fs: fs_readdir exhausted scan", path)
                exhausted = true
            end
        until exhausted

        uv.fs_closedir(dir)

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
