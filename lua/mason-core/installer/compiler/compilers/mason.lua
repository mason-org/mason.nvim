local Result = require "mason-core.result"
local _ = require "mason-core.functional"

local M = {}

---@param source RegistryPackageSource
---@param purl Purl
function M.parse(source, purl)
    if type(source.install) ~= "function" and type((getmetatable(source.install) or {}).__call) ~= "function" then
        return Result.failure "source.install is not a function."
    end

    ---@class ParsedMasonSource : ParsedPackageSource
    local parsed_source = {
        purl = purl,
        ---@type async fun(ctx: InstallContext, purl: Purl)
        install = source.install,
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedMasonSource
function M.install(ctx, source)
    ctx.spawn.strict_mode = true
    return Result.pcall(source.install, ctx, source.purl)
        :on_success(function()
            ctx.spawn.strict_mode = false
        end)
        :on_failure(function()
            ctx.spawn.strict_mode = false
        end)
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return Result.failure "Unimplemented."
end

return M
