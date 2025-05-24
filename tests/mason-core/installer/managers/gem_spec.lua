local gem = require "mason-core.installer.managers.gem"
local match = require "luassert.match"
local spy = require "luassert.spy"
local test_helper = require "mason-test.helpers"

describe("gem manager", function()
    it("should install", function()
        local ctx = test_helper.create_context()

        local result = ctx:execute(function()
            return gem.install("my-gem", "1.0.0")
        end)
        assert.is_true(result:is_success())

        assert.spy(ctx.spawn.gem).was_called(1)
        assert.spy(ctx.spawn.gem).was_called_with {
            "install",
            "--no-user-install",
            "--no-format-executable",
            "--install-dir=.",
            "--bindir=bin",
            "--no-document",
            "my-gem:1.0.0",
            vim.NIL, -- extra_packages
            env = {
                GEM_HOME = ctx.location:staging "dummy",
            },
        }
    end)

    it("should write output", function()
        local ctx = test_helper.create_context()
        spy.on(ctx.stdio_sink, "stdout")
        ctx:execute(function()
            gem.install("my-gem", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing gem my-gem@1.0.0…\n")
    end)

    it("should install extra packages", function()
        local ctx = test_helper.create_context()
        ctx:execute(function()
            gem.install("my-gem", "1.0.0", {
                extra_packages = { "extra-gem" },
            })
        end)

        assert.spy(ctx.spawn.gem).was_called(1)
        assert.spy(ctx.spawn.gem).was_called_with {
            "install",
            "--no-user-install",
            "--no-format-executable",
            "--install-dir=.",
            "--bindir=bin",
            "--no-document",
            "my-gem:1.0.0",
            { "extra-gem" },
            env = {
                GEM_HOME = ctx.cwd:get(),
            },
        }
    end)
end)
