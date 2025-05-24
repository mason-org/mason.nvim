local golang = require "mason-core.installer.managers.golang"
local match = require "luassert.match"
local spy = require "luassert.spy"
local test_helpers = require "mason-test.helpers"

describe("golang manager", function()
    it("should install", function()
        local ctx = test_helpers.create_context()

        ctx:execute(function()
            golang.install("my-golang", "1.0.0")
        end)

        assert.spy(ctx.spawn.go).was_called(1)
        assert.spy(ctx.spawn.go).was_called_with {
            "install",
            "-v",
            "my-golang@1.0.0",
            env = {
                GOBIN = ctx.cwd:get(),
            },
        }
    end)

    it("should write output", function()
        local ctx = test_helpers.create_context()
        spy.on(ctx.stdio_sink, "stdout")

        ctx:execute(function()
            golang.install("my-golang", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing go package my-golang@1.0.0…\n")
    end)

    it("should install extra packages", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            golang.install("my-golang", "1.0.0", {
                extra_packages = { "extra", "package" },
            })
        end)

        assert.spy(ctx.spawn.go).was_called(3)
        assert.spy(ctx.spawn.go).was_called_with {
            "install",
            "-v",
            "my-golang@1.0.0",
            env = {
                GOBIN = ctx.cwd:get(),
            },
        }
        assert.spy(ctx.spawn.go).was_called_with {
            "install",
            "-v",
            "extra@latest",
            env = {
                GOBIN = ctx.cwd:get(),
            },
        }
        assert.spy(ctx.spawn.go).was_called_with {
            "install",
            "-v",
            "package@latest",
            env = {
                GOBIN = ctx.cwd:get(),
            },
        }
    end)
end)
