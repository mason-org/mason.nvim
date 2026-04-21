local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"

local M = {}

---@async
---@param pkg string
---@param version string
---@param opts { server?: string, dev?: boolean }
function M.install(pkg, version, opts)
    opts = opts or {}
    log.fmt_debug("luarocks: install %s %s %s", pkg, version, opts)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing luarocks package %s@%s…\n"):format(pkg, version))
    ctx:promote_cwd() -- luarocks encodes absolute paths during installation
    return ctx.spawn.luarocks {
        "install",
        { "--tree", ctx.cwd:get() },
        opts.dev and "--dev" or vim.NIL,
        opts.server and ("--server=%s"):format(opts.server) or vim.NIL,
        { pkg, version },
    }
end

---@param exec string
function M.bin_path(exec)
    return Result.pcall(platform.when, {
        unix = function()
            return path.concat { "bin", exec }
        end,
        win = function()
            return path.concat { "bin", ("%s.bat"):format(exec) }
        end,
    })
end

return M
