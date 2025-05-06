local health = vim.health or require "health"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local control = require "mason-core.async.control"
local platform = require "mason-core.platform"
local providers = require "mason-core.providers"
local registry = require "mason-registry"
local settings = require "mason.settings"
local spawn = require "mason-core.spawn"
local version = require "mason.version"

local Semaphore = control.Semaphore

local M = {}

local report_start = _.scheduler_wrap(health.start or health.report_start)
local report_ok = _.scheduler_wrap(health.ok or health.report_ok)
local report_warn = _.scheduler_wrap(health.warn or health.report_warn)
local report_error = _.scheduler_wrap(health.error or health.report_error)

local sem = Semaphore:new(5)

---@async
---@param opts {cmd:string, args:string[], name: string, use_stderr: boolean?, version_check: (fun(version: string): string?), relaxed: boolean?, advice: string[]}
local function check(opts)
    local get_first_non_empty_line = _.compose(_.head, _.filter(_.complement(_.matches "^%s*$")), _.split "\n")

    local permit = sem:acquire()

    Result.try(function(try)
        local result = try(spawn[opts.cmd] {
            opts.args,
            on_spawn = function(_, stdio)
                local stdin = stdio[1]
                -- some processes (`sh` for example) will endlessly read from stdin, so we close it immediately
                if not stdin:is_closing() then
                    stdin:close()
                end
            end,
        })

        ---@type string?
        local version = get_first_non_empty_line(opts.use_stderr and result.stderr or result.stdout)

        if opts.version_check then
            local ok, version_mismatch = pcall(opts.version_check, version)
            if ok and version_mismatch then
                local report = opts.relaxed and report_warn or report_error
                report(("%s: unsupported version `%s`"):format(opts.name, version), { version_mismatch })
                return
            elseif not ok then
                local report = opts.relaxed and report_warn or report_error
                report(("%s: failed to parse version"):format(opts.name), { ("Error: %s"):format(version_mismatch) })
                return
            end
        end

        report_ok(("%s: `%s`"):format(opts.name, version or "Ok"))
    end):on_failure(function(err)
        local report = opts.relaxed and report_warn or report_error
        report(("%s: not available"):format(opts.name), opts.advice or { tostring(err) })
    end)
    permit:forget()
end

local function check_registries()
    report_start "mason.nvim [Registries]"
    a.wait(registry.refresh)
    for source in registry.sources:iterate { include_uninstalled = true } do
        if source:is_installed() then
            report_ok(("Registry `%s` is installed."):format(source:get_display_name()))
        else
            report_error(
                ("Registry `%s` is not installed."):format(source:get_display_name()),
                { "Run :MasonUpdate to install." }
            )
        end
    end
end

local function check_neovim()
    if vim.fn.has "nvim-0.10.0" == 1 then
        report_ok "neovim version >= 0.10.0"
    else
        report_error("neovim version < 0.10.0", { "Upgrade Neovim." })
    end
end

---@async
local function check_core_utils()
    report_start "mason.nvim [Core utils]"

    check { name = "unzip", cmd = "unzip", args = { "-v" }, relaxed = true }

    -- wget is used interchangeably with curl, but with lower priority, so we mark wget as relaxed
    check { cmd = "wget", args = { "--version" }, name = "wget", relaxed = true }
    check { cmd = "curl", args = { "--version" }, name = "curl" }
    check {
        cmd = "gzip",
        args = { "--version" },
        name = "gzip",
        use_stderr = platform.is.mac, -- Apple gzip prints version string to stderr
        relaxed = platform.is.win,
    }

    a.scheduler()
    local tar = vim.fn.executable "gtar" == 1 and "gtar" or "tar"
    check { cmd = tar, args = { "--version" }, name = tar }

    if platform.is.unix then
        check { cmd = "bash", args = { "--version" }, name = "bash" }
        check { cmd = "sh", name = "sh" }
    end

    if platform.is.win then
        check {
            cmd = "pwsh",
            args = {
                "-NoProfile",
                "-Command",
                [[$PSVersionTable.PSVersion, $PSVersionTable.OS, $PSVersionTable.Platform -join " "]],
            },
            name = "pwsh",
        }
        check { cmd = "7z", args = { "--help" }, name = "7z", relaxed = true }
    end
end

local function check_thunk(opts)
    return function()
        check(opts)
    end
end

