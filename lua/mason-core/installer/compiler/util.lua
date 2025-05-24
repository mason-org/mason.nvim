local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local installer = require "mason-core.installer"
local log = require "mason-core.log"
local platform = require "mason-core.platform"

local M = {}

---@generic T : { target: Platform | Platform[] }
---@param candidates T[] | T
---@param opts PackageInstallOpts
---@return Result # Result<T>
function M.coalesce_by_target(candidates, opts)
    if not _.is_list(candidates) then
        return Result.success(candidates)
    end
    return Optional.of_nilable(_.find_first(function(asset)
        if opts.target then
            -- Matching against a provided target rather than the current platform is an escape hatch primarily meant
            -- for automated testing purposes.
            if type(asset.target) == "table" then
                return _.any(_.equals(opts.target), asset.target)
            else
                return asset.target == opts.target
            end
        else
            if type(asset.target) == "table" then
                return _.any(function(target)
                    return platform.is[target]
                end, asset.target)
            else
                return platform.is[asset.target]
            end
        end
    end, candidates)):ok_or "PLATFORM_UNSUPPORTED"
end

---Checks whether a custom version of a package installation corresponds to a valid version.
---@async
---@param versions_thunk async fun(): Result Result<string[]>
function M.ensure_valid_version(versions_thunk)
    local ctx = installer.context()
    local version = ctx.opts.version

    if version and not ctx.opts.force then
        ctx.stdio_sink:stdout "Fetching available versions…\n"
        local all_versions = versions_thunk()
        if all_versions:is_failure() then
            log.warn("Failed to fetch versions for package", ctx.package)
            -- Gracefully fail (i.e. optimistically continue package installation)
            return Result.success()
        end
        all_versions = all_versions:get_or_else {}

        if not _.any(_.equals(version), all_versions) then
            ctx.stdio_sink:stderr(("Tried to install invalid version %q. Available versions:\n"):format(version))
            ctx.stdio_sink:stderr(_.compose(_.join "\n", _.map(_.join ", "), _.split_every(15))(all_versions))
            ctx.stdio_sink:stderr "\n\n"
            ctx.stdio_sink:stderr(
                ("Run with --force flag to bypass version validation:\n  :MasonInstall --force %s@%s\n\n"):format(
                    ctx.package.name,
                    version
                )
            )
            return Result.failure(("Version %q is not available."):format(version))
        end
    end

    return Result.success()
end

---@param platforms string[]
function M.ensure_valid_platform(platforms)
    if not _.any(function(target)
        return platform.is[target]
    end, platforms) then
        return Result.failure "PLATFORM_UNSUPPORTED"
    end
    return Result.success()
end

return M
