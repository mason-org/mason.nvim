local Ui = require "mason-core.ui"
local _ = require "mason-core.functional"
local p = require "mason.ui.palette"
local settings = require "mason.settings"

local JsonSchema = require "mason.ui.components.json-schema"

---@param props { state: InstallerUiState, heading: INode, packages: Package[], list_item_renderer: (fun(package: Package, state: InstallerUiState): INode), hide_when_empty: boolean }
local function PackageListContainer(props)
    local items = {}
    for i = 1, #props.packages do
        local pkg = props.packages[i]
        if props.state.packages.visible[pkg.name] then
            items[#items + 1] = props.list_item_renderer(pkg, props.state)
        end
    end

    if props.hide_when_empty and #items == 0 then
        return Ui.Node {}
    end

    return Ui.Node {
        props.heading,
        Ui.VirtualTextNode { p.Comment(("(%d)"):format(#items)) },
        Ui.CascadingStyleNode({ "INDENT" }, items),
        Ui.When(
            #items == 0,
            Ui.CascadingStyleNode({ "CENTERED" }, {
                Ui.HlTextNode(p.Comment "No packages."),
            })
        ),
        Ui.EmptyLine(),
    }
end

---@param executables table<string, string>?
local function ExecutablesTable(executables)
    if not executables or _.size(executables) == 0 then
        return Ui.Node {}
    end
    local rows = {}
    for executable in pairs(executables) do
        table.insert(rows, { p.none "", p.Bold(executable) })
    end
    rows[1][1] = p.muted "executables"
    return rows
end

---@param state InstallerUiState
---@param pkg Package
---@param is_installed boolean
local function ExpandedPackageInfo(state, pkg, is_installed)
    local pkg_state = state.packages.states[pkg.name]
    return Ui.CascadingStyleNode({ "INDENT" }, {
        Ui.When(not is_installed and pkg.spec.deprecation, function()
            return Ui.HlTextNode(p.warning(("Deprecation message: %s"):format(pkg.spec.deprecation.message)))
        end),
        Ui.HlTextNode(_.map(function(line)
            return { p.Comment(line) }
        end, _.split("\n", pkg.spec.description))),
        Ui.EmptyLine(),
        Ui.Table(_.concat(
            _.filter(_.identity, {
                is_installed and {
                    p.muted "installed version",
                    pkg_state.version and p.Bold(pkg_state.version) or p.muted "-",
                } or {
                    p.muted "version",
                    p.Bold(pkg:get_latest_version()),
                },
                pkg_state.new_version and {
                    p.muted "latest version",
                    p.muted(pkg_state.new_version),
                },
                pkg_state.installed_purl and {
                    p.muted "installed purl",
                    p.highlight(pkg_state.installed_purl),
                } or {
                    p.muted "purl",
                    p.highlight(pkg.spec.source.id),
                },
                {
                    p.muted "homepage",
                    pkg.spec.homepage and p.highlight(pkg.spec.homepage) or p.muted "-",
                },
                {
                    p.muted "languages",
                    #pkg.spec.languages > 0 and p.Bold(table.concat(pkg.spec.languages, ", ")) or p.muted "-",
                },
                {
                    p.muted "categories",
                    #pkg.spec.categories > 0 and p.Bold(table.concat(pkg.spec.categories, ", ")) or p.muted "-",
                },
            }),
            Ui.When(is_installed, function()
                return ExecutablesTable(pkg_state.linked_executables)
            end)
        )),
        Ui.When(pkg_state.lsp_settings_schema ~= nil, function()
            local has_expanded = pkg_state.expanded_json_schemas["lsp"]
            return Ui.Node {
                Ui.EmptyLine(),
                Ui.HlTextNode {
                    {
                        p.Bold(("%s LSP server configuration schema"):format(has_expanded and "↓" or "→")),
                        p.Comment((" (press enter to %s)"):format(has_expanded and "collapse" or "expand")),
                    },
                },
                Ui.Keybind(
                    settings.current.ui.keymaps.toggle_package_expand,
                    "TOGGLE_JSON_SCHEMA",
                    { package = pkg, schema_id = "lsp" }
                ),
                Ui.When(has_expanded, function()
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(
                            p.muted "This is a read-only overview of the settings this server accepts. Note that some settings might not apply to neovim."
                        ),
                        Ui.EmptyLine(),
                        JsonSchema(pkg, "lsp", pkg_state, pkg_state.lsp_settings_schema),
                    })
                end),
            }
        end),
        Ui.EmptyLine(),
    })
end

local get_package_search_keywords = _.compose(_.join ", ", _.map(_.to_lower), _.path { "spec", "languages" })

---@param state InstallerUiState
---@param pkg Package
---@param opts { keybinds: KeybindHandlerNode[], icon: string[], is_installed: boolean, sticky: StickyCursorNode? }
local function PackageComponent(state, pkg, opts)
    local pkg_state = state.packages.states[pkg.name]
    local is_expanded = state.packages.expanded == pkg.name
    local label = (is_expanded or pkg_state.has_transitioned) and p.Bold(" " .. pkg.name) or p.none(" " .. pkg.name)

    local package_line = {
        opts.icon,
        label,
    }

    local pkg_aliases = pkg:get_aliases()
    if #pkg_aliases > 0 then
        package_line[#package_line + 1] = p.Comment(" " .. table.concat(pkg:get_aliases(), ", "))
    end
    if state.view.is_searching then
        package_line[#package_line + 1] = p.Comment((" (keywords: %s)"):format(get_package_search_keywords(pkg)))
    end
    if not opts.is_installed and pkg.spec.deprecation ~= nil then
        package_line[#package_line + 1] = p.warning " deprecated"
    end

    return Ui.Node {
        Ui.HlTextNode { package_line },
        opts.sticky or Ui.Node {},
        Ui.When(opts.is_installed and pkg.spec.deprecation ~= nil, function()
            return Ui.DiagnosticsNode {
                message = ("deprecated: %s"):format(pkg.spec.deprecation.message),
                severity = vim.diagnostic.severity.WARN,
                source = ("Deprecated since version %s"):format(pkg.spec.deprecation.since),
            }
        end),
        Ui.Keybind(settings.current.ui.keymaps.check_package_version, "CHECK_NEW_PACKAGE_VERSION", pkg),
        Ui.When(pkg_state.new_version ~= nil, function()
            return Ui.DiagnosticsNode {
                message = ("new version available: %s -> %s"):format(pkg_state.version or "-", pkg_state.new_version),
                severity = vim.diagnostic.severity.INFO,
            }
        end),
        Ui.Node(opts.keybinds),
        Ui.When(is_expanded, function()
            return ExpandedPackageInfo(state, pkg, opts.is_installed)
        end),
    }
end

local get_outdated_packages_preview = _.if_else(
    _.compose(_.lte(4), _.size),
    _.compose(_.join ", ", _.map(_.prop "name")),
    _.compose(
        _.join ", ",
        _.converge(_.concat, {
            _.compose(_.map(_.prop "name"), _.take(3)),
            function(pkgs)
                return { ("and %d more…"):format(#pkgs - 3) }
            end,
        })
    )
)

---@param state InstallerUiState
local function Installed(state)
    return Ui.Node {
        Ui.Keybind(settings.current.ui.keymaps.check_outdated_packages, "UPDATE_REGISTRY", nil, true),
        PackageListContainer {
            state = state,
            heading = Ui.Node {
                Ui.HlTextNode(p.heading "Installed"),
                Ui.When(state.info.registry_update.in_progress, function()
                    local styling = state.info.registry_update.percentage_complete == 1 and p.highlight_block
                        or p.muted_block
                    local is_all_registries_installed = _.all(_.prop "is_installed", state.info.registries)
                    local registry_count = #state.info.registries
                    local text
                    if registry_count > 1 then
                        text = p.Comment(
                            is_all_registries_installed and ("updating %d registries "):format(registry_count)
                                or ("installing %d registries "):format(registry_count)
                        )
                    else
                        text = p.Comment(is_all_registries_installed and "updating registry " or "installing registry ")
                    end
                    return Ui.VirtualTextNode {
                        text,
                        styling(
                            ("%-4s"):format(math.floor(state.info.registry_update.percentage_complete * 100) .. "%")
                        ),
                        styling((" "):rep(state.info.registry_update.percentage_complete * 15)),
                    }
                end),
                Ui.When(
                    not state.info.registry_update.in_progress and #state.packages.outdated_packages > 0,
                    function()
                        return Ui.VirtualTextNode {
                            p.muted "Press ",
                            p.highlight(settings.current.ui.keymaps.update_all_packages),
                            p.muted " to update ",
                            p.highlight(tostring(#state.packages.outdated_packages)),
                            p.muted(#state.packages.outdated_packages > 1 and " packages " or " package "),
                            p.Comment(("(%s)"):format(get_outdated_packages_preview(state.packages.outdated_packages))),
                        }
                    end
                ),
            },
            packages = state.packages.installed,
            ---@param pkg Package
            list_item_renderer = function(pkg)
                return PackageComponent(state, pkg, {
                    is_installed = true,
                    icon = p.highlight(settings.current.ui.icons.package_installed),
                    keybinds = {
                        Ui.Keybind(settings.current.ui.keymaps.update_package, "INSTALL_PACKAGE", pkg),
                        Ui.Keybind(settings.current.ui.keymaps.uninstall_package, "UNINSTALL_PACKAGE", pkg),
                        Ui.Keybind(settings.current.ui.keymaps.toggle_package_expand, "TOGGLE_EXPAND_PACKAGE", pkg),
                    },
                    sticky = Ui.StickyCursor { id = ("%s-installed"):format(pkg.name) },
                })
            end,
        },
    }
end

---@param pkg Package
---@param state InstallerUiState
local function InstallingPackageComponent(pkg, state)
    ---@type UiPackageState
    local pkg_state = state.packages.states[pkg.name]
    local current_state = pkg_state.is_terminated and p.Comment " (cancelling)" or p.none ""
    local tail = pkg_state.short_tailed_output
            and ("▶ # [%d/%d] %s"):format(
                #pkg_state.tailed_output,
                #pkg_state.tailed_output,
                pkg_state.short_tailed_output
            )
        or ""
    return Ui.Node {
        Ui.HlTextNode {
            {
                pkg_state.has_failed and p.error(settings.current.ui.icons.package_uninstalled)
                    or p.highlight(settings.current.ui.icons.package_pending),
                p.none(" " .. pkg.name),
                current_state,
                pkg_state.latest_spawn and p.Comment((" $ %s"):format(pkg_state.latest_spawn)) or p.none "",
            },
        },
        Ui.StickyCursor { id = ("%s-installing"):format(pkg.name) },
        Ui.Keybind(settings.current.ui.keymaps.cancel_installation, "TERMINATE_PACKAGE_HANDLE", pkg),
        Ui.Keybind(settings.current.ui.keymaps.install_package, "INSTALL_PACKAGE", pkg),
        Ui.CascadingStyleNode({ "INDENT" }, {
            Ui.HlTextNode(pkg_state.is_log_expanded and p.Bold "▼ Displaying full log" or p.muted(tail)),
            Ui.Keybind(settings.current.ui.keymaps.toggle_package_install_log, "TOGGLE_INSTALL_LOG", pkg),
            Ui.StickyCursor { id = ("%s-toggle-install-log"):format(pkg.name) },
        }),
        Ui.When(pkg_state.is_log_expanded, function()
            return Ui.CascadingStyleNode({ "INDENT", "INDENT" }, {
                Ui.HlTextNode(_.map(function(line)
                    return { p.muted(line) }
                end, pkg_state.tailed_output)),
            })
        end),
    }
end

---@param state InstallerUiState
local function Installing(state)
    local packages = state.packages.installing
    return PackageListContainer {
        state = state,
        heading = Ui.Node {
            Ui.HlTextNode(p.heading "Installing"),
            Ui.StickyCursor { id = "installing-section" },
            Ui.Keybind(settings.current.ui.keymaps.cancel_installation, "TERMINATE_PACKAGE_HANDLES", packages),
        },
        hide_when_empty = true,
        packages = packages,
        ---@param pkg Package
        list_item_renderer = InstallingPackageComponent,
    }
end

---@param state InstallerUiState
local function Queued(state)
    local packages = state.packages.queued
    return PackageListContainer {
        state = state,
        heading = Ui.Node {
            Ui.HlTextNode(p.heading "Queued"),
            Ui.StickyCursor { id = "queued-section" },
            Ui.Keybind(settings.current.ui.keymaps.cancel_installation, "TERMINATE_PACKAGE_HANDLES", packages),
        },
        packages = packages,
        hide_when_empty = true,
        ---@param pkg Package
        list_item_renderer = function(pkg)
            return Ui.Node {
                Ui.HlTextNode {
                    { p.highlight(settings.current.ui.icons.package_pending), p.none(" " .. pkg.name) },
                },
                Ui.StickyCursor { id = ("%s-installing"):format(pkg.spec.name) },
                Ui.Keybind(settings.current.ui.keymaps.cancel_installation, "TERMINATE_PACKAGE_HANDLE", pkg),
            }
        end,
    }
end

---@param state InstallerUiState
local function Failed(state)
    local packages = state.packages.failed
    if #packages == 0 then
        return Ui.Node {}
    end
    return PackageListContainer {
        state = state,
        heading = Ui.HlTextNode(p.heading "Failed"),
        packages = packages,
        list_item_renderer = InstallingPackageComponent,
    }
end

---@param state InstallerUiState
local function Uninstalled(state)
    return PackageListContainer {
        state = state,
        heading = Ui.HlTextNode(p.heading "Available"),
        packages = state.packages.uninstalled,
        ---@param pkg Package
        list_item_renderer = function(pkg)
            return PackageComponent(state, pkg, {
                icon = p.muted(settings.current.ui.icons.package_uninstalled),
                keybinds = {
                    Ui.Keybind(settings.current.ui.keymaps.install_package, "INSTALL_PACKAGE", pkg),
                    Ui.Keybind(settings.current.ui.keymaps.toggle_package_expand, "TOGGLE_EXPAND_PACKAGE", pkg),
                },
                sticky = Ui.StickyCursor { id = ("%s-uninstalled"):format(pkg.name) },
            })
        end,
    }
end

---@param state InstallerUiState
return function(state)
    return Ui.CascadingStyleNode({ "INDENT" }, {
        Failed(state),
        Installing(state),
        Queued(state),
        Installed(state),
        Uninstalled(state),
    })
end
