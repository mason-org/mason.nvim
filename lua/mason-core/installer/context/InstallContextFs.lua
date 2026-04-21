local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"

---@class InstallContextFs
---@field private cwd InstallContextCwd
local InstallContextFs = {}
InstallContextFs.__index = InstallContextFs

---@param cwd InstallContextCwd
function InstallContextFs:new(cwd)
    ---@type InstallContextFs
    local instance = {}
    setmetatable(instance, InstallContextFs)
    instance.cwd = cwd
    return instance
end

---@async
---@param rel_path string The relative path from the current working directory to the file to append.
---@param contents string
function InstallContextFs:append_file(rel_path, contents)
    return fs.async.append_file(path.concat { self.cwd:get(), rel_path }, contents)
end

---@async
---@param rel_path string The relative path from the current working directory to the file to write.
---@param contents string
function InstallContextFs:write_file(rel_path, contents)
    return fs.async.write_file(path.concat { self.cwd:get(), rel_path }, contents)
end

---@async
---@param rel_path string The relative path from the current working directory to the file to read.
function InstallContextFs:read_file(rel_path)
    return fs.async.read_file(path.concat { self.cwd:get(), rel_path })
end

---@async
---@param rel_path string The relative path from the current working directory.
function InstallContextFs:file_exists(rel_path)
    return fs.async.file_exists(path.concat { self.cwd:get(), rel_path })
end

---@async
---@param rel_path string The relative path from the current working directory.
function InstallContextFs:dir_exists(rel_path)
    return fs.async.dir_exists(path.concat { self.cwd:get(), rel_path })
end

---@async
---@param rel_path string The relative path from the current working directory.
function InstallContextFs:rmrf(rel_path)
    return fs.async.rmrf(path.concat { self.cwd:get(), rel_path })
end

---@async
---@param rel_path string The relative path from the current working directory.
function InstallContextFs:unlink(rel_path)
    return fs.async.unlink(path.concat { self.cwd:get(), rel_path })
end

---@async
---@param old_path string
---@param new_path string
function InstallContextFs:rename(old_path, new_path)
    return fs.async.rename(path.concat { self.cwd:get(), old_path }, path.concat { self.cwd:get(), new_path })
end

---@async
---@param dir_path string
function InstallContextFs:mkdir(dir_path)
    return fs.async.mkdir(path.concat { self.cwd:get(), dir_path })
end

---@async
---@param dir_path string
function InstallContextFs:mkdirp(dir_path)
    return fs.async.mkdirp(path.concat { self.cwd:get(), dir_path })
end

---@async
---@param file_path string
function InstallContextFs:chmod_exec(file_path)
    local bit = require "bit"
    -- see chmod(2)
    local USR_EXEC = 0x40
    local GRP_EXEC = 0x8
    local ALL_EXEC = 0x1
    local EXEC = bit.bor(USR_EXEC, GRP_EXEC, ALL_EXEC)
    local fstat = self:fstat(file_path)
    if bit.band(fstat.mode, EXEC) ~= EXEC then
        local plus_exec = bit.bor(fstat.mode, EXEC)
        log.fmt_debug("Setting exec flags on file %s %o -> %o", file_path, fstat.mode, plus_exec)
        self:chmod(file_path, plus_exec) -- chmod +x
    end
end

---@async
---@param file_path string
---@param mode integer
function InstallContextFs:chmod(file_path, mode)
    return fs.async.chmod(path.concat { self.cwd:get(), file_path }, mode)
end

---@async
---@param file_path string
function InstallContextFs:fstat(file_path)
    return fs.async.fstat(path.concat { self.cwd:get(), file_path })
end

return InstallContextFs
