local LockfileRestore = require "mason-core.lock.restore"
local Ui = require "mason-core.ui"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local display = require "mason-core.ui.display"
local lock = require "mason-core.lock"
local p = require "mason.ui.palette"
local registry = require "mason-registry"
local settings = require "mason.settings"

require "mason.ui.colors"

local window = display.new_view_only_win("mason.nvim lockfile restore", "mason")

---@class RestoreUiState
local INITIAL_STATE = {
    lockfile = {
        error = nil,
        is_loaded = false,
    },
    restore = {
        is_preparing = false,
        is_running = false,
        ---@type LockfileRestore?
        instance = nil,
        error = nil,
        ---@type table<string, { error: string, metadata: LockfilePackage }>
        unavailable_packages = {},
        ---@type table<Package, LockfilePackage>
        available_packages = {},
        ---@type table<string, { tail: string, full: string[] }>
        output = {},
        ---@type table<string, InstallHandleState>
        install_state = {},
    },
    ---@type { package: string, from_version: string?, to_version: string?, is_installed: boolean }[]?
    preview = nil,
}

local mutate_state, get_state = window.state(INITIAL_STATE)

---@param state RestoreUiState
local function Header(state)
    return Ui.CascadingStyleNode({ "CENTERED" }, {
        Ui.HlTextNode {
            { p.header " mason.nvim | Lockfile restore " },
        },
        Ui.EmptyLine(),
        Ui.EmptyLine(),
    })
end

local function truncate(str, max_len)
    if #str <= max_len then
        return str
    else
        return str:sub(1, max_len - 3) .. "..."
    end
end

window.view(
    ---@param state RestoreUiState
    function(state)
        return Ui.Node {
            Ui.Keybind("q", "CLOSE_WINDOW", nil, true),
            Ui.Keybind("<Esc>", "CLOSE_WINDOW", nil, true),
            Header(state),
            Ui.When(state.lockfile.is_loaded, function()
                if state.restore.is_running then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(p.Bold "Restoring packages…"),
                        Ui.EmptyLine(),
                        Ui.EmptyLine(),
                        Ui.Table {
                            {
                                p.Comment "Package",
                                p.Comment "From",
                                p.Comment "To",
                                p.none "",
                            },
                            unpack(vim.tbl_map(function(preview)
                                local is_same_version = preview.from_version == preview.to_version
                                local unavailable = state.restore.unavailable_packages[preview.package]
                                local handle_state = state.restore.install_state[preview.package]
                                local is_active = handle_state == "ACTIVE"
                                local package_name = handle_state == "ACTIVE" and p.Bold or p.Comment

                                return {
                                    is_active and p.Bold(preview.package) or p.none(preview.package),
                                    p.muted(preview.from_version and truncate(preview.from_version, 16) or "-"),
                                    p.muted(truncate(preview.to_version, 16)),
                                    unavailable and p.Error(unavailable.error)
                                        or (
                                            is_active and p.Comment(state.restore.output[preview.package].tail)
                                            or p.none ""
                                        ),
                                }
                            end, state.preview)),
                        },
                    })
                elseif state.restore.is_preparing then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(p.Bold "Retrieving package metadata…"),
                        Ui.EmptyLine(),
                        Ui.EmptyLine(),
                        Ui.Table {
                            {
                                p.Comment "Package",
                                p.Comment "From",
                                p.Comment "To",
                            },
                            unpack(vim.tbl_map(function(preview)
                                local is_same_version = preview.from_version == preview.to_version
                                return {
                                    p.muted(preview.package),
                                    p.muted(preview.from_version and truncate(preview.from_version, 16) or "-"),
                                    p.muted(truncate(preview.to_version, 16)),
                                }
                            end, state.preview)),
                        },
                    })
                elseif state.preview then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.Keybind(settings.current.ui.keymaps.update_all_packages, "CONFIRM_RESTORE", nil, true),
                        Ui.HlTextNode {
                            { p.Bold "Preview" },
                            {
                                p.none "Press ",
                                p.highlight(settings.current.ui.keymaps.update_all_packages),
                                p.none " to restore the following packages",
                            },
                        },
                        Ui.EmptyLine(),
                        Ui.Table {
                            {
                                p.Comment "Package",
                                p.Comment "From",
                                p.Comment "To",
                            },
                            unpack(vim.tbl_map(function(preview)
                                local is_same_version = preview.from_version == preview.to_version
                                return {
                                    preview.is_installed and p.none(preview.package) or p.Bold(preview.package),
                                    p.muted(preview.from_version and truncate(preview.from_version, 16) or "-"),
                                    is_same_version and p.muted(truncate(preview.to_version, 16))
                                        or p.highlight(truncate(preview.to_version, 16)),
                                }
                            end, state.preview)),
                        },
                    })
                else
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(p.Bold "Loading..."),
                    })
                end
            end),
            Ui.When(not state.lockfile.is_loaded, function()
                if state.lockfile.error then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.Keybind("R", "RESET", nil, true),
                        Ui.HlTextNode {
                            {
                                p.Bold "Unable to restore from lockfile",
                            },
                            {
                                p.error(state.lockfile.error),
                            },
                        },
                        Ui.EmptyLine(),
                        Ui.HlTextNode {
                            {
                                p.Comment "Press R to retry",
                            },
                        },
                    })
                else
                    -- TODO loading message
                end
            end),
        }
    end
)

