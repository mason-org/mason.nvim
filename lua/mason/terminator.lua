local registry = require "mason-registry"
local a = require "mason-core.async"

-- Hasta la vista, baby.
--                      ______
--                    <((((((\\\
--                    /      . }\
--                    ;--..--._|}
-- (\                 '--/\--'  )
--  \\                | '-'  :'|
--   \\               . -==- .-|
--    \\               \.__.'   \--._
--    [\\          __.--|       //  _/'--.
--    \ \\       .'-._ ('-----'/ __/      \
--     \ \\     /   __>|      | '--.       |
--      \ \\   |   \   |     /    /       /
--       \ '\ /     \  |     |  _/       /
--        \  \       \ |     | /        /
--  snd    \  \      \        /

local M = {}

---@async
---@param handles InstallHandle[]
local function terminate_handles(handles)
    a.wait_all(vim.tbl_map(
        ---@param handle InstallHandle
        function(handle)
            if not handle:is_closed() then
                handle:terminate()
            end
            return function()
                a.wait(function(resolve)
                    if handle:is_closed() then
                        resolve()
                    else
                        handle:once("closed", resolve)
                    end
                end)
            end
        end,
        handles
    ))
end

local active_handles = {}

function M.setup()
    registry:on("package:handle", function(_, handle)
        if handle:is_closed() then
            return
        end
        active_handles[handle] = true
        handle:once("closed", function()
            active_handles[handle] = nil
        end)
    end)
end

function M.terminate()
    local handles = vim.tbl_keys(active_handles)
    if #handles > 0 then
        local package_names = vim.tbl_map(function(h)
            return h.package.name
        end, handles)
        table.sort(package_names)

        -- 1. Print warning message.
        vim.api.nvim_echo({
            {
                "[mason.nvim] Neovim is exiting while packages are still installing. Terminating all installations…",
                "WarningMsg",
            },
        }, true, {})
        vim.cmd "redraw"

        -- 2. Synchronously terminate all installation handles.
        a.run_blocking(function()
            a.wait_first {
                function()
                    a.sleep(5000)
                end,
                function()
                    terminate_handles(handles)
                end,
            }
        end)

        -- 3. Schedule error message to be displayed so that Neovim prints it to the tty.
        --    XXX: does this need to be conditional on which UIs are attached?
        vim.schedule(function()
            vim.api.nvim_err_writeln(
                ("[mason.nvim] Neovim exited while the following packages were installing. Installation was aborted.\n- %s"):format(
                    table.concat(package_names, #package_names > 5 and ", " or "\n- ")
                )
            )
        end)
    end
end

return M
