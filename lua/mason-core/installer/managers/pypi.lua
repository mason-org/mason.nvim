local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local path = require "mason-core.path"
local pep440 = require "mason-core.pep440"
local platform = require "mason-core.platform"
local providers = require "mason-core.providers"
local semver = require "mason-core.semver"
local spawn = require "mason-core.spawn"

local M = {}

local VENV_DIR = "venv"

function M.venv_path(dir)
    return path.concat {
        dir,
        VENV_DIR,
        platform.is.win and "Scripts" or "bin",
    }
end

---@async
---@param candidates string[]
local function resolve_python3(candidates)
    local is_executable = _.compose(_.equals(1), vim.fn.executable)
    a.scheduler()
    local available_candidates = _.filter(is_executable, candidates)
    for __, candidate in ipairs(available_candidates) do
        ---@type string
        local version_output = spawn[candidate]({ "--version" }):map(_.prop "stdout"):get_or_else ""
        local ok, version = pcall(semver.new, version_output:match "Python (3%.%d+.%d+)")
        if ok then
            return { executable = candidate, version = version }
        end
    end
    return nil
end

---@param version string
---@param specifiers string
local function pep440_check_version(version, specifiers)
    -- The version check only implements a subset of the PEP440 specification and may error with certain inputs.
    local ok, result = pcall(pep440.check_version, version, specifiers)
    if not ok then
        log.fmt_warn(
            "Failed to check PEP440 version compatibility for version %s with specifiers %s: %s",
            version,
            specifiers,
            result
        )
        return false
    end
    return result
end

---@param supported_python_versions string
local function get_versioned_candidates(supported_python_versions)
    return _.filter_map(function(pair)
        local version, executable = unpack(pair)
        if not pep440_check_version(tostring(version), supported_python_versions) then
            return Optional.empty()
        end
        return Optional.of(executable)
    end, {
        { semver.new "3.12.0", "python3.12" },
        { semver.new "3.11.0", "python3.11" },
        { semver.new "3.10.0", "python3.10" },
        { semver.new "3.9.0", "python3.9" },
        { semver.new "3.8.0", "python3.8" },
        { semver.new "3.7.0", "python3.7" },
        { semver.new "3.6.0", "python3.6" },
    })
end

---@async
---@param pkg { name: string, version: string }
local function create_venv(pkg)
    local ctx = installer.context()
    ---@type string?
    local supported_python_versions = providers.pypi.get_supported_python_versions(pkg.name, pkg.version):get_or_nil()

    -- 1. Resolve stock python3 installation.
    local stock_candidates = platform.is.win and { "python", "python3" } or { "python3", "python" }
    local stock_target = resolve_python3(stock_candidates)
    if stock_target then
        log.fmt_debug("Resolved stock python3 installation version %s", stock_target.version)
    end

    -- 2. Resolve suitable versioned python3 installation (python3.12, python3.11, etc.).
    local versioned_candidates = {}
    if supported_python_versions ~= nil then
        if stock_target and not pep440_check_version(tostring(stock_target.version), supported_python_versions) then
            log.fmt_debug("Finding versioned candidates for %s", supported_python_versions)
            versioned_candidates = get_versioned_candidates(supported_python_versions)
        end
    end
    local target = resolve_python3(versioned_candidates) or stock_target

    if not target then
        return Result.failure(
            ("Unable to find python3 installation in PATH. Tried the following candidates: %s."):format(
                _.join(", ", _.concat(stock_candidates, versioned_candidates))
            )
        )
    end

    -- 3. If a versioned python3 installation was not found, warn the user if the stock python3 installation is outside
    -- the supported version range.
    if
        target == stock_target
        and supported_python_versions ~= nil
        and not pep440_check_version(tostring(target.version), supported_python_versions)
    then
        if ctx.opts.force then
            ctx.stdio_sink:stderr(
                ("Warning: The resolved python3 version %s is not compatible with the required Python versions: %s.\n"):format(
                    target.version,
                    supported_python_versions
                )
            )
        else
            ctx.stdio_sink:stderr "Run with :MasonInstall --force to bypass this version validation.\n"
            return Result.failure(
                ("Failed to find a python3 installation in PATH that meets the required versions (%s). Found version: %s."):format(
                    supported_python_versions,
                    target.version
                )
            )
        end
    end

    log.fmt_debug("Found python3 installation version=%s, executable=%s", target.version, target.executable)
    ctx.stdio_sink:stdout "Creating virtual environment…\n"
    return ctx.spawn[target.executable] { "-m", "venv", "--system-site-packages", VENV_DIR }
end

---@param ctx InstallContext
---@param executable string
local function find_venv_executable(ctx, executable)
    local candidates = _.filter(_.identity, {
        platform.is.unix and path.concat { VENV_DIR, "bin", executable },
        -- MSYS2
        platform.is.win and path.concat { VENV_DIR, "bin", ("%s.exe"):format(executable) },
        -- Stock Windows
        platform.is.win and path.concat { VENV_DIR, "Scripts", ("%s.exe"):format(executable) },
    })

    for _, candidate in ipairs(candidates) do
        if ctx.fs:file_exists(candidate) then
            return Result.success(candidate)
        end
    end
    return Result.failure(("Failed to find executable %q in Python virtual environment."):format(executable))
end

---@async
---@param args SpawnArgs
local function venv_python(args)
    local ctx = installer.context()
    return find_venv_executable(ctx, "python"):and_then(function(python_path)
        return ctx.spawn[path.concat { ctx.cwd:get(), python_path }](args)
    end)
end

---@async
---@param pkgs string[]
---@param extra_args? string[]
local function pip_install(pkgs, extra_args)
    return venv_python {
        "-m",
        "pip",
        "--disable-pip-version-check",
        "install",
        "--no-user",
        "--ignore-installed",
        extra_args or vim.NIL,
        pkgs,
    }
end

---@async
---@param opts { package: { name: string, version: string }, upgrade_pip: boolean, install_extra_args?: string[] }
function M.init(opts)
    return Result.try(function(try)
        log.fmt_debug("pypi: init", opts)
        local ctx = installer.context()

        -- pip3 will hardcode the full path to venv executables, so we need to promote cwd to make sure pip uses the final destination path.
        ctx:promote_cwd()
        try(create_venv(opts.package))

        if opts.upgrade_pip then
            ctx.stdio_sink:stdout "Upgrading pip inside the virtual environment…\n"
            try(pip_install({ "pip" }, opts.install_extra_args))
        end
    end)
end

---@async
---@param pkg string
---@param version string
---@param opts? { extra?: string, extra_packages?: string[], install_extra_args?: string[] }
function M.install(pkg, version, opts)
    opts = opts or {}
    log.fmt_debug("pypi: install %s %s %s", pkg, version, opts or "")
    local ctx = installer.context()
    ctx.stdio_sink:stdout(("Installing pip package %s@%s…\n"):format(pkg, version))
    return pip_install({
        opts.extra and ("%s[%s]==%s"):format(pkg, opts.extra, version) or ("%s==%s"):format(pkg, version),
        opts.extra_packages or vim.NIL,
    }, opts.install_extra_args)
end

---@async
---@param pkg string
function M.uninstall(pkg)
    log.fmt_debug("pypi: uninstall %s", pkg)
    return venv_python {
        "-m",
        "pip",
        "uninstall",
        "-y",
        pkg,
    }
end

---@param executable string
function M.bin_path(executable)
    local ctx = installer.context()
    return find_venv_executable(ctx, executable)
end

return M
