local cargo = require "mason-core.installer.managers.cargo"
local match = require "luassert.match"
local spy = require "luassert.spy"
local test_helpers = require "mason-test.helpers"

describe("cargo manager", function()
    it("should install", function()
        local ctx = test_helpers.create_context()

        ctx:execute(function()
            cargo.install("my-crate", "1.0.0")
        end)

        assert.spy(ctx.spawn.cargo).was_called(1)
        assert.spy(ctx.spawn.cargo).was_called_with {
            "install",
            "--root",
            ".",
            { "--version", "1.0.0" },
            vim.NIL, -- features
            vim.NIL, -- locked
            "my-crate",
        }
    end)

    it("should write output", function()
        local ctx = test_helpers.create_context()
        spy.on(ctx.stdio_sink, "stdout")

        ctx:execute(function()
            cargo.install("my-crate", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing crate my-crate@1.0.0…\n")
    end)

    it("should install locked", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            cargo.install("my-crate", "1.0.0", {
                locked = true,
            })
        end)

        assert.spy(ctx.spawn.cargo).was_called(1)
        assert.spy(ctx.spawn.cargo).was_called_with {
            "install",
            "--root",
            ".",
            { "--version", "1.0.0" },
            vim.NIL, -- features
            "--locked", -- locked
            "my-crate",
        }
    end)

    it("should install provided features", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            cargo.install("my-crate", "1.0.0", {
                features = "lsp,cli",
            })
        end)

        assert.spy(ctx.spawn.cargo).was_called(1)
        assert.spy(ctx.spawn.cargo).was_called_with {
            "install",
            "--root",
            ".",
            { "--version", "1.0.0" },
            { "--features", "lsp,cli" }, -- features
            vim.NIL, -- locked
            "my-crate",
        }
    end)

    it("should install git tag source", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            cargo.install("my-crate", "1.0.0", {
                git = {
                    url = "https://github.com/neovim/neovim",
                },
            })
        end)

        assert.spy(ctx.spawn.cargo).was_called(1)
        assert.spy(ctx.spawn.cargo).was_called_with {
            "install",
            "--root",
            ".",
            { "--git", "https://github.com/neovim/neovim", "--tag", "1.0.0" },
            vim.NIL, -- features
            vim.NIL, -- locked
            "my-crate",
        }
    end)

    it("should install git rev source", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            cargo.install("my-crate", "16dfc89abd413c391e5b63ae5d132c22843ce9a7", {
                git = {
                    url = "https://github.com/neovim/neovim",
                    rev = true,
                },
            })
        end)

        assert.spy(ctx.spawn.cargo).was_called(1)
        assert.spy(ctx.spawn.cargo).was_called_with {
            "install",
            "--root",
            ".",
            { "--git", "https://github.com/neovim/neovim", "--rev", "16dfc89abd413c391e5b63ae5d132c22843ce9a7" },
            vim.NIL, -- features
            vim.NIL, -- locked
            "my-crate",
        }
    end)
end)
