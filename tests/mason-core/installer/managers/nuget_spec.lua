local match = require "luassert.match"
local nuget = require "mason-core.installer.managers.nuget"
local spy = require "luassert.spy"
local test_helpers = require "mason-test.helpers"

describe("nuget manager", function()
    it("should install", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            nuget.install("nuget-package", "1.0.0")
        end)

        assert.spy(ctx.spawn.dotnet).was_called(1)
        assert.spy(ctx.spawn.dotnet).was_called_with {
            "tool",
            "update",
            "--tool-path",
            ".",
            { "--version", "1.0.0" },
            "nuget-package",
        }
    end)

    it("should write output", function()
        local ctx = test_helpers.create_context()
        spy.on(ctx.stdio_sink, "stdout")

        ctx:execute(function()
            nuget.install("nuget-package", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing nuget package nuget-package@1.0.0…\n")
    end)
end)
