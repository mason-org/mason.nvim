local EventEmitter = require "mason-core.EventEmitter"
local settings = require "mason.settings"
local uv = vim.uv

local event = EventEmitter:new()

---@class Spinner
---@field id string
---@field private enabled boolean
---@field private active integer
---@field private index integer
local Spinner = {}
Spinner.__index = Spinner

---@type string[]
local texts = settings.current.ui.icons.spinner_texts

---@type integer
local texts_length = #texts

---@type uv.uv_timer_t|nil
local timer = nil

---@type table<string, fun()>
local ticks = {}

---@type integer spinner refresh interval
local INTERVAL = 80

local function start_tick(id, cb)
    if not ticks[id] then
        ticks[id] = cb
    end

    if timer then
        return
    end

    timer = uv.new_timer()
    assert(timer, "Failed to create spinner timer")
    timer:start(
        0,
        INTERVAL,
        vim.schedule_wrap(function()
            vim.iter(ticks):each(function(_, f)
                if f then
                    f()
                end
            end)
            -- combine all spinners refresh event into one.
            event:emit "change"
        end)
    )
end

local function stop_tick(id)
    ticks[id] = nil
    if next(ticks) == nil and timer then
        timer:stop()
        timer:close()
        timer = nil
    end
end

---Create a new spinner.
---
---@return Spinner
local function new(id)
    return setmetatable({
        id = id,
        enabled = false,
        active = 0,
        index = 1,
    }, Spinner)
end

---Start spinner.
function Spinner:start()
    self.active = self.active + 1
    if self.enabled then
        return
    end

    self.enabled = true
    --- refresh ui immediately.
    event:emit "change"

    start_tick(self.id, function()
        self.index = (self.index % texts_length) + 1
    end)
end

---Stop spinner.
function Spinner:stop()
    self.active = self.active - 1
    if not self.enabled or self.active > 0 then
        return
    end

    stop_tick(self.id)

    self.enabled = false
    self.active = 0

    event:emit "change"
end

function Spinner:__tostring()
    return self.enabled and texts[self.index] or ""
end

---@type table<string, Spinner>
local instances = setmetatable({}, {
    __index = function(self, k)
        local v = rawget(self, k)
        if v == nil then
            v = new(k)
            rawset(self, k, v)
        end
        return v
    end,
})

return {
    event = event,
    instances = instances,
}
