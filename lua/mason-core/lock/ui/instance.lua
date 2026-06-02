local LockfileRestore = require "mason-core.lock.restore"
local Ui = require "mason-core.ui"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local display = require "mason-core.ui.display"
local lock = require "mason-core.lock"
local log = require "mason-core.log"
local notify = require "mason-core.notify"
local p = require "mason.ui.palette"
local registry = require "mason-registry"
local settings = require "mason.settings"

require "mason.ui.colors"

local window = display.new_view_only_win("mason.nvim lockfile restore", "mason")

---@class RestoreUiState
local INITIAL_STATE = {
    lockfile = {
        error = nil,
        exists = false,
        is_loaded = false,
    },
    restore = {
        ---@type string?
        expanded_log = nil,
        ---@type nil | '"PREPARING"' | '"RUNNING"' | '"FINISHED"'
        state = nil,
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
        handle_state = {},
        ---@type table<string, boolean>
        install_succeeded = {},
    },
    ---@type { package: string, from_version: string?, to_version: string?, is_installed: boolean }[]?
    preview = nil,
}

local mutate_state, get_state = window.state(INITIAL_STATE)

---@param state RestoreUiState
local function Header(state)
    return Ui.CascadingStyleNode({ "CENTERED" }, {
        Ui.HlTextNode {
            { p.header " mason.nvim | Lockfile " },
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

---@param state RestoreUiState
local function Failed(state)
    local failures = {}

    for pkg_name, info in pairs(state.restore.unavailable_packages) do
        table.insert(failures, {
            name = pkg_name,
            tail = info.error,
            log = { info.error },
        })
    end

    for pkg_name, success in pairs(state.restore.install_succeeded) do
        if not success then
            table.insert(failures, {
                name = pkg_name,
                log = state.restore.output[pkg_name].full,
                tail = state.restore.output[pkg_name].tail,
            })
        end
    end

    local failed_list = Ui.Node(_.map(function(pkg)
        local is_expanded = state.restore.expanded_log == pkg.name
        local log_tail = is_expanded and p.bold "▼ Displaying full log"
            or p.muted(("▶ # [%d/%d] %s"):format(#pkg.log, #pkg.log, pkg.tail))

        return Ui.Node {
            Ui.HlTextNode {
                {
                    p.error(settings.current.ui.icons.package_uninstalled),
                    p.none(" " .. pkg.name .. " "),
                },
            },
            Ui.CascadingStyleNode({ "INDENT" }, {
                Ui.HlTextNode(log_tail),
                Ui.Keybind(settings.current.ui.keymaps.toggle_package_install_log, "TOGGLE_INSTALL_LOG", pkg.name),
                Ui.When(is_expanded, function()
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(_.map(function(line)
                            return { p.muted(line) }
                        end, pkg.log)),
                    })
                end),
            }),
        }
    end, failures))

    return Ui.Node {
        Ui.HlTextNode(p.Bold "Failed"),
        Ui.Keybind("R", "RESET", nil, true),
        Ui.CascadingStyleNode({ "INDENT" }, {
            failed_list,
        }),
    }
end

window.view(
    ---@param state RestoreUiState
    function(state)
        return Ui.Node {
            Ui.Keybind("q", "CLOSE_WINDOW", nil, true),
            Ui.Keybind("<Esc>", "CLOSE_WINDOW", nil, true),
            Header(state),
            Ui.When(state.lockfile.is_loaded, function()
                if state.restore.state == "FINISHED" then
                    local has_failures = _.size(state.restore.unavailable_packages) > 0
                        or _.any(_.equals(false), vim.tbl_values(state.restore.install_succeeded))

                    local successful_packages = vim.tbl_filter(function(preview_item)
                        return state.restore.install_succeeded[preview_item.package]
                    end, state.preview)

                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode {
                            {
                                p.Bold(
                                    ("Restored %d/%d packages in lockfile."):format(
                                        #successful_packages,
                                        #state.preview
                                    )
                                ),
                            },
                            {
                                p.none "Press ",
                                p.highlight "R",
                                p.none " to reload lockfile.",
                            },
                        },
                        Ui.Keybind("R", "RESET", nil, true),
                        Ui.EmptyLine(),
                        Ui.When(has_failures, function()
                            return Ui.Node {
                                Failed(state),
                                Ui.EmptyLine(),
                            }
                        end),
                        Ui.HlTextNode(p.Bold "Installed"),
                        Ui.CascadingStyleNode(
                            { "INDENT" },
                            vim.tbl_map(function(preview)
                                local handle_state = state.restore.handle_state[preview.package]

                                return Ui.HlTextNode {

                                    {
                                        p.highlight(settings.current.ui.icons.package_installed),
                                        p.none(" " .. preview.package .. "@" .. preview.to_version),
                                    },
                                }
                            end, successful_packages)
                        ),
                    })
                elseif state.restore.state == "RUNNING" then
                    local unfinished_packages = vim.tbl_filter(function(preview)
                        return not state.restore.unavailable_packages[preview.package]
                            and state.restore.handle_state[preview.package] ~= "CLOSED"
                    end, state.preview)

                    local col_width = math.max(unpack(_.map(_.compose(_.length, _.prop "package"), state.preview)))

                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(p.Bold "Restoring packages…"),
                        Ui.EmptyLine(),
                        Ui.Table {
                            {
                                -- hack to ensure the table retains its original width as we're removing rows from the table
                                p.muted("Package" .. (" "):rep(col_width - #"Package")),
                                p.muted "current",
                                p.muted "target",
                                p.none "",
                            },
                            unpack(vim.tbl_map(function(preview)
                                local handle_state = state.restore.handle_state[preview.package]
                                local is_active = handle_state == "ACTIVE"

                                return {
                                    is_active and p.Bold(preview.package) or p.none(preview.package),
                                    p.muted(preview.from_version and truncate(preview.from_version, 16) or "-"),
                                    p.muted(truncate(preview.to_version, 16)),
                                    is_active and p.muted(state.restore.output[preview.package].tail) or p.none "",
                                }
                            end, unfinished_packages)),
                        },
                    })
                elseif state.restore.state == "PREPARING" then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(p.Bold "Retrieving package metadata…"),
                        Ui.EmptyLine(),
                        Ui.Table {
                            {
                                p.muted "Package",
                                p.muted "current",
                                p.muted "target",
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
                        Ui.When(#state.preview == 0, function()
                            return Ui.Node {
                                Ui.HlTextNode {
                                    {
                                        p.Bold "Lockfile is empty",
                                    },
                                },
                                Ui.EmptyLine(),
                                Ui.HlTextNode {
                                    {
                                        p.none "Press ",
                                        p.highlight "C",
                                        p.none " to populate the lockfile with the currently installed packages.",
                                    },
                                },
                                Ui.Keybind("C", "CREATE_LOCKFILE", nil, true),
                            }
                        end),
                        Ui.When(#state.preview > 0, function()
                            return Ui.Node {
                                Ui.HlTextNode {
                                    { p.Bold "Lockfile" },
                                    {
                                        p.none "Press ",
                                        p.highlight(settings.current.ui.keymaps.update_all_packages),
                                        p.none " to restore the following packages.",
                                    },
                                },
                                Ui.Keybind(
                                    settings.current.ui.keymaps.update_all_packages,
                                    "CONFIRM_RESTORE",
                                    nil,
                                    true
                                ),
                                Ui.EmptyLine(),
                                Ui.HlTextNode(p.muted "Package"),
                                Ui.Node(vim.tbl_map(function(preview)
                                    local is_same_version = preview.from_version == preview.to_version
                                    return Ui.Node {
                                        Ui.HlTextNode {
                                            {
                                                preview.is_installed and p.none(preview.package .. " ")
                                                    or p.Bold(preview.package .. " "),
                                                (preview.is_installed and not is_same_version)
                                                        and p.muted(truncate(preview.from_version .. " -> ", 16))
                                                    or p.none "",
                                                is_same_version and p.muted(truncate(preview.to_version, 16))
                                                    or p.highlight(truncate(preview.to_version, 16)),
                                            },
                                        },
                                        Ui.Keybind("X", "REMOVE_PACKAGE", preview.package),
                                    }
                                end, state.preview)),
                                Ui.EmptyLine(),
                                Ui.When(
                                    #state.preview > 0,
                                    Ui.HlTextNode {
                                        {
                                            p.none "Press ",
                                            p.highlight "X",
                                            p.none " to remove a package from the lockfile.",
                                        },
                                    }
                                ),
                            }
                        end),
                        Ui.EmptyLine(),
                        Ui.HlTextNode {
                            {
                                p.none "Press ",
                                p.highlight "R",
                                p.none " to reload lockfile.",
                            },
                        },
                        Ui.Keybind("R", "RESET", nil, true),
                    })
                else
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode(p.Bold "Loading…"),
                    })
                end
            end),
            Ui.When(not state.lockfile.is_loaded, function()
                if state.lockfile.error then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode {
                            {
                                p.Bold "Unable to parse lockfile",
                            },
                            {
                                p.error(state.lockfile.error),
                            },
                        },
                        Ui.EmptyLine(),
                        Ui.HlTextNode {
                            {
                                p.muted "Press ",
                                p.highlight "R",
                                p.muted " to retry.",
                            },
                        },
                        Ui.Keybind("R", "RESET", nil, true),
                    })
                elseif not state.lockfile.exists then
                    return Ui.CascadingStyleNode({ "INDENT" }, {
                        Ui.HlTextNode {
                            {
                                p.Bold "Lockfile does not exist",
                            },
                        },
                        Ui.EmptyLine(),
                        Ui.HlTextNode {
                            {
                                p.none "Press ",
                                p.highlight "C",
                                p.none " to create a new lockfile at ",
                                p.highlight(settings.current.lockfile.path),
                                p.none ".",
                            },
                        },
                        Ui.Keybind("C", "CREATE_LOCKFILE", nil, true),
                        Ui.EmptyLine(),
                        Ui.HlTextNode {
                            { p.muted "This will create a new lockfile based on your currently installed packages." },
                        },
                    })
                else
                    -- TODO loading state. Not needed for now because parsing lockfile is synchronous.
                    return Ui.Node {}
                end
            end),
        }
    end
)

