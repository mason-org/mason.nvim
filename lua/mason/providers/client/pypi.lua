local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local fetch = require "mason-core.fetch"
local fs = require "mason-core.fs"
local platform = require "mason-core.platform"
local spawn = require "mason-core.spawn"

---@param args SpawnArgs
local function python(args)
    a.scheduler()
    local py_exec = platform.is.win and "python" or "python3"
    -- run in tmpdir in case pip inadvertently produces some output
    args.cwd = vim.fn.tempname()
    fs.async.mkdir(args.cwd)
    return spawn[py_exec](args)
end

---@async
---@param pkg string
local function get_all_versions(pkg)
    -- https://stackoverflow.com/a/26664162
    return python({
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "--use-deprecated=legacy-resolver", -- for pip >= 20.3
            ("%s=="):format(pkg), -- invalid version specifier to trigger the wanted error message
        })
        :recover(_.prop "stderr")
        :map(_.compose(_.split ", ", _.head, _.match "%(from versions: (.+)%)"))
        :map(_.reverse)
end

---@param pkg string
local function synthesize_pkg(pkg)
    ---@param version Optional
    return function(version)
        return version
            :map(function(v)
                return { name = pkg, version = v }
            end)
            :ok_or "Unable to find latest version."
    end
end

---@type PyPiProvider
return {
    get_latest_version = function(pkg)
        return get_all_versions(pkg):map(_.compose(Optional.of_nilable, _.last)):and_then(synthesize_pkg(pkg))
    end,
    get_all_versions = get_all_versions,
    get_supported_python_versions = function(pkg, version)
        return fetch(("https://pypi.org/pypi/%s/%s/json"):format(pkg, version))
            :map_catching(vim.json.decode)
            :map(_.path { "info", "requires_python" })
            :and_then(function(requires_python)
                if type(requires_python) ~= "string" or requires_python == "" then
                    return Result.failure "Package does not specify supported Python versions."
                else
                    return Result.success(requires_python)
                end
            end)
    end,
}
