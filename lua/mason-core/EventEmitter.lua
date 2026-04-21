local log = require "mason-core.log"
---@class EventEmitter
---@field private __event_handlers table<any, table<fun(), fun()>>
---@field private __event_handlers_once table<any, table<fun(), fun()>>
local EventEmitter = {}
EventEmitter.__index = EventEmitter

function EventEmitter:new()
    local instance = {}
    setmetatable(instance, self)
    instance.__event_handlers = {}
    instance.__event_handlers_once = {}
    return instance
end

---@generic T
---@param obj T
---@return T
function EventEmitter.init(obj)
    obj.__event_handlers = {}
    obj.__event_handlers_once = {}
    return obj
end

---@param event any
---@param handler fun(...): any
local function call_handler(event, handler, ...)
    local ok, err = pcall(handler, ...)
    if not ok then
        log.fmt_warn("EventEmitter handler failed for event %s with error %s", event, err)
    end
end

---@param event any
function EventEmitter:emit(event, ...)
    if self.__event_handlers[event] then
        for handler in pairs(self.__event_handlers[event]) do
            call_handler(event, handler, ...)
        end
    end
    if self.__event_handlers_once[event] then
        for handler in pairs(self.__event_handlers_once[event]) do
            call_handler(event, handler, ...)
            self.__event_handlers_once[event][handler] = nil
        end
    end
    return self
end

---@param event any
---@param handler fun(payload: any)
function EventEmitter:on(event, handler)
    if not self.__event_handlers[event] then
        self.__event_handlers[event] = {}
    end
    self.__event_handlers[event][handler] = handler
    return self
end

---@param event any
---@param handler fun(payload: any)
function EventEmitter:once(event, handler)
    if not self.__event_handlers_once[event] then
        self.__event_handlers_once[event] = {}
    end
    self.__event_handlers_once[event][handler] = handler
    return self
end

---@param event any
---@param handler fun(payload: any)
function EventEmitter:off(event, handler)
    if self.__event_handlers[event] then
        self.__event_handlers[event][handler] = nil
    end
    if self.__event_handlers_once[event] then
        self.__event_handlers_once[event][handler] = nil
    end
    return self
end

---@private
function EventEmitter:__clear_event_handlers()
    self.__event_handlers = {}
    self.__event_handlers_once = {}
end

return EventEmitter
