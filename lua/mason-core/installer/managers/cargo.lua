local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"

local M = {}

---@async
---@param crate string
---@param version string
---@param opts? { features?: string, locked?: boolean, git?: { url: string, rev?: boolean } }
function M.install(crate, version, opts)
    opts = opts or {}
    log.fmt_debug("cargo: install %s %s %s", crate, version, opts)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing crate %s@%s…\n"):format(crate, version))
    return ctx.spawn.cargo {
        "install",
        "--root",
        ".",
        opts.git and {
            "--git",
            opts.git.url,
            opts.git.rev and "--rev" or "--tag",
            version,
        } or { "--version", version },
        opts.features and { "--features", opts.features } or vim.NIL,
        opts.locked and "--locked" or vim.NIL,
        crate,
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
