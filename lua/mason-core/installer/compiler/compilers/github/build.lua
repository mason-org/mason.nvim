local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local common = require "mason-core.installer.managers.common"
local expr = require "mason-core.installer.compiler.expr"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@class GitHubBuildSource : RegistryPackageSource
---@field build BuildInstruction | BuildInstruction[]

---@param source GitHubBuildSource
---@param purl Purl
---@param opts PackageInstallOpts
function M.parse(source, purl, opts)
    return Result.try(function(try)
        ---@type BuildInstruction
        local build_instruction = try(util.coalesce_by_target(source.build, opts))

        local expr_ctx = { version = purl.version }

        build_instruction.env = try(expr.tbl_interpolate(build_instruction.env or {}, expr_ctx))

        ---@class ParsedGitHubBuildSource : ParsedPackageSource
        local parsed_source = {
            build = build_instruction,
            repo = ("https://github.com/%s/%s.git"):format(purl.namespace, purl.name),
            rev = purl.version,
        }
        return parsed_source
    end)
end

---@async
---@param ctx InstallContext
---@param source ParsedGitHubBuildSource
function M.install(ctx, source)
    local std = require "mason-core.installer.managers.std"
    return Result.try(function(try)
        try(std.clone(source.repo, { rev = source.rev }))
        try(common.run_build_instruction(source.build))
    end)
end

return M
