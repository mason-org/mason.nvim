---@class Failure
---@field error any
local Failure = {}
Failure.__index = Failure

function Failure:new(error)
    ---@type Failure
    local instance = {}
    setmetatable(instance, self)
    instance.error = error
    return instance
end

---@class Result
---@field value any
local Result = {}
Result.__index = Result

function Result:new(value)
    ---@type Result
    local instance = {}
    setmetatable(instance, self)
    instance.value = value
    return instance
end

function Result.success(value)
    return Result:new(value)
end

function Result.failure(error)
    return Result:new(Failure:new(error))
end

function Result:get_or_nil()
    if self:is_success() then
        return self.value
    end
end

function Result:get_or_else(value)
    if self:is_success() then
        return self.value
    else
        return value
    end
end

---@param exception any? The exception to throw if the result is a failure.
function Result:get_or_throw(exception)
    if self:is_success() then
        return self.value
    else
        if exception ~= nil then
            error(exception, 2)
        else
            error(self.value.error, 2)
        end
    end
end

function Result:err_or_nil()
    if self:is_failure() then
        return self.value.error
    end
end

function Result:is_failure()
    return getmetatable(self.value) == Failure
end

function Result:is_success()
    return getmetatable(self.value) ~= Failure
end

---@param mapper_fn fun(value: any): any
function Result:map(mapper_fn)
    if self:is_success() then
        return Result.success(mapper_fn(self.value))
    else
        return self
    end
end

---@param mapper_fn fun(value: any): any
function Result:map_err(mapper_fn)
    if self:is_failure() then
        return Result.failure(mapper_fn(self.value.error))
    else
        return self
    end
end

---@param mapper_fn fun(value: any): any
function Result:map_catching(mapper_fn)
    if self:is_success() then
        local ok, result = pcall(mapper_fn, self.value)
        if ok then
            return Result.success(result)
        else
            return Result.failure(result)
        end
    else
        return self
    end
end

---@param recover_fn fun(value: any): any
function Result:recover(recover_fn)
    if self:is_failure() then
        return Result.success(recover_fn(self:err_or_nil()))
    else
        return self
    end
end

---@param recover_fn fun(value: any): any
function Result:recover_catching(recover_fn)
    if self:is_failure() then
        local ok, value = pcall(recover_fn, self:err_or_nil())
        if ok then
            return Result.success(value)
        else
            return Result.failure(value)
        end
    else
        return self
    end
end

---@param fn fun(value: any): any
function Result:on_failure(fn)
    if self:is_failure() then
        fn(self.value.error)
    end
    return self
end

---@param fn fun(value: any): any
function Result:on_success(fn)
    if self:is_success() then
        fn(self.value)
    end
    return self
end

function Result:ok()
    local Optional = require "mason-core.optional"
    if self:is_success() then
        return Optional.of(self.value)
    else
        return Optional.empty()
    end
end

---@param fn fun(value: any): Result
function Result:and_then(fn)
    if self:is_success() then
        return fn(self.value)
    else
        return self
    end
end

---@param fn fun(err: any): Result
function Result:or_else(fn)
    if self:is_failure() then
        return fn(self:err_or_nil())
    else
        return self
    end
end

---@param fn fun(): any
---@return Result
function Result.run_catching(fn)
    local ok, result = pcall(fn)
    if ok then
        return Result.success(result)
    else
        return Result.failure(result)
    end
end

---@generic T
---@param fn fun(try: fun(result: Result)): T?
---@return Result # Result<T>
function Result.try(fn)
    local thread = coroutine.create(fn)
    local step
    step = function(...)
        local ok, result = coroutine.resume(thread, ...)
        if not ok then
            return Result.failure(result)
        end
        if coroutine.status(thread) == "dead" then
            if getmetatable(result) == Result then
                return result
            else
                return Result.success(result)
            end
        elseif getmetatable(result) == Result then
            if result:is_failure() then
                return result
            else
                return step(result:get_or_nil())
            end
        else
            -- yield to parent coroutine
            return step(coroutine.yield(result))
        end
    end
    return step(coroutine.yield)
end

function Result.pcall(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then
        return Result.success(res)
    else
        return Result.failure(res)
    end
end

return Result
