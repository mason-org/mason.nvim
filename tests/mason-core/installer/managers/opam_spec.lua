local match = require "luassert.match"
local opam = require "mason-core.installer.managers.opam"
local spy = require "luassert.spy"
local test_helpers = require "mason-test.helpers"

describe("opam manager", function()
    it("should install", function()
        local ctx = test_helpers.create_context()

        ctx:execute(function()
            opam.install("opam-package", "1.0.0")
        end)

        assert.spy(ctx.spawn.opam).was_called(1)
        assert.spy(ctx.spawn.opam).was_called_with {
            "install",
            "--destdir=.",
            "--yes",
            "--verbose",
            "opam-package.1.0.0",
        }
    end)

    it("should write output", function()
        local ctx = test_helpers.create_context()
        spy.on(ctx.stdio_sink, "stdout")

        ctx:execute(function()
            opam.install("opam-package", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing opam package opam-package@1.0.0…\n")
    end)
end)
