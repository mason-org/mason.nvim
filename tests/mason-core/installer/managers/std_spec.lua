local match = require "luassert.match"
local std = require "mason-core.installer.managers.std"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

describe("std unpack [Unix]", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should unpack .gz", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            std.unpack "file.gz"
        end)

        assert.spy(ctx.spawn.gzip).was_called(1)
        assert.spy(ctx.spawn.gzip).was_called_with { "-d", "file.gz" }
    end)

    describe("tar", function()
        before_each(function()
            stub(vim.fn, "executable")
            vim.fn.executable.on_call_with("gtar").returns(0)
        end)

        it("should use gtar if available", function()
            local ctx = test_helpers.create_context()
            stub(ctx.fs, "unlink")
            stub(vim.fn, "executable")
            vim.fn.executable.on_call_with("gtar").returns(1)

            ctx:execute(function()
                std.unpack "file.tar.gz"
            end)

            assert.spy(ctx.spawn.gtar).was_called(1)
            assert.spy(ctx.spawn.gtar).was_called_with { "--no-same-owner", "-xvf", "file.tar.gz" }
        end)

        it("should unpack .tar", function()
            local ctx = test_helpers.create_context()
            stub(ctx.fs, "unlink")
            ctx:execute(function()
                std.unpack "file.tar"
            end)

            assert.spy(ctx.spawn.tar).was_called(1)
            assert.spy(ctx.spawn.tar).was_called_with { "--no-same-owner", "-xvf", "file.tar" }
            assert.spy(ctx.fs.unlink).was_called(1)
            assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.tar")
        end)

        it("should unpack .tar.bz2", function()
            local ctx = test_helpers.create_context()
            stub(ctx.fs, "unlink")
            ctx:execute(function()
                std.unpack "file.tar.bz2"
            end)

            assert.spy(ctx.spawn.tar).was_called(1)
            assert.spy(ctx.spawn.tar).was_called_with { "--no-same-owner", "-xvf", "file.tar.bz2" }
            assert.spy(ctx.fs.unlink).was_called(1)
            assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.tar.bz2")
        end)

        it("should unpack .tar.gz", function()
            local ctx = test_helpers.create_context()
            stub(ctx.fs, "unlink")
            ctx:execute(function()
                std.unpack "file.tar.gz"
            end)

            assert.spy(ctx.spawn.tar).was_called(1)
            assert.spy(ctx.spawn.tar).was_called_with { "--no-same-owner", "-xvf", "file.tar.gz" }
            assert.spy(ctx.fs.unlink).was_called(1)
            assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.tar.gz")
        end)

        it("should unpack .tar.xz", function()
            local ctx = test_helpers.create_context()
            stub(ctx.fs, "unlink")
            ctx:execute(function()
                std.unpack "file.tar.xz"
            end)

            assert.spy(ctx.spawn.tar).was_called(1)
            assert.spy(ctx.spawn.tar).was_called_with { "--no-same-owner", "-xvf", "file.tar.xz" }
            assert.spy(ctx.fs.unlink).was_called(1)
            assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.tar.xz")
        end)

        it("should unpack .tar.zst", function()
            local ctx = test_helpers.create_context()
            stub(ctx.fs, "unlink")
            ctx:execute(function()
                std.unpack "file.tar.zst"
            end)

            assert.spy(ctx.spawn.tar).was_called(1)
            assert.spy(ctx.spawn.tar).was_called_with { "--no-same-owner", "-xvf", "file.tar.zst" }
            assert.spy(ctx.fs.unlink).was_called(1)
            assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.tar.zst")
        end)
    end)

    it("should unpack .vsix", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "unlink")
        ctx:execute(function()
            std.unpack "file.vsix"
        end)

        assert.spy(ctx.spawn.unzip).was_called(1)
        assert.spy(ctx.spawn.unzip).was_called_with { "-d", ".", "file.vsix" }
        assert.spy(ctx.fs.unlink).was_called(1)
        assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.vsix")
    end)

    it("should unpack .zip", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "unlink")
        ctx:execute(function()
            std.unpack "file.zip"
        end)

        assert.spy(ctx.spawn.unzip).was_called(1)
        assert.spy(ctx.spawn.unzip).was_called_with { "-d", ".", "file.zip" }
        assert.spy(ctx.fs.unlink).was_called(1)
        assert.spy(ctx.fs.unlink).was_called_with(match.is_ref(ctx.fs), "file.zip")
    end)
end)

describe("std clone", function()
    it("should clone", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            std.clone "https://github.com/mason-org/mason.nvim"
        end)

        assert.spy(ctx.spawn.git).was_called(1)
        assert.spy(ctx.spawn.git).was_called_with {
            "clone",
            "--depth",
            "1",
            vim.NIL, -- recursive
            "https://github.com/mason-org/mason.nvim",
            ".",
        }
    end)

    it("should clone and checkout rev", function()
        local ctx = test_helpers.create_context()
        ctx:execute(function()
            std.clone("https://github.com/mason-org/mason.nvim", {
                rev = "e1fd03b1856cb5ad8425f49e18353dc524b02f91",
                recursive = true,
            })
        end)

        assert.spy(ctx.spawn.git).was_called(3)
        assert.spy(ctx.spawn.git).was_called_with {
            "clone",
            "--depth",
            "1",
            "--recursive",
            "https://github.com/mason-org/mason.nvim",
            ".",
        }
        assert
            .spy(ctx.spawn.git)
            .was_called_with { "fetch", "--depth", "1", "origin", "e1fd03b1856cb5ad8425f49e18353dc524b02f91" }
        assert.spy(ctx.spawn.git).was_called_with { "checkout", "--quiet", "FETCH_HEAD" }
    end)
end)
