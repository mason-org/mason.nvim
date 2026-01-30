local spinner = require "mason-core.spinner"
local stub = require "luassert.stub"
local eq = assert.are.same

---@diagnostic disable: invisible
---@diagnostic disable: undefined-field

describe("spinner", function()
    before_each(function()
        spinner.instances.sp = nil
        stub(vim.uv, "new_timer").returns {
            start = function(_, _, _, callback)
                callback()
            end,
            stop = function(_) end,
            close = function(_) end,
        }
        stub(vim, "schedule_wrap").invokes(function(fn)
            return fn
        end)
    end)

    it("empty default", function()
        local sp = spinner.instances.sp
        eq(false, sp.enabled)
        eq("", tostring(sp))
    end)

    it("start spinner", function()
        local sp = spinner.instances.sp
        stub(vim.uv, "new_timer").returns {
            start = function(_, _, _, callback)
                callback()
                eq(true, sp.enabled)
                eq(true, tostring(sp) ~= "")

                callback()
                eq(true, sp.enabled)
                eq(true, tostring(sp) ~= "")
            end,
            stop = function(_) end,
            close = function(_) end,
        }
        sp:start()
    end)

    it("remain start if call times start() > stop()", function()
        local sp = spinner.instances.sp

        sp:start()
        eq(true, sp.enabled)
        sp:start()
        eq(true, sp.enabled)

        sp:stop()
        -- remain enable
        eq(true, sp.enabled)

        sp:stop()
        eq(false, sp.enabled)

        -- remian stop
        sp:stop()
        eq(false, sp.enabled)
    end)
end)
