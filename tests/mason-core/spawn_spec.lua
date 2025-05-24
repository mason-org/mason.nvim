local a = require "mason-core.async"
local match = require "luassert.match"
local platform = require "mason-core.platform"
local process = require "mason-core.process"
local spawn = require "mason-core.spawn"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

describe("async spawn", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should spawn commands and return stdout & stderr", function()
        local result = a.run_blocking(spawn.env, {
            env_raw = { "FOO=bar" },
        })
        assert.is_true(result:is_success())
        assert.equals("FOO=bar\n", result:get_or_nil().stdout)
        assert.equals("", result:get_or_nil().stderr)
    end)

    it("should use provided stdio_sink", function()
        local stdout = spy.new()
        local stdio = process.StdioSink:new {
            stdout = stdout,
        }
        local result = a.run_blocking(spawn.env, {
            env_raw = { "FOO=bar" },
            stdio_sink = stdio,
        })
        assert.is_true(result:is_success())
        assert.equals(nil, result:get_or_nil())
        -- Not 100 %guaranteed it's only called once because output is always buffered, but it's extremely likely
        assert.spy(stdout).was_called(1)
        assert.spy(stdout).was_called_with "FOO=bar\n"
    end)

    it("should pass command arguments", function()
        local result = a.run_blocking(spawn.bash, {
            "-c",
            'echo "Hello $VAR"',
            env = { VAR = "world" },
        })

        assert.is_true(result:is_success())
        assert.equals("Hello world\n", result:get_or_nil().stdout)
        assert.equals("", result:get_or_nil().stderr)
    end)

    it("should ignore vim.NIL args", function()
        spy.on(process, "spawn")
        local result = a.run_blocking(spawn.bash, {
            vim.NIL,
            vim.NIL,
            "-c",
            { vim.NIL, vim.NIL },
            'echo "Hello $VAR"',
            env = { VAR = "world" },
        })

        assert.is_true(result:is_success())
        assert.equals("Hello world\n", result:get_or_nil().stdout)
        assert.equals("", result:get_or_nil().stderr)
        assert.spy(process.spawn).was_called(1)
        assert.spy(process.spawn).was_called_with(
            "bash",
            match.tbl_containing {
                stdio_sink = match.instanceof(process.BufferedSink),
                env = match.list_containing "VAR=world",
                args = match.tbl_containing {
                    "-c",
                    'echo "Hello $VAR"',
                },
            },
            match.is_function()
        )
    end)

    it("should flatten table args", function()
        local result = a.run_blocking(spawn.bash, {
            { "-c", 'echo "Hello $VAR"' },
            env = { VAR = "world" },
        })

        assert.is_true(result:is_success())
        assert.equals("Hello world\n", result:get_or_nil().stdout)
        assert.equals("", result:get_or_nil().stderr)
    end)

    it("should call on_spawn", function()
        local on_spawn = spy.new(function(_, stdio)
            local stdin = stdio[1]
            stdin:write "im so piped rn"
            stdin:close()
        end)

        local result = a.run_blocking(spawn.cat, {
            { "-" },
            on_spawn = on_spawn,
        })

        assert.spy(on_spawn).was_called(1)
        assert.spy(on_spawn).was_called_with(match.is_not.is_nil(), match.is_table(), match.is_number())
        assert.is_true(result:is_success())
        assert.equals("im so piped rn", result:get_or_nil().stdout)
    end)

    it("should not call on_spawn if spawning fails", function()
        local on_spawn = spy.new()

        local result = a.run_blocking(spawn.this_cmd_doesnt_exist, {
            on_spawn = on_spawn,
        })

        assert.spy(on_spawn).was_called(0)
        assert.is_true(result:is_failure())
    end)

    it("should handle failure to spawn process", function()
        stub(process, "spawn", function(_, _, callback)
            callback(false)
        end)

        local result = a.run_blocking(spawn.my_cmd, {})
        assert.is_true(result:is_failure())
        assert.is_nil(result:err_or_nil().exit_code)
    end)

    it("should format failure message", function()
        stub(process, "spawn", function(cmd, opts, callback)
            opts.stdio_sink:stderr(("This is an error message for %s!"):format(cmd))
            callback(false, 127)
        end)

        local result = a.run_blocking(spawn.bash, {})
        assert.is_true(result:is_failure())
        assert.equals(
            "spawn: bash failed with exit code 127 and signal -. This is an error message for bash!",
            tostring(result:err_or_nil())
        )
    end)

    describe("Windows", function()
        before_each(function()
            platform.is.win = true
        end)

        after_each(function()
            platform.is.win = nil
        end)

        it("should use exepath to get absolute path to executable", function()
            stub(process, "spawn", function(_, _, callback)
                callback(true, 0, 0)
            end)

            local result = a.run_blocking(spawn.bash, { "arg1" })
            assert.is_true(result:is_success())
            assert.spy(process.spawn).was_called(1)
            assert.spy(process.spawn).was_called_with(
                vim.fn.exepath "bash",
                match.tbl_containing {
                    args = match.same { "arg1" },
                },
                match.is_function()
            )
        end)

        it("should not use exepath if env.PATH is set", function()
            stub(process, "spawn", function(_, _, callback)
                callback(true, 0, 0)
            end)

            local result = a.run_blocking(spawn.bash, { "arg1", env = { PATH = "C:\\some\\path" } })
            assert.is_true(result:is_success())
            assert.spy(process.spawn).was_called(1)
            assert.spy(process.spawn).was_called_with(
                "bash",
                match.tbl_containing {
                    args = match.same { "arg1" },
                },
                match.is_function()
            )
        end)

        it("should not use exepath if env_raw.PATH is set", function()
            stub(process, "spawn", function(_, _, callback)
                callback(true, 0, 0)
            end)

            local result = a.run_blocking(spawn.bash, { "arg1", env_raw = { "PATH=C:\\some\\path" } })
            assert.is_true(result:is_success())
            assert.spy(process.spawn).was_called(1)
            assert.spy(process.spawn).was_called_with(
                "bash",
                match.tbl_containing {
                    args = match.same { "arg1" },
                },
                match.is_function()
            )
        end)

        it("should not use exepath if with_paths is provided", function()
            stub(process, "spawn", function(_, _, callback)
                callback(true, 0, 0)
            end)

            local result = a.run_blocking(spawn.bash, { "arg1", with_paths = { "C:\\some\\path" } })
            assert.is_true(result:is_success())
            assert.spy(process.spawn).was_called(1)
            assert.spy(process.spawn).was_called_with(
                "bash",
                match.tbl_containing {
                    args = match.same { "arg1" },
                },
                match.is_function()
            )
        end)
    end)
end)
