local _ = require "mason-core.functional"
local platform = require "mason-core.platform"

local M = {}

-- TODO: These are apparently deprecated. Find some alternative.
local write_stdout = vim.api.nvim_out_write
local writeln_stdout = function(msg)
    vim.api.nvim_echo({ { msg } }, true, {})
end
local write_stderr = vim.api.nvim_err_write
local writeln_stderr = vim.api.nvim_err_writeln

function M.run()
    if not platform.is_headless then
        local answer = vim.fn.confirm("Are you sure you want to restore packages?", "&Yes\n&No", 2)
        if answer ~= 1 then
            return
        end
        require("mason-core.lock.ui").restore()
        require("mason-core.lock.ui").open()
    else
        local a = require "mason-core.async"
        a.run_blocking(function()
            ---@type LockfileInstallHandlers
            local handlers = {
                on_completion = vim.schedule_wrap(function(pkg, success, result)
                    if success then
                        writeln_stdout(("%s was successfully restored"):format(pkg.name))
                    else
                        writeln_stderr(("%s failed to restore: %s"):format(pkg.name, result))
                    end
                end),
                on_install = vim.schedule_wrap(function(pkg, metadata)
                    writeln_stdout(("Restoring %s@%s"):format(pkg.name, metadata.version))
                end),
            }

            local ok, result = a.wait(_.partial(require("mason-core.lock").restore, handlers))
            a.scheduler()
            writeln_stdout ""
            if ok then
                writeln_stdout "Lockfile was successfully restored."
            else
                writeln_stderr "Lockfile: One or more packages failed to restore."
                if #result.unavailable_packages > 0 then
                    writeln_stderr "The following packages were unavailable:"
                    for _, pkg_name in ipairs(result.unavailable_packages) do
                        writeln_stderr(" - " .. pkg_name)
                    end
                    writeln_stderr ""
                end
                if #result.failed > 0 then
                    writeln_stderr "The following packages failed to install:"
                    for _, pkg in ipairs(result.failed) do
                        writeln_stderr(" - " .. pkg.name)
                    end
                end
                vim.cmd [[1cq]]
            end
        end)
    end
end

return M
