-- !!!
-- in dire need of rework, proceed with caution
-- !!!
local Package = require "mason-core.package"
local Ui = require "mason-core.ui"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local display = require "mason-core.ui.display"
local notify = require "mason-core.notify"
local registry = require "mason-registry"
local settings = require "mason.settings"

local Header = require "mason.ui.components.header"
local Help = require "mason.ui.components.help"
local LanguageFilter = require "mason.ui.components.language-filter"
local Main = require "mason.ui.components.main"
local Tabs = require "mason.ui.components.tabs"

require "mason.ui.colors"

---@param state InstallerUiState
local function GlobalKeybinds(state)
    return Ui.Node {
        Ui.Keybind(settings.current.ui.keymaps.toggle_help, "TOGGLE_HELP", nil, true),
        Ui.Keybind("q", "CLOSE_WINDOW", nil, true),
        Ui.When(not state.view.language_filter, Ui.Keybind("<Esc>", "CLOSE_WINDOW", nil, true)),
        Ui.When(state.view.language_filter, Ui.Keybind("<Esc>", "CLEAR_LANGUAGE_FILTER", nil, true)),
        Ui.When(state.view.is_searching, Ui.Keybind("<Esc>", "CLEAR_SEARCH_MODE", nil, true)),
        Ui.Keybind(settings.current.ui.keymaps.apply_language_filter, "LANGUAGE_FILTER", nil, true),
        Ui.Keybind(settings.current.ui.keymaps.update_all_packages, "UPDATE_ALL_PACKAGES", nil, true),

        Ui.Keybind("1", "SET_VIEW", "All", true),
        Ui.Keybind("2", "SET_VIEW", "LSP", true),
        Ui.Keybind("3", "SET_VIEW", "DAP", true),
        Ui.Keybind("4", "SET_VIEW", "Linter", true),
        Ui.Keybind("5", "SET_VIEW", "Formatter", true),
    }
end

---@class UiPackageState
---@field expanded_json_schema_keys table<string, table<string, boolean>>
---@field expanded_json_schemas table<string, boolean>
---@field has_expanded_before boolean
---@field has_transitioned boolean
---@field is_terminated boolean
---@field is_log_expanded boolean
---@field has_failed boolean
---@field latest_spawn string?
---@field linked_executables table<string, string>?
---@field installed_purl string?
---@field lsp_settings_schema table?
---@field new_version string?
---@field short_tailed_output string?
---@field tailed_output string[]
---@field version string?

---@class InstallerUiState
local INITIAL_STATE = {
    info = {
        ---@type string | nil
        used_disk_space = nil,
        ---@type { name: string, is_installed: boolean }[]
        registries = {},
        registry_update = {
            ---@type string?
            error = nil,
            in_progress = false,
            percentage_complete = 0,
        },
    },
    view = {
        is_searching = false,
        is_showing_help = false,
        is_current_settings_expanded = false,
        language_filter = nil,
        current = "All",
        has_changed = false,
        ship_indentation = 0,
        ship_exclamation = "",
    },
    header = {
        title_prefix = "", -- for animation
    },
    packages = {
        ---@type Package[]
        outdated_packages = {},
        ---@type Package[]
        all = {},
        ---@type table<string, boolean>
        visible = {},
        ---@type string|nil
        expanded = nil,
        ---@type table<string, UiPackageState>
        states = {},
        ---@type Package[]
        installed = {},
        ---@type Package[]
        installing = {},
        ---@type Package[]
        failed = {},
        ---@type Package[]
        queued = {},
        ---@type Package[]
        uninstalled = {},
    },
}

---@generic T
---@param list T[]
---@param item T
---@return T
local function remove(list, item)
    for i, v in ipairs(list) do
        if v == item then
            table.remove(list, i)
            return list
        end
    end
    return list
end

local window = display.new_view_only_win("mason.nvim", "mason")

