local Result = require "mason-core.result"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local platform = require "mason-core.platform"

local M = {}

---@async
---@param package string
---@param version string
---@nodiscard
function M.install(package, version)
    log.fmt_debug("nuget: install %s %s", package, version)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing nuget package %s@%s…\n"):format(package, version))
    return ctx.spawn.dotnet {
        "tool",
        "update",
        "--tool-path",
        ".",
        { "--version", version },
        package,
    }
end

---@param bin string
function M.bin_path(bin)
    return Result.pcall(platform.when, {
        unix = function()
            return bin
        end,
        win = function()
            return ("%s.exe"):format(bin)
        end,
    })
end

return M
