local log = require "mason-core.log"
local match = require "luassert.match"
local spy = require "luassert.spy"

local EventEmitter = require "mason-core.EventEmitter"
local a = require "mason-core.async"

describe("EventEmitter", function()
    it("should call registered event handlers", function()
        local emitter = EventEmitter.init(setmetatable({}, { __index = EventEmitter }))
        local my_event_handler = spy.new()
        emitter:on("my:event", my_event_handler --[[@as fun()]])

        emitter:emit("my:event", { table = "value" })
        emitter:emit("my:event", 1337, 42)

        assert.spy(my_event_handler).was_called(2)
        assert.spy(my_event_handler).was_called_with(match.same { table = "value" })
        assert.spy(my_event_handler).was_called_with(1337, 42)
    end)

    it("should call registered event handlers only once", function()
        local emitter = EventEmitter.init(setmetatable({}, { __index = EventEmitter }))
        local my_event_handler = spy.new()
        emitter:once("my:event", my_event_handler --[[@as fun()]])

        emitter:emit("my:event", { table = "value" })
        emitter:emit("my:event", 1337, 42)

        assert.spy(my_event_handler).was_called(1)
        assert.spy(my_event_handler).was_called_with(match.same { table = "value" })
    end)

    it("should remove registered event handlers", function()
        local emitter = EventEmitter.init(setmetatable({}, { __index = EventEmitter }))
        local my_event_handler = spy.new() --[[@as fun()]]
        emitter:on("my:event", my_event_handler)
        emitter:once("my:event", my_event_handler)

        emitter:off("my:event", my_event_handler)

        emitter:emit("my:event", { table = "value" })
        assert.spy(my_event_handler).was_called(0)
    end)

    it("should log errors in handlers", function()
        spy.on(log, "fmt_warn")
        local emitter = EventEmitter.init(setmetatable({}, { __index = EventEmitter }))
        emitter:on("event", mockx.throws "My error.")
        emitter:emit "event"
        a.run_blocking(a.wait, vim.schedule)
        assert.spy(log.fmt_warn).was_called(1)
        assert
            .spy(log.fmt_warn)
            .was_called_with("EventEmitter handler failed for event %s with error %s", "event", "My error.")
    end)
end)