window.view(
    ---@param state InstallerUiState
    function(state)
        return Ui.Node {
            GlobalKeybinds(state),
            Header(state),
            Tabs(state),
            Ui.When(state.view.is_showing_help, function()
                return Help(state)
            end),
            Ui.When(not state.view.is_showing_help, function()
                return Ui.Node {
                    LanguageFilter(state),
                    Main(state),
                }
            end),
        }
    end
)

local mutate_state, get_state = window.state(INITIAL_STATE)

window.events:on("search:enter", function()
    mutate_state(function(state)
        state.view.is_searching = true
    end)
    vim.schedule(function()
        vim.cmd "redraw"
    end)
end)

window.events:on("search:leave", function(search)
    if search == "" and vim.fn.getreg "/" == "" then
        mutate_state(function(state)
            state.view.is_searching = false
        end)
    end
end)

---@param pkg Package
---@param group string
---@param tail boolean? Whether to insert at the end.
local function mutate_package_grouping(pkg, group, tail)
    mutate_state(function(state)
        remove(state.packages.installing, pkg)
        remove(state.packages.queued, pkg)
        remove(state.packages.uninstalled, pkg)
        remove(state.packages.installed, pkg)
        remove(state.packages.failed, pkg)
        if tail then
            table.insert(state.packages[group], pkg)
        else
            table.insert(state.packages[group], 1, pkg)
        end
        state.packages.states[pkg.name].has_transitioned = true
    end)
end

---@param mutate_fn fun(state: InstallerUiState)
local function mutate_package_visibility(mutate_fn)
    mutate_state(function(state)
        mutate_fn(state)
        local view_predicate = {
            ["All"] = _.T,
            ["LSP"] = _.prop_satisfies(_.any(_.equals(Package.Cat.LSP)), "categories"),
            ["DAP"] = _.prop_satisfies(_.any(_.equals(Package.Cat.DAP)), "categories"),
            ["Linter"] = _.prop_satisfies(_.any(_.equals(Package.Cat.Linter)), "categories"),
            ["Formatter"] = _.prop_satisfies(_.any(_.equals(Package.Cat.Formatter)), "categories"),
        }
        local language_predicate = _.if_else(
            _.always(state.view.language_filter),
            _.prop_satisfies(_.any(_.equals(state.view.language_filter)), "languages"),
            _.T
        )
        for __, pkg in ipairs(state.packages.all) do
            state.packages.visible[pkg.name] =
                _.all_pass({ view_predicate[state.view.current], language_predicate }, pkg.spec)
        end
    end)
end

---@return UiPackageState
local function create_initial_package_state()
    return {
        expanded_json_schema_keys = {},
        expanded_json_schemas = {},
        has_expanded_before = false,
        has_transitioned = false,
        is_terminated = false,
        is_log_expanded = false,
        has_failed = false,
        latest_spawn = nil,
        linked_executables = nil,
        installed_purl = nil,
        lsp_settings_schema = nil,
        new_version = nil,
        short_tailed_output = nil,
        tailed_output = {},
        version = nil,
    }
end