local function init()
    mutate_state, get_state = window.reset_state(INITIAL_STATE)

    local ok, lockfile = pcall(lock.get_lockfile)
    if not ok then
        mutate_state(function(state)
            state.lockfile.error = tostring(lockfile)
        end)
        return
    end
    mutate_state(function(state)
        state.lockfile.is_loaded = true
    end)
    local restore = LockfileRestore:new(lockfile)

    registry.refresh(function()
        mutate_state(function(state)
            state.restore.instance = restore
            state.preview = {}
            for pkg_name, metadata in pairs(restore:get_packages()) do
                local from_version
                local is_installed = false
                local ok, pkg = pcall(registry.get_package, pkg_name)
                if ok and pkg:is_installed() then
                    from_version = pkg:get_installed_version()
                    is_installed = true
                end
                state.preview[#state.preview + 1] = {
                    package = pkg_name,
                    to_version = metadata.version,
                    from_version = from_version,
                    is_installed = is_installed,
                }
            end
            table.sort(state.preview, function(a, b)
                return a.package < b.package
            end)
        end)
    end)
end

---@param handle InstallHandle
local function setup_handle(handle)
    mutate_state(function(state)
        state.restore.output[handle.package.name] = { tail = "", full = { "" } }
    end)

    ---@param chunk string
    local function handle_output(chunk)
        mutate_state(function(state)
            local output = state.restore.output[handle.package.name]
            local lines = vim.split(chunk, "\n")
            for i = 1, #lines do
                local line = lines[i]
                if i == 1 then
                    output.full[#output.full] = output.full[#output.full] .. line
                else
                    output.full[#output.full + 1] = line
                end
                if not line:match "^%s*$" then
                    output.tail = line:gsub("^%s+", "")
                end
            end
        end)
    end

    local function handle_state_change(handle_state)
        mutate_state(function(state)
            state.restore.install_state[handle.package.name] = handle_state
        end)
    end

    handle_state_change(handle.state)

    handle:on("state:change", handle_state_change)
    handle:on("stderr", handle_output)
    handle:on("stdout", handle_output)
end

local function restore()
    mutate_state(function(state)
        state.restore.is_preparing = true
    end)
    ---@type LockfileRestore
    local restore = assert(get_state().restore.instance, "restore instance is nil")
    a.run(function()
        local group = restore:prepare()
        mutate_state(function(state)
            state.restore.available_packages = group.packages
            state.restore.unavailable_packages = group.unavailable_packages
            state.restore.is_preparing = false
            state.restore.is_running = true
        end)
        group:install {
            on_handle = setup_handle,
        }
    end, function(success, error)
        restore:cleanup()
        if not success then
            mutate_state(function(state)
                state.restore.error = tostring(error)
            end)
        end
    end)
end

window.init {
    effects = {
        CLOSE_WINDOW = window.close,
        RESET = init,
        CONFIRM_RESTORE = restore,
    },
    winhighlight = {
        "NormalFloat:MasonNormal",
    },
}

init()
window.open()

return {
    ---@param install_group LockfileInstallGroup
    init = init,
    open = function()
        window.open()
    end,
}
