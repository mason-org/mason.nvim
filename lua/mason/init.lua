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

    local Command = require "mason.api.command"
    setup_autocmds()

    local Package = require "mason-core.package"
    local pkgs_to_install = {}
    for _, pkg_identifier in ipairs(settings.current.ensure_installed or {}) do
        local pkg_name, _ = Package.Parse(pkg_identifier)
        local ok, pkg = pcall(Registry.get_package, pkg_name)
        if ok and not pkg:is_installed() and not pkg:is_installing() then
            table.insert(pkgs_to_install, pkg_identifier)
        end
    end
    if not vim.tbl_isempty(pkgs_to_install) then
        Command.MasonInstall(pkgs_to_install)
    end

    M.has_setup = true
end

return M
