local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local expr = require "mason-core.installer.compiler.expr"
local fetch = require "mason-core.fetch"
local log = require "mason-core.log"
local path = require "mason-core.path"
local std = require "mason-core.installer.managers.std"

local M = {}

---@async
---@param ctx InstallContext
---@param url string
local function download_lsp_schema(ctx, url)
    return Result.try(function(try)
        local is_vscode_schema = _.starts_with("vscode:", url)
        local out_file = path.concat { "mason-schemas", "lsp.json" }
        local share_file = path.concat { "mason-schemas", "lsp", ("%s.json"):format(ctx.package.name) }

        if is_vscode_schema then
            local url = unpack(_.match("^vscode:(.+)$", url))
            ctx.stdio_sink:stdout(("Downloading LSP configuration schema from %q…\n"):format(url))
            local json = try(fetch(url))

            ---@type { contributes?: { configuration?: table } }
            local schema = try(Result.pcall(vim.json.decode, json))
            local configuration = schema.contributes and schema.contributes.configuration

            if configuration then
                ctx.fs:write_file(out_file, vim.json.encode(configuration) --[[@as string]])
                ctx.links.share[share_file] = out_file
            else
                return Result.failure "Unable to find LSP entry in VSCode schema."
            end
        else
            ctx.stdio_sink:stdout(("Downloading LSP configuration schema from %q…\n"):format(url))
            try(std.download_file(url, out_file))
            ctx.links.share[share_file] = out_file
        end
    end)
end

---@async
---@param ctx InstallContext
---@param spec RegistryPackageSpec
---@param purl Purl
---@param source ParsedPackageSource
---@nodiscard
function M.download(ctx, spec, purl, source)
    return Result.try(function(try)
        log.debug("schemas: download", ctx.package, spec.schemas)
        local schemas = spec.schemas
        if not schemas then
            return
        end
        ---@type RegistryPackageSchemas
        local interpolated_schemas = try(expr.tbl_interpolate(schemas, { version = purl.version, source = source }))
        ctx.fs:mkdir "mason-schemas"

        if interpolated_schemas.lsp then
            try(a.wait_first {
                function()
                    return download_lsp_schema(ctx, interpolated_schemas.lsp)
                end,
                function()
                    a.sleep(5000)
                    return Result.failure "Schema download timed out."
                end,
            })
        end
    end)
end

return M
