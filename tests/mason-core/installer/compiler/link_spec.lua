local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local fs = require "mason-core.fs"
local link = require "mason-core.installer.compiler.link"
local match = require "luassert.match"
local path = require "mason-core.path"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

describe("registry linker", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should expand bin table", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        stub(ctx.fs, "chmod")
        stub(ctx.fs, "fstat")

        ctx.fs.file_exists.on_call_with(match.is_ref(ctx.fs), "exec.sh").returns(true)
        ctx.fs.fstat.on_call_with(match.is_ref(ctx.fs), "exec.sh").returns {
            mode = 493, -- 0755
        }

        local result = link.bin(
            ctx,
            {
                bin = {
                    ["exec"] = "exec.sh",
                },
            },
            Purl.parse("pkg:dummy/package@v1.0.0"):get_or_throw(),
            {
                metadata = "value",
            }
        )

        assert.same(
            Result.success {
                ["exec"] = "exec.sh",
            },
            result
        )
        assert.same({
            ["exec"] = "exec.sh",
        }, ctx.links.bin)

        assert.spy(ctx.fs.chmod).was_not_called()
    end)

    it("should chmod executable if necessary", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        stub(ctx.fs, "chmod")
        stub(ctx.fs, "fstat")

        ctx.fs.file_exists.on_call_with(match.is_ref(ctx.fs), "exec.sh").returns(true)
        ctx.fs.fstat.on_call_with(match.is_ref(ctx.fs), "exec.sh").returns {
            mode = 420, -- 0644
        }

        local result = link.bin(
            ctx,
            {
                bin = {
                    ["exec"] = "exec.sh",
                },
            },
            Purl.parse("pkg:dummy/package@v1.0.0"):get_or_throw(),
            {
                metadata = "value",
            }
        )

        assert.is_true(result:is_success())
        assert.spy(ctx.fs.chmod).was_called(1)
        assert.spy(ctx.fs.chmod).was_called_with(match.is_ref(ctx.fs), "exec.sh", 493)
    end)

    it("should interpolate bin table", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        stub(ctx.fs, "chmod")
        stub(ctx.fs, "fstat")

        ctx.fs.file_exists.on_call_with(match.is_ref(ctx.fs), "v1.0.0-exec.sh").returns(true)
        ctx.fs.fstat.on_call_with(match.is_ref(ctx.fs), "v1.0.0-exec.sh").returns {
            mode = 493, -- 0755
        }

        local result = link.bin(
            ctx,
            {
                bin = {
                    ["exec"] = "{{version}}-{{source.script}}",
                },
            },
            Purl.parse("pkg:dummy/package@v1.0.0"):get_or_throw(),
            {
                script = "exec.sh",
            }
        )

        assert.same(
            Result.success {
                ["exec"] = "v1.0.0-exec.sh",
            },
            result
        )
    end)

    it("should delegate bin paths", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        stub(ctx.fs, "chmod")
        stub(ctx.fs, "fstat")

        local matrix = {
            ["cargo:executable"] = "bin/executable",
            ["composer:executable"] = "vendor/bin/executable",
            ["golang:executable"] = "executable",
            ["luarocks:executable"] = "bin/executable",
            ["npm:executable"] = "node_modules/.bin/executable",
            ["nuget:executable"] = "executable",
            ["opam:executable"] = "bin/executable",
            -- ["pypi:executable"] = "venv/bin/executable",
        }

        for bin, path in pairs(matrix) do
            ctx.fs.file_exists.on_call_with(match.is_ref(ctx.fs), path).returns(true)
            ctx.fs.fstat.on_call_with(match.is_ref(ctx.fs), path).returns {
                mode = 493, -- 0755
            }

            local result = link.bin(ctx, {
                bin = {
                    ["executable"] = bin,
                },
            }, Purl.parse("pkg:dummy/package@v1.0.0"):get_or_throw(), {})

            assert.same(
                Result.success {
                    ["executable"] = path,
                },
                result
            )
        end
    end)

    it("should register share links", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        stub(fs.sync, "file_exists")
        stub(vim.fn, "glob")

        vim.fn.glob.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0/dir/" } .. "**/*", false, true).returns {
            path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file1" },
            path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file2" },
            path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file3" },
        }
        fs.sync.file_exists.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file1" }).returns(true)
        fs.sync.file_exists.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file2" }).returns(true)
        fs.sync.file_exists.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file3" }).returns(true)

        local result = link.share(
            ctx,
            {
                share = {
                    ["file"] = "{{version}}-{{source.file}}",
                    ["dir/"] = "{{version}}/dir/",
                    ["empty/"] = "{{source.empty}}",
                },
            },
            Purl.parse("pkg:dummy/package@v1.0.0"):get_or_throw(),
            {
                file = "file",
            }
        )

        assert.same(
            Result.success {
                ["file"] = "v1.0.0-file",
                ["dir/file1"] = "v1.0.0/dir/file1",
                ["dir/file2"] = "v1.0.0/dir/file2",
                ["dir/file3"] = "v1.0.0/dir/file3",
            },
            result
        )

        assert.same({
            ["file"] = "v1.0.0-file",
            ["dir/file1"] = "v1.0.0/dir/file1",
            ["dir/file2"] = "v1.0.0/dir/file2",
            ["dir/file3"] = "v1.0.0/dir/file3",
        }, ctx.links.share)
    end)

    it("should register opt links", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        stub(fs.sync, "file_exists")
        stub(vim.fn, "glob")

        vim.fn.glob.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0/dir/" } .. "**/*", false, true).returns {
            path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file1" },
            path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file2" },
            path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file3" },
        }
        fs.sync.file_exists.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file1" }).returns(true)
        fs.sync.file_exists.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file2" }).returns(true)
        fs.sync.file_exists.on_call_with(path.concat { ctx.cwd:get(), "v1.0.0", "dir", "file3" }).returns(true)

        local result = link.opt(
            ctx,
            {
                opt = {
                    ["file"] = "{{version}}-{{source.file}}",
                    ["dir/"] = "{{version}}/dir/",
                    ["empty/"] = "{{source.empty}}",
                },
            },
            Purl.parse("pkg:dummy/package@v1.0.0"):get_or_throw(),
            {
                file = "file",
            }
        )

        assert.same(
            Result.success {
                ["file"] = "v1.0.0-file",
                ["dir/file1"] = "v1.0.0/dir/file1",
                ["dir/file2"] = "v1.0.0/dir/file2",
                ["dir/file3"] = "v1.0.0/dir/file3",
            },
            result
        )

        assert.same({
            ["file"] = "v1.0.0-file",
            ["dir/file1"] = "v1.0.0/dir/file1",
            ["dir/file2"] = "v1.0.0/dir/file2",
            ["dir/file3"] = "v1.0.0/dir/file3",
        }, ctx.links.opt)
    end)
end)
