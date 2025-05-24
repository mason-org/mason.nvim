local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local platform = require "mason-core.platform"

local M = {}

local parse_expr = _.compose(
    _.apply_spec {
        value_expr = _.head,
        filters = _.drop(1),
    },
    _.filter(_.complement(_.equals "")),
    _.map(_.trim),
    _.split "|"
)

---@param predicate (fun(value: string): boolean) | boolean
---@param value string
local take_if = _.curryN(function(predicate, value)
    if type(predicate) == "boolean" then
        predicate = _.always(predicate)
    end
    return predicate(value) and value or nil
end, 2)

---@param predicate (fun(value: string): boolean) | boolean
---@param value string
local take_if_not = _.curryN(function(predicate, value)
    if type(predicate) == "boolean" then
        predicate = _.always(predicate)
    end
    return (not predicate(value)) and value or nil
end, 2)

local FILTERS = {
    equals = _.equals,
    not_equals = _.not_equals,
    strip_prefix = _.strip_prefix,
    strip_suffix = _.strip_suffix,
    take_if = take_if,
    take_if_not = take_if_not,
    to_lower = _.to_lower,
    to_upper = _.to_upper,
    is_platform = function(target)
        return platform.is[target]
    end,
}

---@generic T : table
---@param tbl T
---@return T
local function shallow_clone(tbl)
    local res = {}
    for k, v in pairs(tbl) do
        res[k] = v
    end
    return res
end

---@param expr string
---@param ctx table<string, any>
local function eval(expr, ctx)
    return setfenv(assert(loadstring("return " .. expr), ("Failed to parse expression: %q"):format(expr)), ctx)()
end

---@param str string
---@param ctx table<string, any>
function M.interpolate(str, ctx)
    ctx = shallow_clone(ctx)
    setmetatable(ctx, { __index = FILTERS })
    return Result.pcall(function()
        return _.gsub("{{([^}]+)}}", function(expr)
            local components = parse_expr(expr)

            local value = eval(components.value_expr, ctx)

            local filters = _.map(function(filter_expr)
                local filter = eval(filter_expr, ctx)
                assert(type(filter) == "function", ("Invalid filter expression: %q"):format(filter_expr))
                return filter
            end, components.filters)

            local reduced_value = _.reduce(_.apply_to, value, filters)

            return reduced_value ~= nil and tostring(reduced_value) or ""
        end, str)
    end)
end

---@generic T : table
---@param tbl T
---@param ctx table
---@return Result # Result<T>
function M.tbl_interpolate(tbl, ctx)
    return Result.try(function(try)
        local interpolated = {}
        for k, v in pairs(tbl) do
            if type(k) == "string" then
                k = try(M.interpolate(k, ctx))
            end
            if type(v) == "string" then
                interpolated[k] = try(M.interpolate(v, ctx))
            elseif type(v) == "table" then
                interpolated[k] = try(M.tbl_interpolate(v, ctx))
            else
                interpolated[k] = v
            end
        end
        return interpolated
    end)
end

return M
