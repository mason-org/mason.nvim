local InstallHandle = require "mason-core.installer.InstallHandle"
local mock = require "luassert.mock"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

describe("InstallHandle ::", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should register spawn handle", function()
        local handle = InstallHandle:new(mock.new {})
        local spawn_handle_change_handler = spy.new()
        local luv_handle = mock.new {}

        handle:once("spawn_handles:change", spawn_handle_change_handler)
        handle:register_spawn_handle(luv_handle, 1337, "tar", { "-xvf", "file" })

        assert.same({
            uv_handle = luv_handle,
            pid = 1337,
            cmd = "tar",
            args = { "-xvf", "file" },
        }, handle:peek_spawn_handle():get())
        assert.spy(spawn_handle_change_handler).was_called(1)
    end)

    it("should deregister spawn handle", function()
        local handle = InstallHandle:new(mock.new {})
        local spawn_handle_change_handler = spy.new()
        local luv_handle1 = mock.new {}
        local luv_handle2 = mock.new {}

        handle:on("spawn_handles:change", spawn_handle_change_handler)
        handle:register_spawn_handle(luv_handle1, 42, "curl", { "someurl" })
        handle:register_spawn_handle(luv_handle2, 1337, "tar", { "-xvf", "file" })

        assert.is_true(handle:deregister_spawn_handle(luv_handle1))
        assert.equals(1, #handle.spawn_handles)
        assert.same({
            uv_handle = luv_handle2,
            pid = 1337,
            cmd = "tar",
            args = { "-xvf", "file" },
        }, handle:peek_spawn_handle():get())
        assert.spy(spawn_handle_change_handler).was_called(3)
    end)

    it("should change state", function()
        local handle = InstallHandle:new(mock.new {})
        local state_change_handler = spy.new()

        handle:once("state:change", state_change_handler)
        handle:set_state "QUEUED"

        assert.equals("QUEUED", handle.state)
        assert.spy(state_change_handler).was_called(1)
        assert.spy(state_change_handler).was_called_with("QUEUED", "IDLE")
    end)

    it("should send signals to registered handles", function()
        local process = require "mason-core.process"
        stub(process, "kill")
        local uv_handle = {}
        local handle = InstallHandle:new(mock.new {})
        local kill_handler = spy.new()

        handle:once("kill", kill_handler)
        handle.state = "ACTIVE"
        handle.spawn_handles = { { uv_handle = uv_handle } }
        handle:kill(9)

        assert.spy(process.kill).was_called(1)
        assert.spy(process.kill).was_called_with(uv_handle, 9)
        assert.spy(kill_handler).was_called(1)
        assert.spy(kill_handler).was_called_with(9)
    end)

    it("should terminate handle", function()
        local process = require "mason-core.process"
        stub(process, "kill")
        local uv_handle1 = {}
        local uv_handle2 = {}
        local handle = InstallHandle:new(mock.new {})
        local kill_handler = spy.new()
        local terminate_handler = spy.new()
        local closed_handler = spy.new()

        handle:once("kill", kill_handler)
        handle:once("terminate", terminate_handler)
        handle:once("closed", closed_handler)
        handle.state = "ACTIVE"
        handle.spawn_handles = { { uv_handle = uv_handle2 }, { uv_handle = uv_handle2 } }
        handle:terminate()

        assert.spy(process.kill).was_called(2)
        assert.spy(process.kill).was_called_with(uv_handle1, 15)
        assert.spy(process.kill).was_called_with(uv_handle2, 15)
        assert.spy(kill_handler).was_called(1)
        assert.spy(kill_handler).was_called_with(15)
        assert.spy(terminate_handler).was_called(1)
        assert.is_true(handle.is_terminated)
        assert.wait(function()
            assert.is_true(handle:is_closed())
            assert.spy(closed_handler).was_called(1)
        end)
    end)
end)
