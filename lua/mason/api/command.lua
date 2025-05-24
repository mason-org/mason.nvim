local _ = require "mason-core.functional"
local platform = require "mason-core.platform"

local function Mason()
    require("mason.ui").open()
end

vim.api.nvim_create_user_command("Mason", Mason, {
    desc = "Opens mason's UI window.",
    nargs = 0,
})

local get_valid_packages = _.filter_map(function(pkg_specifier)
    local Optional = require "mason-core.optional"
    local notify = require "mason-core.notify"
    local Package = require "mason-core.package"
    local registry = require "mason-registry"
    local package_name, version = Package.Parse(pkg_specifier)
    local ok, pkg = pcall(registry.get_package, package_name)
    if ok and pkg then
        return Optional.of { pkg = pkg, version = version }
    else
        notify(("%q is not a valid package."):format(pkg_specifier), vim.log.levels.ERROR)
        return Optional.empty()
    end
end)

---@param package_specifiers string[]
---@param opts? table<string, string | boolean>
local function MasonInstall(package_specifiers, opts)
    opts = opts or {}
    local a = require "mason-core.async"
    local registry = require "mason-registry"
    local Optional = require "mason-core.optional"

    local install_packages = _.filter_map(function(target)
        if target.pkg:is_installing() then
            return Optional.empty()
        else
            return Optional.of(target.pkg:install {
                version = target.version,
                debug = opts.debug,
                force = opts.force,
                strict = opts.strict,
                target = opts.target,
            })
        end
    end)

    if platform.is_headless then
        registry.refresh()
        local valid_packages = get_valid_packages(package_specifiers)
        if #valid_packages ~= #package_specifiers then
            -- When executing in headless mode we don't allow any of the provided packages to be invalid.
            -- This is to avoid things like scripts silently not erroring even if they've provided one or more invalid packages.
            return vim.cmd [[1cq]]
        end
        a.run_blocking(function()
            local results = {
                a.wait_all(_.map(
                    ---@param target { pkg: Package, version: string? }
                    function(target)
                        return function()
                            if target.pkg:is_installing() then
                                return
                            end
                            return a.wait(function(resolve)
                                local handle = target.pkg:install({
                                    version = target.version,
                                    debug = opts.debug,
                                    force = opts.force,
                                    strict = opts.strict,
                                    target = opts.target,
                                }, function(success, err)
                                    resolve { success, target.pkg, err }
                                end)
                                if not opts.quiet then
                                    handle
                                        :on("stdout", vim.schedule_wrap(vim.api.nvim_out_write))
                                        :on("stderr", vim.schedule_wrap(vim.api.nvim_err_write))
                                end
                            end)
                        end
                    end,
                    valid_packages
                )),
            }
            a.scheduler()

            local is_failure = _.compose(_.equals(false), _.head)
            if _.any(is_failure, results) then
                local failures = _.filter(is_failure, results)
                local failed_packages = _.map(_.nth(2), failures)
                for _, failure in ipairs(failures) do
                    local _, pkg, error = unpack(failure)
                    vim.api.nvim_err_writeln(("Package %s failed with the following error:"):format(pkg.name))
                    vim.api.nvim_err_writeln(tostring(error))
                end
                vim.cmd [[1cq]]
            end
        end)
    else
        local ui = require "mason.ui"
        ui.open()
        -- Important: We start installation of packages _after_ opening the UI. This gives the UI components a chance to
        -- register the necessary event handlers in time, avoiding desynced state.
        registry.refresh(function()
            local valid_packages = get_valid_packages(package_specifiers)
            install_packages(valid_packages)
            vim.schedule(function()
                ui.set_sticky_cursor "installing-section"
            end)
        end)
    end
end

local parse_opts = _.compose(
    _.from_pairs,
    _.map(_.compose(function(arg)
        if #arg == 2 then
            return arg
        else
            return { arg[1], true }
        end
    end, _.split "=", _.gsub("^%-%-", "")))
)

---@param args string[]
---@return table<string, true|string> opts, string[] args
local function parse_args(args)
    local opts_list, args = unpack(_.partition(_.starts_with "--", args))
    local opts = parse_opts(opts_list)
    return opts, args
