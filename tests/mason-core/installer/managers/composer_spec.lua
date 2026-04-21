local composer = require "mason-core.installer.managers.composer"
local match = require "luassert.match"
local spy = require "luassert.spy"
local test_helpers = require "mason-test.helpers"

describe("composer manager", function()
    it("should install", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            composer.install("my-package", "1.0.0")
        end)

        assert.spy(ctx.spawn.composer).was_called(2)
        assert.spy(ctx.spawn.composer).was_called_with {
            "init",
            "--no-interaction",
            "--stability=stable",
        }
        assert.spy(ctx.spawn.composer).was_called_with {
            "require",
            "my-package:1.0.0",
        }
    end)

    it("should write output", function()
        local ctx = test_helpers.create_context()
        spy.on(ctx.stdio_sink, "stdout")

        ctx:execute(function()
            composer.install("my-package", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing composer package my-package@1.0.0…\n")
    end)
end)
