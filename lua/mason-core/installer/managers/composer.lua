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
    log.fmt_debug("composer: install %s %s", package, version)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing composer package %s@%s…\n"):format(package, version))
    return Result.try(function(try)
        try(ctx.spawn.composer {
            "init",
            "--no-interaction",
            "--stability=stable",
        })
        try(ctx.spawn.composer {
            "require",
            ("%s:%s"):format(package, version),
        })
    end)
end

---@param executable string
function M.bin_path(executable)
    return Result.pcall(platform.when, {
        unix = function()
            return path.concat { "vendor", "bin", executable }
        end,
        win = function()
            return path.concat { "vendor", "bin", ("%s.bat"):format(executable) }
        end,
    })
end

return M
