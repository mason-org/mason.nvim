local _ = require "mason-core.functional"

local M = {}

local uname = vim.loop.os_uname()

---@alias Platform
---| '"darwin_arm64"'
---| '"darwin_x64"'
---| '"linux_arm"'
---| '"linux_arm64"'
---| '"linux_arm64_gnu"'
---| '"linux_arm64_openbsd"'
---| '"linux_arm_gnu"'
---| '"linux_x64"'
---| '"linux_x64_gnu"'
---| '"linux_x64_openbsd"'
---| '"linux_x86"'
---| '"linux_x86_gnu"'
---| '"win_arm"'
---| '"win_arm64"'
---| '"win_x64"'
---| '"win_x86"'

local arch_aliases = {
    ["x86_64"] = "x64",
    ["i386"] = "x86",
    ["i686"] = "x86", -- x86 compat
    ["aarch64"] = "arm64",
    ["aarch64_be"] = "arm64",
    ["armv8b"] = "arm64", -- arm64 compat
    ["armv8l"] = "arm64", -- arm64 compat
}

M.arch = arch_aliases[uname.machine] or uname.machine
M.sysname = uname.sysname

M.is_headless = #vim.api.nvim_list_uis() == 0

local function system(args)
    if vim.fn.executable(args[1]) == 1 then
        local ok, output = pcall(vim.fn.system, args)
        if ok and (vim.v.shell_error == 0 or vim.v.shell_error == 1) then
            return true, output
        end
        return false, output
    end
    return false, args[1] .. " is not executable"
end

---@type fun(): ('"glibc"' | '"musl"')?
local get_libc = _.lazy(function()
    local getconf_ok, getconf_output = system { "getconf", "GNU_LIBC_VERSION" }
    if getconf_ok and getconf_output:find "glibc" then
        return "glibc"
    end
    local ldd_ok, ldd_output = system { "ldd", "--version" }
    if ldd_ok then
        if ldd_output:find "musl" then
            return "musl"
        elseif ldd_output:find "GLIBC" or ldd_output:find "glibc" or ldd_output:find "GNU" then
            return "glibc"
        end
    end
end)

-- Most of the code that calls into these functions executes outside of the main event loop, where API/fn functions are
-- disabled. We evaluate these immediately here to avoid issues with main loop synchronization.
M.cached_features = {
    ["win"] = vim.fn.has "win32",
    ["win32"] = vim.fn.has "win32",
    ["win64"] = vim.fn.has "win64",
    ["mac"] = vim.fn.has "mac",
    ["darwin"] = vim.fn.has "mac",
    ["unix"] = vim.fn.has "unix",
    ["linux"] = vim.fn.has "linux",
    ["nvim-0.11"] = vim.fn.has "nvim-0.11",
}

---@type fun(env: string): boolean
local check_env = _.memoize(_.cond {
    {
        _.equals "musl",
        function()
            return get_libc() == "musl"
        end,
    },
    {
        _.equals "gnu",
        function()
            return get_libc() == "glibc"
        end,
    },
    { _.equals "openbsd", _.always(uname.sysname == "OpenBSD") },
    { _.T, _.F },
})

---Table that allows for checking whether the provided targets apply to the current system.
---Each key is a target tuple consisting of at most 3 targets, in the following order:
--- 1) OS (e.g. linux, unix, darwin, win) - Mandatory
--- 2) Architecture (e.g. arm64, x64) - Optional
--- 3) Environment (e.g. gnu, musl, openbsd) - Optional
---Each target is separated by a "_" character, like so: "linux_x64_musl".
---@type table<string, boolean>
M.is = setmetatable({}, {
    __index = function(__, key)
        local os, arch, env = unpack(vim.split(key, "_", { plain = true }))
        if not M.cached_features[os] or M.cached_features[os] ~= 1 then
            return false
        end
        if arch and arch ~= M.arch then
            return false
        end
        if env and not check_env(env) then
            return false
        end
        return true
    end,
})

---@generic T
---@param platform_table table<Platform, T>
---@return T
local function get_by_platform(platform_table)
    if M.is.darwin then
        return platform_table.darwin or platform_table.mac or platform_table.unix
    elseif M.is.linux then
        return platform_table.linux or platform_table.unix
    elseif M.is.unix then
        return platform_table.unix
    elseif M.is.win then
        return platform_table.win
    else
        return nil
    end
end

function M.when(cases)
    local case = get_by_platform(cases)
    if case then
        return case()
    else
        error "Current platform is not supported."
    end
end

---@type async fun(): table
M.os_distribution = _.lazy(function()
    local parse_os_release = _.compose(_.from_pairs, _.map(_.split "="), _.split "\n")

    ---@param entries table<string, string>
    local function parse_ubuntu(entries)
        -- Parses the Ubuntu OS VERSION_ID into their version components, e.g. "18.04" -> {major=18, minor=04}
        local version_id = entries.VERSION_ID:gsub([["]], "")
        local version_parts = vim.split(version_id, "%.")
        local major = tonumber(version_parts[1])
        local minor = tonumber(version_parts[2])

        return {
            id = "ubuntu",
            version_id = version_id,
            version = { major = major, minor = minor },
        }
    end

    ---@param entries table<string, string>
    local function parse_centos(entries)
        -- Parses the CentOS VERSION_ID into a major version (the only thing available).
        local version_id = entries.VERSION_ID:gsub([["]], "")
        local major = tonumber(version_id)

        return {
            id = "centos",
            version_id = version_id,
            version = { major = major },
        }
    end

    ---Parses the provided contents of an /etc/*-release file and identifies the Linux distribution.
    local parse_linux_dist = _.cond {
        { _.prop_eq("ID", "ubuntu"), parse_ubuntu },
        { _.prop_eq("ID", [["centos"]]), parse_centos },
        { _.T, _.always { id = "linux-generic", version = {} } },
    }

    return M.when {
        linux = function()
            local spawn = require "mason-core.spawn"
            return spawn
                .bash({ "-c", "cat /etc/*-release" })
                :map_catching(_.compose(parse_linux_dist, parse_os_release, _.prop "stdout"))
                :recover(function()
                    return { id = "linux-generic", version = {} }
                end)
                :get_or_throw()
        end,
        darwin = function()
            return { id = "macOS", version = {} }
        end,
        win = function()
            return { id = "windows", version = {} }
        end,
    }
end)

---@type async fun(): Result<string>
M.get_homebrew_prefix = _.lazy(function()
    assert(M.is.darwin, "Can only locate Homebrew installation on Mac systems.")
    local spawn = require "mason-core.spawn"
    return spawn
        .brew({ "--prefix" })
        :map_catching(function(result)
            return vim.trim(result.stdout)
        end)
        :map_err(function()
            return "Failed to locate Homebrew installation."
        end)
end)

---@async
function M.get_node_version()
    local spawn = require "mason-core.spawn"

    return spawn.node({ "--version" }):map(function(result)
        -- Parses output such as "v16.3.1" into major, minor, patch
        local _, _, major, minor, patch = _.head(_.split("\n", result.stdout)):find "v(%d+)%.(%d+)%.(%d+)"
        return { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch) }
    end)
end

-- PATH separator
M.path_sep = M.is.win and ";" or ":"

return M
