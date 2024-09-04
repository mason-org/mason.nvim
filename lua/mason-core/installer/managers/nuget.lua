local Result = require "mason-core.result"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local platform = require "mason-core.platform"
local fetch = require "mason-core.fetch"

local M = {}

---@async
---@param package string
---@param version string
---@param repository_url string
---@nodiscard
function M.install(package, version, repository_url)
    log.fmt_debug("nuget: install %s %s", package, version)
    local ctx = installer.context()
    ctx.stdio_sink.stdout(("Installing nuget package %s@%s…\n"):format(package, version))
    local args = {
        "tool",
        "update",
        "--tool-path",
        ".",
        { "--version", version },
    }

    if repository_url then
        table.insert(args, { "--add-source",  repository_url })
    end

    table.insert(args, package)

    return ctx.spawn.dotnet(args)
end

---@alias NugetIndexResource { '@id': string, '@type': string}
---@alias NugetIndexFile { version: string, resources: NugetIndexResource[]}

---@async
---@param repository_url string
---@return Result # Result<NugetIndexFile>
function M.fetch_nuget_endpoint(repository_url)
    return fetch(repository_url, {
        headers = {
            Accept = "application/json",
        },
    }):map_catching(vim.json.decode)
end

---@param bin string
function M.bin_path(bin)
    return Result.pcall(platform.when, {
        unix = function()
            return bin
        end,
        win = function()
            return ("%s.exe"):format(bin)
        end,
    })
end

return M
