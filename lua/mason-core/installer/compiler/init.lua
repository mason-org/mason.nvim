local Optional = require "mason-core.optional"
local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local link = require "mason-core.installer.compiler.link"
local log = require "mason-core.log"
local schemas = require "mason-core.installer.compiler.schemas"
local util = require "mason-core.installer.compiler.util"

local M = {}

---@type table<RegistryPackageSpecSchema, boolean>
M.SCHEMA_CAP = _.set_of {
    "registry+v1",
}

---@type table<string, InstallerCompiler>
local COMPILERS = {}

---@param id string
---@param compiler InstallerCompiler
function M.register_compiler(id, compiler)
    COMPILERS[id] = compiler
end

M.register_compiler("cargo", _.lazy_require "mason-core.installer.compiler.compilers.cargo")
M.register_compiler("composer", _.lazy_require "mason-core.installer.compiler.compilers.composer")
M.register_compiler("gem", _.lazy_require "mason-core.installer.compiler.compilers.gem")
M.register_compiler("generic", _.lazy_require "mason-core.installer.compiler.compilers.generic")
M.register_compiler("github", _.lazy_require "mason-core.installer.compiler.compilers.github")
M.register_compiler("golang", _.lazy_require "mason-core.installer.compiler.compilers.golang")
M.register_compiler("luarocks", _.lazy_require "mason-core.installer.compiler.compilers.luarocks")
M.register_compiler("mason", _.lazy_require "mason-core.installer.compiler.compilers.mason")
M.register_compiler("npm", _.lazy_require "mason-core.installer.compiler.compilers.npm")
M.register_compiler("nuget", _.lazy_require "mason-core.installer.compiler.compilers.nuget")
M.register_compiler("opam", _.lazy_require "mason-core.installer.compiler.compilers.opam")
M.register_compiler("openvsx", _.lazy_require "mason-core.installer.compiler.compilers.openvsx")
M.register_compiler("pypi", _.lazy_require "mason-core.installer.compiler.compilers.pypi")

---@param purl Purl
---@return Result # Result<InstallerCompiler>
function M.get_compiler(purl)
    return Optional.of_nilable(COMPILERS[purl.type])
        :ok_or(("Current version of mason.nvim is not capable of parsing package type %q."):format(purl.type))
end

---@class InstallerCompiler
---@field parse fun(source: RegistryPackageSource, purl: Purl, opts: PackageInstallOpts): Result
---@field install async fun(ctx: InstallContext, source: ParsedPackageSource, purl: Purl): Result
---@field get_versions async fun(purl: Purl, source: RegistryPackageSource): Result # Result<string[]>

---@class ParsedPackageSource

---Upserts {dst} with contents of {src}. List table values will be merged, with contents of {src} prepended.
---@param dst table
---@param src table
local function upsert(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if _.is_list(v) then
                dst[k] = _.concat(v, dst[k] or {})
            else
                dst[k] = upsert(dst[k] or {}, src[k])
            end
        else
            dst[k] = v
        end
    end
    return dst
end

---@param source RegistryPackageSource
---@param version string?
local function coalesce_source(source, version)
    if version and source.version_overrides then
        for i = #source.version_overrides, 1, -1 do
            local version_override = source.version_overrides[i]
            local version_type, constraint = unpack(_.split(":", version_override.constraint))
            if version_type == "semver" then
                local semver = require "mason-core.semver"
                local version_match = Result.try(function(try)
                    local requested_version = try(semver.parse(version))
                    if _.starts_with("<=", constraint) then
                        local rule_version = try(semver.parse(_.strip_prefix("<=", constraint)))
                        return requested_version <= rule_version
                    elseif _.starts_with(">=", constraint) then
                        local rule_version = try(semver.parse(_.strip_prefix(">=", constraint)))
                        return requested_version >= rule_version
                    else
                        local rule_version = try(semver.parse(constraint))
                        return requested_version == rule_version
                    end
                end):get_or_else(false)

                if version_match then
                    return _.dissoc("constraint", version_override)
                end
            end
        end
    end
    return _.dissoc("version_overrides", source)
end

---@param spec RegistryPackageSpec
---@param opts PackageInstallOpts
function M.parse(spec, opts)
    log.trace("Parsing spec", spec.name, opts)
    return Result.try(function(try)
        if not M.SCHEMA_CAP[spec.schema] then
            return Result.failure(
                ("Current version of mason.nvim is not capable of parsing package schema version %q."):format(
                    spec.schema
                )
            )
        end

        local source = coalesce_source(spec.source, opts.version)

        ---@type Purl
        local purl = try(Purl.parse(source.id))
        log.trace("Parsed purl.", source.id, purl)
        if opts.version then
            purl.version = opts.version
        end

        ---@type InstallerCompiler
        local compiler = try(M.get_compiler(purl))
        log.trace("Found compiler for purl.", source.id)
        local parsed_source = try(compiler.parse(source, purl, opts))
        log.trace("Parsed source for purl.", source.id, parsed_source)
        return {
            compiler = compiler,
            source = vim.tbl_extend("keep", parsed_source, source),
            raw_source = source,
            purl = purl,
        }
    end):on_failure(function(err)
        log.debug("Failed to parse spec spec", spec.name, err)
    end)
end

---@async
---@param spec RegistryPackageSpec
---@param opts PackageInstallOpts
function M.compile_installer(spec, opts)
    log.debug("Compiling installer.", spec.name, opts)
    return Result.try(function(try)
        -- Parsers run synchronously and may access API functions, so we schedule before-hand.
        a.scheduler()

        local map_parse_err = _.cond {
            {
                _.equals "PLATFORM_UNSUPPORTED",
                function()
                    if opts.target then
                        return ("Platform %q is unsupported."):format(opts.target)
                    else
                        return "The current platform is unsupported."
                    end
                end,
            },
            { _.T, _.identity },
        }

        ---@type { purl: Purl, compiler: InstallerCompiler, source: ParsedPackageSource, raw_source: RegistryPackageSource }
        local parsed = try(M.parse(spec, opts):map_err(map_parse_err))

        ---@async
        ---@param ctx InstallContext
        return function(ctx)
            return Result.try(function(try)
                if ctx.opts.version then
                    try(util.ensure_valid_version(function()
                        return parsed.compiler.get_versions(parsed.purl, parsed.raw_source)
                    end))
                end

                -- Run installer
                a.scheduler()
                try(parsed.compiler.install(ctx, parsed.source, parsed.purl))

                if spec.schemas then
                    local result = schemas.download(ctx, spec, parsed.purl, parsed.source):on_failure(function(err)
                        log.error("Failed to download schemas", ctx.package, err)
                    end)
                    if opts.strict then
                        -- schema download sources are not considered stable nor a critical feature, so we only fail in strict mode
                        try(result)
                    end
                end

                -- Expand & register links
                if spec.bin then
                    try(link.bin(ctx, spec, parsed.purl, parsed.source))
                end
                if spec.share then
                    try(link.share(ctx, spec, parsed.purl, parsed.source))
                end
                if spec.opt then
                    try(link.opt(ctx, spec, parsed.purl, parsed.source))
                end

                ctx.receipt:with_source {
                    type = ctx.package.spec.schema,
                    id = Purl.compile(parsed.purl),
                    -- Exclude the "install" field from "mason" sources because this is a Lua function.
                    raw = parsed.purl.type == "mason" and _.dissoc("install", parsed.raw_source) or parsed.raw_source,
                }
                ctx.receipt:with_install_options(opts)
            end)
        end
    end)
end

return M
