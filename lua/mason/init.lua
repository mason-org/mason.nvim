local InstallLocation = require "mason-core.installer.InstallLocation"
local Registry = require "mason-registry"
local settings = require "mason.settings"

local M = {}

local function setup_autocmds()
    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            require("mason-core.terminator").terminate(5000)
        end,
        once = true,
    })
end

M.has_setup = false

---@param config MasonSettings?
function M.setup(config)
    if config then
        settings.set(config)
    end

    local global_location = InstallLocation.global()
    global_location:set_env { PATH = settings.current.PATH }
    for _, registry in ipairs(settings.current.registries) do
        Registry.sources:append(registry)
    end

    local commands = require "mason.api.command"
    setup_autocmds()

    local pkg_names_to_install = {}
    for _, pkg_name in ipairs(settings.current.ensure_installed or {}) do
        if not Registry.is_installed(pkg_name) then
            table.insert(pkg_names_to_install, pkg_name)
        end
    end
    if not vim.tbl_isempty(pkg_names_to_install) then
        commands.MasonInstall(pkg_names_to_install)
    end

    M.has_setup = true
end

return M