---@param cb? fun()
local function init(cb)
    mutate_state, get_state = window.reset_state(INITIAL_STATE)

    local ok, lockfile = pcall(lock.get_lockfile)
    if not ok then
        mutate_state(function(state)
            state.lockfile.error = tostring(lockfile)
        end)
        return
    end
    if lockfile == nil then
        mutate_state(function(state)
            state.lockfile.exists = false
        end)
        return
    end
    mutate_state(function(state)
        state.lockfile.is_loaded = true
        state.lockfile.exists = true
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
        if cb then
            cb()
        end
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
            state.restore.handle_state[handle.package.name] = handle_state
        end)
    end

    handle_state_change(handle.state)

    handle:on("state:change", handle_state_change)
    handle:on("stderr", handle_output)
    handle:on("stdout", handle_output)
end

local function restore()
    mutate_state(function(state)
        state.restore.state = "PREPARING"
    end)
    ---@type LockfileRestore
    local restore = assert(get_state().restore.instance, "restore instance is nil")
    a.run(function()
        local group = restore:prepare()
        mutate_state(function(state)
            state.restore.available_packages = group.packages
            state.restore.unavailable_packages = group.unavailable_packages
            state.restore.state = "RUNNING"
        end)
        group:install {
            on_handle = setup_handle,
            on_completion = function(pkg, success)
                mutate_state(function(state)
                    state.restore.install_succeeded[pkg.name] = success
                end)
            end,
        }
    end, function(success, err)
        vim.schedule(function()
            restore:cleanup()
        end)
        if success then
            mutate_state(function(state)
                state.restore.state = "FINISHED"
            end)
        end
        log.error("Lockfile restore errored with unexpected error", err)
    end)
end

local function toggle_install_log(event)
    mutate_state(function(state)
        if state.restore.expanded_log == event.payload then
            state.restore.expanded_log = nil
        else
            state.restore.expanded_log = event.payload
        end
    end)
end

local function create_lockfile()
    lock.create_lockfile()
    notify(("Successfully created lockfile at %s."):format(lock.get_lockfile_path()))
    init()
end

local function remove_package(event)
    local pkg_name = event.payload
    local lockfile = lock.get_lockfile()
    if not lockfile then
        return
    end
    lockfile.body[pkg_name] = nil
    lock.write_lockfile(lockfile)
    init()
end

window.init {
    effects = {
        CLOSE_WINDOW = window.close,
        RESET = function()
            init()
        end,
        CREATE_LOCKFILE = create_lockfile,
        CONFIRM_RESTORE = restore,
        TOGGLE_INSTALL_LOG = toggle_install_log,
        REMOVE_PACKAGE = remove_package,
    },
    winhighlight = {
        "NormalFloat:MasonNormal",
    },
}

local has_initialized = false
return {
    init = init,
    close = window.close,
    restore = function()
        init(restore)
    end,
    open = function()
        if not has_initialized then
            init()
            has_initialized = true
        end
        window.open()
    end,
}
