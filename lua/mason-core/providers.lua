local Result = require "mason-core.result"
local log = require "mason-core.log"
local settings = require "mason.settings"

---@alias GitHubRelease { tag_name: string, prerelease: boolean, draft: boolean, assets: table[] }
---@alias GitHubTag { name: string }

---@class GitHubProvider
---@field get_latest_release? async fun(repo: string): Result # Result<GitHubRelease>
---@field get_all_release_versions? async fun(repo: string): Result # Result<string[]>
---@field get_latest_tag? async fun(repo: string): Result # Result<GitHubTag>
---@field get_all_tags? async fun(repo: string): Result # Result<string[]>

---@alias NpmPackage { name: string, version: string }

---@class NpmProvider
---@field get_latest_version? async fun(pkg: string): Result # Result<NpmPackage>
---@field get_all_versions? async fun(pkg: string): Result # Result<string[]>

---@alias PyPiPackage { name: string, version: string }

---@class PyPiProvider
---@field get_latest_version? async fun(pkg: string): Result # Result<PyPiPackage>
---@field get_all_versions? async fun(pkg: string): Result # Result<string[]> # Sorting should not be relied upon due to "proprietary" sorting algo in pip that is difficult to replicate in mason-registry-api.
---@field get_supported_python_versions? async fun(pkg: string, version: string): Result # Result<string> # Returns a version specifier as provided by the PyPI API (see PEP440).

---@alias RubyGem { name: string, version: string }

---@class RubyGemsProvider
---@field get_latest_version? async fun(gem: string): Result # Result<RubyGem>
---@field get_all_versions? async fun(gem: string): Result # Result<string[]>

---@alias PackagistPackage { name: string, version: string }

---@class PackagistProvider
---@field get_latest_version? async fun(pkg: string): Result # Result<PackagistPackage>
---@field get_all_versions? async fun(pkg: string): Result # Result<string[]>

---@alias Crate { name: string, version: string }

---@class CratesProvider
---@field get_latest_version? async fun(crate: string): Result # Result<Crate>
---@field get_all_versions? async fun(crate: string): Result # Result<string[]>

---@class GolangProvider
---@field get_all_versions? async fun(pkg: string): Result # Result<string[]>

---@class OpenVSXProvider
---@field get_latest_version? async fun(namespace: string, extension: string): Result # Result<Crate>
---@field get_all_versions? async fun(namespace: string, extension: string): Result # Result<string[]>

---@class Provider
---@field github?     GitHubProvider
---@field npm?        NpmProvider
---@field pypi?       PyPiProvider
---@field rubygems?   RubyGemsProvider
---@field packagist?  PackagistProvider
---@field crates?     CratesProvider
---@field golang?     GolangProvider
---@field openvsx?    OpenVSXProvider

local function service_mt(service)
    return setmetatable({}, {
        __index = function(_, method)
            return function(...)
                if #settings.current.providers < 1 then
                    log.error "No providers configured."
                    return Result.failure "1 or more providers are required."
                end
                for _, provider_module in ipairs(settings.current.providers) do
                    local ok, provider = pcall(require, provider_module)
                    if ok and provider then
                        local impl = provider[service] and provider[service][method]
                        if impl then
                            ---@type boolean, Result
                            local ok, result = pcall(impl, ...)
                            if ok and result:is_success() then
                                return result
                            else
                                if getmetatable(result) == Result then
                                    log.fmt_error("Provider %s %s failed: %s", service, method, result:err_or_nil())
                                else
                                    log.fmt_error("Provider %s %s errored: %s", service, method, result)
                                end
                            end
                        end
                    else
                        log.fmt_error("Unable to find provider %s is not registered. %s", provider_module, provider)
                    end
                end
                local err = ("No provider implementation succeeded for %s.%s"):format(service, method)
                log.error(err)
                return Result.failure(err)
            end
        end,
    })
end

---@type Provider
local providers = setmetatable({}, {
    __index = function(tbl, service)
        tbl[service] = service_mt(service)
        return tbl[service]
    end,
})

return providers
