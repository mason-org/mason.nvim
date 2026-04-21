local Result = require "mason-core.result"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"

local M = {}

---@async
---@param pkg string
---@param version string
---@param opts? { extra_packages?: string[] }
---@nodiscard
function M.install(pkg, version, opts)
    opts = opts or {}
    log.fmt_debug("gem: install %s %s %s", pkg, version, opts)
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing gem %s@%s…\n"):format(pkg, version))
    return ctx.spawn.gem {
        "install",
        "--no-user-install",
        "--no-format-executable",
        "--install-dir=.",
        "--bindir=bin",
        "--no-document",
        ("%s:%s"):format(pkg, version),
        opts.extra_packages or vim.NIL,
        env = {
            GEM_HOME = ctx.cwd:get(),
        },
    }
end

---@async
---@param bin string
---@nodiscard
function M.create_bin_wrapper(bin)
    local ctx = installer.context()

    local bin_path = platform.when {
        unix = function()
            return path.concat { "bin", bin }
        end,
        win = function()
            return path.concat { "bin", ("%s.bat"):format(bin) }
        end,
    }

    if not ctx.fs:file_exists(bin_path) then
        return Result.failure(("Cannot link Gem executable %q because it doesn't exist."):format(bin))
    end

    return Result.pcall(ctx.write_shell_exec_wrapper, ctx, bin, path.concat { ctx:get_install_path(), bin_path }, {
        GEM_PATH = platform.when {
            unix = function()
                return ("%s:$GEM_PATH"):format(ctx:get_install_path())
            end,
            win = function()
                return ("%s;%%GEM_PATH%%"):format(ctx:get_install_path())
            end,
        },
    })
end

return M
