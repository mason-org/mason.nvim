---@class Optional<T>
---@field private _value unknown
local Optional = {}
Optional.__index = Optional

---@param value any
function Optional:new(value)
    ---@type Optional
    local instance = {}
    setmetatable(instance, self)
    instance._value = value
    return instance
end

local EMPTY = Optional:new(nil)

---@param value any
function Optional.of_nilable(value)
    if value == nil then
        return EMPTY
    else
        return Optional:new(value)
    end
end

function Optional.empty()
    return EMPTY
end

---@param value any
function Optional.of(value)
    return Optional:new(value)
end

---@param mapper_fn fun(value: any): any
function Optional:map(mapper_fn)
    if self:is_present() then
        return Optional.of_nilable(mapper_fn(self._value))
    else
        return EMPTY
    end
end

function Optional:get()
    if not self:is_present() then
        error("No value present.", 2)
    end
    return self._value
end

---@param value any
function Optional:or_else(value)
    if self:is_present() then
        return self._value
    else
        return value
    end
end

---@param supplier fun(): any
function Optional:or_else_get(supplier)
    if self:is_present() then
        return self._value
    else
        return supplier()
    end
end

---@param supplier fun(value: any): Optional
---@return Optional
function Optional:and_then(supplier)
    if self:is_present() then
        return supplier(self._value)
    else
        return self
    end
end

---@param supplier fun(): Optional
---@return Optional
function Optional:or_(supplier)
    if self:is_present() then
        return self
    else
        return supplier()
    end
end

---@param exception any? The exception to throw if the result is a failure.
function Optional:or_else_throw(exception)
    if self:is_present() then
        return self._value
    else
        if exception then
            error(exception, 2)
        else
            error("No value present.", 2)
        end
    end
end

---@param fn fun(value: any)
function Optional:if_present(fn)
    if self:is_present() then
        fn(self._value)
    end
    return self
end

---@param fn fun(value: any)
function Optional:if_not_present(fn)
    if not self:is_present() then
        fn(self._value)
    end
    return self
end

function Optional:is_present()
    return self._value ~= nil
end

---@param err (fun(): any)|string
function Optional:ok_or(err)
    local Result = require "mason-core.result"
    if self:is_present() then
        return Result.success(self:get())
    else
        if type(err) == "string" then
            return Result.failure(err)
        else
            return Result.failure(err())
        end
    end
end

return Optional
