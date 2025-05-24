local Ui = require "mason-core.ui"
local _ = require "mason-core.functional"
local log = require "mason-core.log"
local p = require "mason.ui.palette"
local settings = require "mason.settings"

local DAPHelp = require "mason.ui.components.help.dap"
local FormatterHelp = require "mason.ui.components.help.formatter"
local LSPHelp = require "mason.ui.components.help.lsp"
local LinterHelp = require "mason.ui.components.help.linter"

---@param state InstallerUiState
local function Ship(state)
    local ship_indent = { (" "):rep(state.view.ship_indentation), "" }
    -- stylua: ignore start
    local ship = {
        { ship_indent,             p.muted "/^v^\\", p.none "         |    |    |" },
        { ship_indent,                          p.none "             )_)  )_)  )_)     ", p.muted "/^v^\\" },
        { ship_indent, p.muted "   ", p.muted "/^v^\\", p.none "    )___))___))___)\\     ", p.highlight_secondary(state.view.ship_exclamation) },
        { ship_indent,                          p.none "           )____)____)_____)\\\\" },
        { ship_indent,                          p.none "         _____|____|____|____\\\\\\__" },
        { ship_indent,  p.muted "         ",            p.none "\\                   /" },
    }
    -- stylua: ignore end
    local water = {
        { p.highlight "  ^^^^^ ^^^^^^^^  ^^^^^ ^^^^^  ^^^^^ ^^^^ <><  " },
        { p.highlight "    ^^^^  ^^  ^^^    ^ ^^^    ^^^ <>< ^^^^     " },
        { p.highlight "     ><> ^^^     ^^    ><> ^^     ^^    ^      " },
    }
    if state.view.ship_indentation < 0 then
        for _, shipline in ipairs(ship) do
            local removed_chars = 0
            for _, span in ipairs(shipline) do
                local span_length = #span[1]
                local chars_to_remove = (math.abs(state.view.ship_indentation) - removed_chars)
                span[1] = string.sub(span[1], chars_to_remove + 1)
                removed_chars = removed_chars + (span_length - #span[1])
            end
        end
    end
    return Ui.Node {
        Ui.HlTextNode(ship),
        Ui.HlTextNode(water),
    }
end

---@param state InstallerUiState
local function GenericHelp(state)
    local keymap_tuples = {
        { "Toggle help", settings.current.ui.keymaps.toggle_help },
        { "Toggle package info", settings.current.ui.keymaps.toggle_package_expand },
        { "Toggle package installation log", settings.current.ui.keymaps.toggle_package_install_log },
        { "Apply language filter", settings.current.ui.keymaps.apply_language_filter },
        { "Install package", settings.current.ui.keymaps.install_package },
        { "Uninstall package", settings.current.ui.keymaps.uninstall_package },
        { "Update package", settings.current.ui.keymaps.update_package },
        { "Update all outdated packages", settings.current.ui.keymaps.update_all_packages },
        { "Check for new package version", settings.current.ui.keymaps.check_package_version },
        { "Check for new versions (all packages)", settings.current.ui.keymaps.check_outdated_packages },
        { "Cancel installation of package", settings.current.ui.keymaps.cancel_installation },
        { "Close window", "q" },
        { "Close window", "<Esc>" },
    }

    local is_current_settings_expanded = state.view.is_current_settings_expanded

    return Ui.Node {
        Ui.HlTextNode {
            { p.muted "Mason log: ", p.none(log.outfile) },
        },
        Ui.EmptyLine(),
        Ui.HlTextNode {
            {
                p.Bold "Registries",
            },
            {
                p.muted "Packages are sourced from the following registries:",
            },
            unpack(_.map(function(registry)
                return { p.none(" - " .. registry.name) }
            end, state.info.registries)),
        },
        Ui.EmptyLine(),
        Ui.Table {
            {
                p.Bold "Keyboard shortcuts",
            },
            unpack(_.map(function(keymap_tuple)
                return { p.muted(keymap_tuple[1]), p.highlight(keymap_tuple[2]) }
            end, keymap_tuples)),
        },
        Ui.EmptyLine(),
        Ui.HlTextNode {
            { p.Bold "Problems installing packages" },
            {
                p.muted "Make sure you meet the minimum requirements to install packages. For debugging, refer to:",
            },
        },
        Ui.CascadingStyleNode({ "INDENT" }, {
            Ui.HlTextNode {
                {
                    p.highlight ":help mason-debugging",
                },
                {
                    p.highlight ":checkhealth mason",
                },
            },
        }),
        Ui.EmptyLine(),
        Ui.HlTextNode {
            { p.Bold "Problems with package functionality" },
            { p.muted "Please refer to each package's own homepage for further assistance." },
        },
        Ui.EmptyLine(),
        Ui.HlTextNode {
            { p.Bold "How do I use installed packages?" },
            { p.muted "Mason only makes packages available for use. It does not automatically integrate" },
            { p.muted "these into Neovim. You have multiple different options for using any given" },
            { p.muted "package, and you are free to pick and choose as you see fit." },
            {
                p.muted "See ",
                p.highlight ":help mason-how-to-use-packages",
                p.muted " for a recommendation.",
            },
        },
        Ui.EmptyLine(),
        Ui.HlTextNode {
            { p.Bold "Missing a package?" },
            { p.muted "Please consider contributing to mason.nvim:" },
        },
        Ui.CascadingStyleNode({ "INDENT" }, {
            Ui.HlTextNode {
                {
                    p.none "- ",
                    p.highlight "https://github.com/mason-org/mason.nvim/blob/main/CONTRIBUTING.md",
                },
                {
                    p.none "- ",
                    p.highlight "https://github.com/mason-org/mason.nvim/blob/main/doc/reference.md",
                },
            },
        }),
        Ui.EmptyLine(),
        Ui.HlTextNode {
            {
                p.Bold(("%s Current settings"):format(is_current_settings_expanded and "↓" or "→")),
                p.highlight " :help mason-settings",
            },
        },
        Ui.Keybind(settings.current.ui.keymaps.toggle_package_expand, "TOGGLE_EXPAND_CURRENT_SETTINGS", nil),
        Ui.When(is_current_settings_expanded, function()
            local settings_split_by_newline = vim.split(vim.inspect(settings.current), "\n")
            local current_settings = _.map(function(line)
                return { p.muted(line) }
            end, settings_split_by_newline)
            return Ui.HlTextNode(current_settings)
        end),
    }
end

---@param state InstallerUiState
return function(state)
    ---@type INode
    local heading = Ui.Node {}
    if state.view.current == "LSP" then
        heading = Ui.Node {
            LSPHelp(state),
            Ui.EmptyLine(),
        }
    elseif state.view.current == "DAP" then
        heading = Ui.Node {
            DAPHelp(state),
            Ui.EmptyLine(),
        }
    elseif state.view.current == "Linter" then
        heading = Ui.Node {
            LinterHelp(state),
            Ui.EmptyLine(),
        }
    elseif state.view.current == "Formatter" then
        heading = Ui.Node {
            FormatterHelp(state),
            Ui.EmptyLine(),
        }
    end

    return Ui.CascadingStyleNode({ "INDENT" }, {
        Ui.HlTextNode(state.view.has_changed and p.none "" or p.Comment "(change view by pressing its number)"),
        heading,
        GenericHelp(state),
        Ui.EmptyLine(),
        Ship(state),
        Ui.EmptyLine(),
    })
end
