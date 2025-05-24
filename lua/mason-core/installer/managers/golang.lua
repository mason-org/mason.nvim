local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local platform = require "mason-core.platform"

local M = {}

---@async
---@param pkg string
---@param version string
---@param opts? { extra_packages?: string[] }
function M.install(pkg, version, opts)
    return Result.try(function(try)
        opts = opts or {}
        log.fmt_debug("golang: install %s %s %s", pkg, version, opts)
        local ctx = installer.context()
        ctx.stdio_sink:stdout(("Installing go package %s@%s…\n"):format(pkg, version))
        local env = {
            GOBIN = ctx.cwd:get(),
        }
        try(ctx.spawn.go {
            "install",
            "-v",
            ("%s@%s"):format(pkg, version),
            env = env,
        })
        if opts.extra_packages then
            for _, pkg in ipairs(opts.extra_packages) do
                try(ctx.spawn.go {
                    "install",
                    "-v",
                    ("%s@latest"):format(pkg),
                    env = env,
                })
            end
        end
    end)
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