---@async
local function check_languages()
    report_start "mason.nvim [Languages]"

    a.wait_all {
        check_thunk {
            cmd = "go",
            args = { "version" },
            name = "Go",
            relaxed = true,
            version_check = function(version)
                -- Parses output such as "go version go1.17.3 darwin/arm64" into major, minor, patch components
                local _, _, major, minor = version:find "go(%d+)%.(%d+)"
                -- Due to https://go.dev/doc/go-get-install-deprecation
                if not (tonumber(major) >= 1 and tonumber(minor) >= 17) then
                    return "Go version must be >= 1.17."
                end
            end,
        },
        check_thunk {
            cmd = "cargo",
            args = { "--version" },
            name = "cargo",
            relaxed = true,
            version_check = function(version)
                local _, _, major, minor = version:find "(%d+)%.(%d+)%.(%d+)"
                if (tonumber(major) <= 1) and (tonumber(minor) < 60) then
                    return "Some cargo installations require Rust >= 1.60.0."
                end
            end,
        },
        check_thunk {
            cmd = "luarocks",
            args = { "--version" },
            name = "luarocks",
            relaxed = true,
            version_check = function(version)
                local _, _, major = version:find "(%d+)%.(%d+)%.(%d+)"
                if not (tonumber(major) >= 3) then
                    -- Because of usage of "--dev" flag
                    return "Luarocks version must be >= 3.0.0."
                end
            end,
        },
        check_thunk { cmd = "ruby", args = { "--version" }, name = "Ruby", relaxed = true },
        check_thunk { cmd = "gem", args = { "--version" }, name = "RubyGem", relaxed = true },
        check_thunk { cmd = "composer", args = { "--version" }, name = "Composer", relaxed = true },
        check_thunk { cmd = "php", args = { "--version" }, name = "PHP", relaxed = true },
        check_thunk {
            cmd = "npm",
            args = { "--version" },
            name = "npm",
            relaxed = true,
            version_check = function(version)
                -- Parses output such as "8.1.2" into major, minor, patch components
                local _, _, major = version:find "(%d+)%.(%d+)%.(%d+)"
                -- Based off of general observations of feature parity.
                -- In npm v7, peerDependencies are now automatically installed.
                if tonumber(major) < 7 then
                    return "npm version must be >= 7"
                end
            end,
        },
        check_thunk {
            cmd = "node",
            args = { "--version" },
            name = "node",
            relaxed = true,
            version_check = function(version)
                -- Parses output such as "v16.3.1" into major, minor, patch
                local _, _, major = version:find "v(%d+)%.(%d+)%.(%d+)"
                if tonumber(major) < 14 then
                    return "Node version must be >= 14"
                end
            end,
        },
        check_thunk { cmd = "javac", args = { "-version" }, name = "javac", relaxed = true },
        check_thunk { cmd = "java", args = { "-version" }, name = "java", use_stderr = true, relaxed = true },
        check_thunk { cmd = "julia", args = { "--version" }, name = "julia", relaxed = true },
        function()
            local python = platform.is.win and "python" or "python3"
            check { cmd = python, args = { "--version" }, name = "python", relaxed = true }
            check { cmd = python, args = { "-m", "pip", "--version" }, name = "pip", relaxed = true }
            check {
                cmd = python,
                args = { "-c", "import venv" },
                name = "python venv",
                relaxed = true,
                advice = {
                    [[On Debian/Ubuntu systems, you need to install the python3-venv package using the following command:

    apt-get install python3-venv]],
                },
            }
        end,
        function()
            a.scheduler()
            if vim.env.JAVA_HOME then
                check {
                    cmd = ("%s/bin/java"):format(vim.env.JAVA_HOME),
                    args = { "-version" },
                    name = "JAVA_HOME",
                    use_stderr = true,
                    relaxed = true,
                }
            end
        end,
    }
end

---@async
local function check_mason()
    providers.github
        .get_latest_release("mason-org/mason.nvim")
        :on_success(
            ---@param latest_release GitHubRelease
            function(latest_release)
                a.scheduler()
                if latest_release.tag_name ~= version.VERSION then
                    report_warn(("mason.nvim version %s"):format(version.VERSION), {
                        ("The latest version of mason.nvim is: %s"):format(latest_release.tag_name),
                    })
                else
                    report_ok(("mason.nvim version %s"):format(version.VERSION))
                end
            end
        )
        :on_failure(function()
            a.scheduler()
            report_ok(("mason.nvim version %s"):format(version.VERSION))
        end)

    report_ok(("PATH: %s"):format(settings.current.PATH))
    report_ok(("Providers: \n  %s"):format(_.join("\n  ", settings.current.providers)))
end

function M.check()
    report_start "mason.nvim"

    a.run_blocking(function()
        check_mason()
        check_neovim()
        check_registries()
        check_core_utils()
        check_languages()
        a.wait(vim.schedule)
    end)
end

return M
