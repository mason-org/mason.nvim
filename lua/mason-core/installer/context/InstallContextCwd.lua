local Result = require "mason-core.result"
local fs = require "mason-core.fs"
local path = require "mason-core.path"

---@class InstallContextCwd
---@field private handle InstallHandle
---@field private cwd string?
local InstallContextCwd = {}
InstallContextCwd.__index = InstallContextCwd

---@param handle InstallHandle
function InstallContextCwd:new(handle)
    ---@type InstallContextCwd
    local instance = {}
    setmetatable(instance, self)
    instance.handle = handle
    instance.cwd = nil
    return instance
end

function InstallContextCwd:initialize()
    return Result.try(function(try)
        local staging_dir = self.handle.location:staging(self.handle.package.name)
        if fs.sync.dir_exists(staging_dir) then
            try(Result.pcall(fs.sync.rmrf, staging_dir))
        end
        try(Result.pcall(fs.sync.mkdirp, staging_dir))
        self:set(staging_dir)
    end)
end

function InstallContextCwd:get()
    assert(self.cwd ~= nil, "Tried to access cwd before it was set.")
    return self.cwd
end

---@param new_abs_cwd string
function InstallContextCwd:set(new_abs_cwd)
    assert(type(new_abs_cwd) == "string", "new_cwd is not a string")
    assert(
        path.is_subdirectory(self.handle.location:get_dir(), new_abs_cwd),
        ("%q is not a subdirectory of %q"):format(new_abs_cwd, self.handle.location)
    )
    self.cwd = new_abs_cwd
    return self
end

return InstallContextCwd