end

vim.api.nvim_create_user_command("MasonInstall", function(opts)
    local command_opts, packages = parse_args(opts.fargs)
    MasonInstall(packages, command_opts)
end, {
    desc = "Install one or more packages.",
    nargs = "+",
    ---@param arg_lead string
    complete = function(arg_lead)
        local registry = require "mason-registry"
        registry.refresh()
        if _.starts_with("--", arg_lead) then
            return _.filter(_.starts_with(arg_lead), {
                "--debug",
                "--force",
                "--strict",
                "--target=",
            })
        elseif _.matches("^.+@", arg_lead) then
            local pkg_name, version = unpack(_.match("^(.+)@(.*)", arg_lead))
            local ok, pkg = pcall(registry.get_package, pkg_name)
            if not ok or not pkg then
                return {}
            end
            local a = require "mason-core.async"
            return a.run_blocking(function()
                return a.wait_first {
                    function()
                        return pkg:get_all_versions()
                            :map(
                                _.compose(
                                    _.map(_.concat(arg_lead)),
                                    _.map(_.strip_prefix(version)),
                                    _.filter(_.starts_with(version))
                                )
                            )
                            :get_or_else {}
                    end,
                    function()
                        a.sleep(4000)
                        return {}
                    end,
                }
            end)
        end

        local all_pkg_names = registry.get_all_package_names()
        return _.sort_by(_.identity, _.filter(_.starts_with(arg_lead), all_pkg_names))
    end,
})

---@param package_names string[]
local function MasonUninstall(package_names)
    local valid_packages = get_valid_packages(package_names)
    if #valid_packages > 0 then
        _.each(function(target)
            target.pkg:uninstall()
        end, valid_packages)
        require("mason.ui").open()
    end
end

vim.api.nvim_create_user_command("MasonUninstall", function(opts)
    MasonUninstall(opts.fargs)
end, {
    desc = "Uninstall one or more packages.",
    nargs = "+",
    ---@param arg_lead string
    complete = function(arg_lead)
        local registry = require "mason-registry"
        return _.sort_by(_.identity, _.filter(_.starts_with(arg_lead), registry.get_installed_package_names()))
    end,
})

local function MasonUninstallAll()
    local registry = require "mason-registry"
    require("mason.ui").open()
    for _, pkg in ipairs(registry.get_installed_packages()) do
        pkg:uninstall()
    end
end

vim.api.nvim_create_user_command("MasonUninstallAll", MasonUninstallAll, {
    desc = "Uninstall all packages.",
})

local function MasonUpdate()
    local notify = require "mason-core.notify"
    local registry = require "mason-registry"
    notify "Updating registries…"

    ---@param success boolean
    ---@param updated_registries RegistrySource[]
    local function handle_result(success, updated_registries)
        if success then
            local count = #updated_registries
            notify(("Successfully updated %d %s."):format(count, count == 1 and "registry" or "registries"))
        else
            notify(("Failed to update registries: %s"):format(updated_registries), vim.log.levels.ERROR)
        end
    end

    if platform.is_headless then
        local a = require "mason-core.async"
        a.run_blocking(function()
            local success, updated_registries = a.wait(registry.update)
            a.scheduler()
            handle_result(success, updated_registries)
        end)
    else
        registry.update(_.scheduler_wrap(handle_result))
    end
end

vim.api.nvim_create_user_command("MasonUpdate", MasonUpdate, {
    desc = "Update Mason registries.",
})

local function MasonLog()
    local log = require "mason-core.log"
    vim.cmd(([[tabnew %s]]):format(log.outfile))
end

vim.api.nvim_create_user_command("MasonLog", MasonLog, {
    desc = "Opens the mason.nvim log.",
})

return {
    Mason = Mason,
    MasonInstall = MasonInstall,
    MasonUninstall = MasonUninstall,
    MasonUninstallAll = MasonUninstallAll,
    MasonUpdate = MasonUpdate,
    MasonLog = MasonLog,
}
