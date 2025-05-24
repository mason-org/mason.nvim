local Result = require "mason-core.result"
local _ = require "mason-core.functional"

local M = {}

---@param purl Purl
local function parse_package_name(purl)
    if purl.namespace then
        return ("%s/%s"):format(purl.namespace, purl.name)
    else
        return purl.name
    end
end

local parse_server = _.path { "qualifiers", "repository_url" }
local parse_dev = _.compose(_.equals "true", _.path { "qualifiers", "dev" })

---@param source RegistryPackageSource
---@param purl Purl
function M.parse(source, purl)
    ---@class ParsedLuaRocksSource : ParsedPackageSource
    local parsed_source = {
        package = parse_package_name(purl),
        version = purl.version,
        ---@type string?
        server = parse_server(purl),
        ---@type boolean?
        dev = parse_dev(purl),
    }

    return Result.success(parsed_source)
end

---@async
---@param ctx InstallContext
---@param source ParsedLuaRocksSource
function M.install(ctx, source)
    local luarocks = require "mason-core.installer.managers.luarocks"
    return luarocks.install(source.package, source.version, {
        server = source.server,
        dev = source.dev,
    })
end

---@async
---@param purl Purl
function M.get_versions(purl)
    return Result.failure "Unimplemented."
end

return M
