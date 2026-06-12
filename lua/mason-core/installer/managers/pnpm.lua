local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"

local M = {}

---@async
function M.init()
    log.debug "pnpm: init"
    local ctx = installer.context()
    return Result.try(function(try)
        try(ctx.spawn.pnpm { "init" })
        local package_json = try(Result.pcall(vim.json.decode, ctx.fs:read_file "package.json"))
        package_json.name = "@mason/" .. package_json.name
        ctx.fs:write_file("package.json", try(Result.pcall(vim.json.encode, package_json)))
        ctx.stdio_sink:stdout "Initialized pnpm root.\n"
    end)
end

---@async
---@param pkg string
---@param version string
---@param opts? { extra_packages?: string[] }
function M.install(pkg, version, opts)
    opts = opts or {}
    log.fmt_debug("pnpm: add %s %s %s", pkg, version, opts)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing npm package %s@%s…\n"):format(pkg, version))
    return ctx.spawn.pnpm {
        "add",
        ("%s@%s"):format(pkg, version),
        opts.extra_packages or vim.NIL,
    }
end

---@param exec string
function M.bin_path(exec)
    return Result.pcall(platform.when, {
        unix = function()
            return path.concat { "node_modules", ".bin", exec }
        end,
        win = function()
            return path.concat { "node_modules", ".bin", ("%s.cmd"):format(exec) }
        end,
    })
end

return M
