local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"

local M = {}

---@async
---@param package string
---@param version string
---@nodiscard
function M.install(package, version)
    log.fmt_debug("opam: install %s %s", package, version)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing opam package %s@%s…\n"):format(package, version))
    return ctx.spawn.opam {
        "install",
        "--destdir=.",
        "--yes",
        "--verbose",
        ("%s.%s"):format(package, version),
    }
end

---@param bin string
function M.bin_path(bin)
    return Result.pcall(platform.when, {
        unix = function()
            return path.concat { "bin", bin }
        end,
        win = function()
            return path.concat { "bin", ("%s.exe"):format(bin) }
        end,
    })
end

return M