---@param handle InstallHandle
local function setup_handle(handle)
    local function handle_state_change()
        if handle.state == "QUEUED" then
            mutate_package_grouping(handle.package, "queued", true)
        elseif handle.state == "ACTIVE" then
            mutate_package_grouping(handle.package, "installing", true)
        elseif handle.state == "CLOSED" then
            mutate_state(function(state)
                state.packages.states[handle.package.name].is_terminated = false
            end)
        end
    end

    local function handle_spawnhandle_change()
        mutate_state(function(state)
            state.packages.states[handle.package.name].latest_spawn =
                handle:peek_spawn_handle():map(tostring):map(_.gsub("\n", "\\n ")):or_else(nil)
        end)
    end

    ---@param chunk string
    local function handle_output(chunk)
        mutate_state(function(state)
            local pkg_state = state.packages.states[handle.package.name]
            local lines = vim.split(chunk, "\n")
            for i = 1, #lines do
                local line = lines[i]
                if i == 1 and pkg_state.tailed_output[#pkg_state.tailed_output] then
                    pkg_state.tailed_output[#pkg_state.tailed_output] = pkg_state.tailed_output[#pkg_state.tailed_output]
                        .. line
                else
                    pkg_state.tailed_output[#pkg_state.tailed_output + 1] = line
                end
                if not line:match "^%s*$" then
                    pkg_state.short_tailed_output = line:gsub("^%s+", "")
                end
            end
        end)
    end

    local function handle_terminate()
        mutate_state(function(state)
            state.packages.states[handle.package.name].is_terminated = handle.is_terminated
            if handle:is_queued() then
                -- This is really already handled by the "install:failed" handler, but for UX reasons we handle
                -- terminated, queued, handlers here. The reason for this is that a queued handler, which is
                -- aborted, will not fail its installation until it acquires a semaphore permit, leading to a weird
                -- UX that may be perceived as non-functional.
                mutate_package_grouping(handle.package, handle.package:is_installed() and "installed" or "uninstalled")
            end
        end)
    end

    handle:on("terminate", handle_terminate)
    handle:on("state:change", handle_state_change)
    handle:on("spawn_handles:change", handle_spawnhandle_change)
    handle:on("stdout", handle_output)
    handle:on("stderr", handle_output)

    -- hydrate initial state
    handle_state_change()
    handle_spawnhandle_change()
    mutate_state(function(state)
        state.packages.states[handle.package.name] = create_initial_package_state()
    end)
end

---@param pkg Package
local function hydrate_detailed_package_state(pkg)
    mutate_state(function(state)
        -- initialize expanded keys table
        state.packages.states[pkg.name].expanded_json_schema_keys["lsp"] = state.packages.states[pkg.name].expanded_json_schema_keys["lsp"]
            or {}
        state.packages.states[pkg.name].lsp_settings_schema = pkg:get_lsp_settings_schema():or_else(nil)
        state.packages.states[pkg.name].version = pkg:get_installed_version()
    end)

    pkg:get_receipt():if_present(
        ---@param receipt InstallReceipt
        function(receipt)
            mutate_state(function(state)
                state.packages.states[pkg.name].linked_executables = receipt:get_links().bin
                state.packages.states[pkg.name].installed_purl = receipt:get_installed_purl()
            end)
        end
    )
end

local help_animation
do
    local help_command = ":help"
    local help_command_len = #help_command
    help_animation = Ui.animation {
        function(tick)
            mutate_state(function(state)
                state.header.title_prefix = help_command:sub(help_command_len - tick, help_command_len)
            end)
        end,
        range = { 0, help_command_len },
        delay_ms = 80,
    }
end

local ship_animation = Ui.animation {
    function(tick)
        mutate_state(function(state)
            state.view.ship_indentation = tick
            if tick > -5 then
                state.view.ship_exclamation = "https://github.com/sponsors/williamboman"
            elseif tick > -27 then
                state.view.ship_exclamation = "Sponsor mason.nvim development!"
            else
                state.view.ship_exclamation = ""
            end
        end)
    end,
    range = { -35, 5 },
    delay_ms = 250,
}

local function toggle_help()
    mutate_state(function(state)
        state.view.is_showing_help = not state.view.is_showing_help
        if state.view.is_showing_help then
            help_animation()
            ship_animation()
        end
    end)
end

local function set_view(event)
    local view = event.payload
    mutate_package_visibility(function(state)
        state.view.current = view
        state.view.has_changed = true
    end)
    if window.is_open() then
        local cursor_line = window.get_cursor()[1]
        if cursor_line > (window.get_win_config().height * 0.75) then
            window.set_sticky_cursor "tabs"
        end
    end
end

local function terminate_package_handle(event)
    ---@type Package
    local pkg = event.payload
    pkg:get_install_handle():if_present(
        ---@param handle InstallHandle
        function(handle)
            if not handle:is_closed() then
                vim.schedule_wrap(notify)(("Cancelling installation of %q."):format(pkg.name))
                handle:terminate()
            end
        end
    )

    pkg:get_uninstall_handle():if_present(
        ---@param handle InstallHandle
        function(handle)
            if not handle:is_closed() then
                vim.schedule_wrap(notify)(("Cancelling uninstallation of %q."):format(pkg.name))
                handle:terminate()
            end
        end
    )
end

local function terminate_all_package_handles(event)
    ---@type Package[]
    local pkgs = _.list_copy(event.payload) -- we copy because list is mutated while iterating it
    for _, pkg in ipairs(pkgs) do
        pkg:get_install_handle():if_present(
            ---@param handle InstallHandle
            function(handle)
                if not handle:is_closed() then
                    handle:terminate()
                end
            end
        )
    end
end

local function install_package(event)
    ---@type AbstractPackage
    local pkg = event.payload
    if not pkg:is_installing() then
        pkg:install()
    end
    mutate_state(function(state)
        state.packages.outdated_packages = _.filter(_.complement(_.equals(pkg)), state.packages.outdated_packages)
    end)
end

local function uninstall_package(event)
    ---@type AbstractPackage
    local pkg = event.payload
    if not pkg:is_uninstalling() then
        pkg:uninstall()
    end
end

local function toggle_expand_package(event)
    ---@type Package
    local pkg = event.payload
    mutate_state(function(state)
        if state.packages.expanded == pkg.name then
            state.packages.expanded = nil
        else
            if not state.packages.states[pkg.name].has_expanded_before then
                hydrate_detailed_package_state(pkg)
                state.packages.states[pkg.name].has_expanded_before = true
            end
            state.packages.expanded = pkg.name
        end
    end)
end

---@param pkg Package
local function check_new_package_version(pkg)
    local installed_version = pkg:get_installed_version()
    mutate_state(function(state)
        state.packages.states[pkg.name].version = installed_version
    end)
    local latest_version = pkg:get_latest_version()
    if latest_version ~= installed_version and pkg:is_installable { version = latest_version } then
        mutate_state(function(state)
            state.packages.states[pkg.name].new_version = latest_version
        end)
        return true
    else
        mutate_state(function(state)
            state.packages.states[pkg.name].new_version = nil
        end)
        return false
    end
end

local function check_new_package_versions()
    mutate_state(function(state)
        local outdated_packages = {}
        for _, pkg in ipairs(state.packages.installed) do
            local current_version = pkg:get_installed_version()
            local latest_version = pkg:get_latest_version()
            if current_version ~= latest_version then
                state.packages.states[pkg.name].version = current_version
                state.packages.states[pkg.name].new_version = latest_version
                table.insert(outdated_packages, pkg)
            else
                state.packages.states[pkg.name].new_version = nil
            end
        end
        state.packages.outdated_packages = outdated_packages
    end)
end

local function toggle_json_schema(event)
    local package, schema_id = event.payload.package, event.payload.schema_id
    mutate_state(function(state)
        state.packages.states[package.name].expanded_json_schemas[schema_id] =
            not state.packages.states[package.name].expanded_json_schemas[schema_id]
    end)
end

local function toggle_json_schema_keys(event)
    local package, schema_id, key = event.payload.package, event.payload.schema_id, event.payload.key
    mutate_state(function(state)
        state.packages.states[package.name].expanded_json_schema_keys[schema_id][key] =
            not state.packages.states[package.name].expanded_json_schema_keys[schema_id][key]
    end)
end

local function filter()
    vim.ui.select(_.sort_by(_.identity, _.keys(Package.Lang)), {
        prompt = "Select language:",
        kind = "mason.ui.language-filter",
    }, function(choice)
        if not choice or choice == "" then
            return
        end
        mutate_package_visibility(function(state)
            state.view.language_filter = choice
        end)
    end)
end

local function clear_filter()
    mutate_package_visibility(function(state)
        state.view.language_filter = nil
    end)
end

local function clear_search_mode()
    mutate_state(function(state)
        state.view.is_searching = false
    end)
end

local function toggle_expand_current_settings()
    mutate_state(function(state)
        state.view.is_current_settings_expanded = not state.view.is_current_settings_expanded
    end)
end

local function update_all_packages()
    local state = get_state()
    _.each(function(pkg)
        pkg:install()
    end, state.packages.outdated_packages)
    mutate_state(function(state)
        state.packages.outdated_packages = {}
    end)
end

local function toggle_install_log(event)
    ---@type Package
    local pkg = event.payload
    mutate_state(function(state)
        state.packages.states[pkg.name].is_log_expanded = not state.packages.states[pkg.name].is_log_expanded
    end)
end

local effects = {
    ["CHECK_NEW_PACKAGE_VERSION"] = a.scope(_.compose(_.partial(pcall, check_new_package_version), _.prop "payload")),
    ["UPDATE_REGISTRY"] = function()
        registry.update()
    end,
    ["CLEAR_LANGUAGE_FILTER"] = clear_filter,
    ["CLEAR_SEARCH_MODE"] = clear_search_mode,
    ["CLOSE_WINDOW"] = window.close,
    ["INSTALL_PACKAGE"] = install_package,
    ["LANGUAGE_FILTER"] = filter,
    ["SET_VIEW"] = set_view,
    ["TERMINATE_PACKAGE_HANDLE"] = terminate_package_handle,
    ["TERMINATE_PACKAGE_HANDLES"] = terminate_all_package_handles,
    ["TOGGLE_EXPAND_CURRENT_SETTINGS"] = toggle_expand_current_settings,
    ["TOGGLE_EXPAND_PACKAGE"] = toggle_expand_package,
    ["TOGGLE_HELP"] = toggle_help,
    ["TOGGLE_INSTALL_LOG"] = toggle_install_log,
    ["TOGGLE_JSON_SCHEMA"] = toggle_json_schema,
    ["TOGGLE_JSON_SCHEMA_KEY"] = toggle_json_schema_keys,
    ["UNINSTALL_PACKAGE"] = uninstall_package,
    ["UPDATE_ALL_PACKAGES"] = update_all_packages,
}

local registered_packages = {}

---@param pkg Package
local function setup_package(pkg)
    if registered_packages[pkg] then
        return
    end

    mutate_state(function(state)
        for _, group in ipairs {
            state.packages.installed,
            state.packages.uninstalled,
            state.packages.failed,
            state.packages.outdated_packages,
        } do
            for i, existing_pkg in ipairs(group) do
                if existing_pkg.name == pkg.name and pkg ~= existing_pkg then
                    -- New package instance (i.e. from a new, updated, registry source).
                    -- Release the old package instance.
                    table.remove(group, i)
                end
            end
        end
    end)

    -- hydrate initial state
    mutate_state(function(state)
        state.packages.states[pkg.name] = create_initial_package_state()
        state.packages.visible[pkg.name] = true
        table.insert(state.packages[pkg:is_installed() and "installed" or "uninstalled"], pkg)
    end)

    pkg:get_install_handle():if_present(setup_handle)
    pkg:on("install:handle", setup_handle)

    pkg:on("install:success", function()
        vim.schedule(function()
            notify(("%s was successfully installed."):format(pkg.name))
        end)
        mutate_state(function(state)
            state.packages.states[pkg.name] = create_initial_package_state()
            if state.packages.expanded == pkg.name then
                hydrate_detailed_package_state(pkg)
            end
        end)
        mutate_package_grouping(pkg, "installed")
    end)

    pkg:on(
        "install:failed",
        ---@param handle InstallHandle
        function(handle)
            if handle.is_terminated then
                -- If installation was explicitly terminated - restore to "pristine" state
                mutate_state(function(state)
                    state.packages.states[pkg.name] = create_initial_package_state()
                end)
                mutate_package_grouping(pkg, pkg:is_installed() and "installed" or "uninstalled")
            else
                vim.schedule(function()
                    notify(("%s failed to install."):format(pkg.name), vim.log.levels.ERROR)
                end)
                mutate_package_grouping(pkg, "failed")
                mutate_state(function(state)
                    state.packages.states[pkg.name].has_failed = true
                end)
            end
        end
    )

    pkg:on("uninstall:success", function()
        if pkg:is_installing() then
            -- We don't care about uninstallations that occur during installation because it's expected behaviour and
            -- not constructive to surface to users.
            return
        end
        vim.schedule(function()
            notify(("%s was successfully uninstalled."):format(pkg.name))
        end)
        mutate_state(function(state)
            state.packages.states[pkg.name] = create_initial_package_state()
            state.packages.outdated_packages = _.filter(_.complement(_.equals(pkg)), state.packages.outdated_packages)
        end)
        mutate_package_grouping(pkg, "uninstalled")
    end)

    registered_packages[pkg] = true
end

local function update_registry_info()
    local registries = {}
    for source in registry.sources:iterate { include_uninstalled = true } do
        table.insert(registries, {
            name = source:get_display_name(),
            is_installed = source:is_installed(),
        })
    end
    mutate_state(function(state)
        state.info.registries = registries
    end)
end

---@param packages Package[]
local function setup_packages(packages)
    for _, pkg in ipairs(_.sort_by(_.prop "name", packages)) do
        setup_package(pkg)
    end
    mutate_state(function(state)
        state.packages.all = packages
    end)
end

registry:on("update:failed", function(errors)
    mutate_state(function(state)
        state.info.registry_update.percentage_complete = 0
        state.info.registry_update.in_progress = false
        state.info.registry_update.error = table.concat(errors, " - ")
    end)
end)

registry:on("update:success", function()
    setup_packages(registry.get_all_packages())
    update_registry_info()
    check_new_package_versions()

    -- Wait with resetting the state in order to keep displaying the update message
    vim.defer_fn(function()
        mutate_state(function(state)
            if state.info.registry_update.percentage_complete ~= 1 then
                -- New update was started already, don't reset state
                return
            end
            state.info.registry_update.in_progress = false
            state.info.registry_update.percentage_complete = 0
        end)
    end, 1000)
end)

registry:on("update:start", function()
    mutate_state(function(state)
        state.packages.outdated_packages = {}
        state.info.registry_update.error = nil
        state.info.registry_update.in_progress = true
        state.info.registry_update.percentage_complete = 0
    end)
end)

registry:on("update:progress", function(finished, all)
    mutate_state(function(state)
        state.info.registry_update.percentage_complete = #finished / #all
    end)
end)

update_registry_info()
if registry.sources:is_all_installed() then
    setup_packages(registry.get_all_packages())
end

if settings.current.ui.check_outdated_packages_on_open then
    registry.update()
else
    registry.refresh(function(success, updated_registries)
        if success and #updated_registries == 0 then
            setup_packages(registry.get_all_packages())
            update_registry_info()
        end
    end)
end

local border = settings.current.ui.border

if border == nil then
    if vim.fn.has "nvim-0.11" == 1 then
        border = vim.o.winborder
    else
        border = "none"
    end
end

window.init {
    effects = effects,
    border = border,
    winhighlight = {
        "NormalFloat:MasonNormal",
    },
}

return {
    window = window,
    set_view = function(view)
        set_view { payload = view }
    end,
    set_sticky_cursor = function(tag)
        window.set_sticky_cursor(tag)
    end,
}
