local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local common = require "mason-core.installer.managers.common"
local installer = require "mason-core.installer"
local match = require "luassert.match"
local mock = require "luassert.mock"
local spy = require "luassert.spy"
local std = require "mason-core.installer.managers.std"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

describe("common manager :: download", function()
    it("should parse download files from common structure", function()
        local url_generator = _.format "https://example.com/%s"

        assert.same(
            {
                {
                    download_url = "https://example.com/abc.jar",
                    out_file = "abc.jar",
                },
            },
            common.parse_downloads({
                file = "abc.jar",
            }, url_generator)
        )

        assert.same(
            {
                {
                    download_url = "https://example.com/abc.jar",
                    out_file = "lib/abc.jar",
                },
            },
            common.parse_downloads({
                file = "abc.jar:lib/",
            }, url_generator)
        )

        assert.same(
            {
                {
                    download_url = "https://example.com/abc.jar",
                    out_file = "lib/abc.jar",
                },
                {
                    download_url = "https://example.com/file.jar",
                    out_file = "lib/nested/new-name.jar",
                },
            },
            common.parse_downloads({
                file = { "abc.jar:lib/", "file.jar:lib/nested/new-name.jar" },
            }, url_generator)
        )
    end)

    it("should download files", function()
        local ctx = test_helpers.create_context()
        stub(std, "download_file", mockx.returns(Result.success()))
        stub(std, "unpack", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return common.download_files(ctx, {
                { out_file = "file.jar", download_url = "https://example.com/file.jar" },
                { out_file = "LICENSE.md", download_url = "https://example.com/LICENSE" },
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(std.download_file).was_called(2)
        assert.spy(std.download_file).was_called_with("https://example.com/file.jar", "file.jar")
        assert.spy(std.download_file).was_called_with("https://example.com/LICENSE", "LICENSE.md")
        assert.spy(std.unpack).was_called(2)
        assert.spy(std.unpack).was_called_with "file.jar"
        assert.spy(std.unpack).was_called_with "LICENSE.md"
    end)

    it("should download files to specified directory", function()
        local ctx = test_helpers.create_context()
        stub(std, "download_file", mockx.returns(Result.success()))
        stub(std, "unpack", mockx.returns(Result.success()))
        stub(ctx.fs, "mkdirp")

        local result = ctx:execute(function()
            return common.download_files(ctx, {
                { out_file = "lib/file.jar", download_url = "https://example.com/file.jar" },
                { out_file = "doc/LICENSE.md", download_url = "https://example.com/LICENSE" },
                { out_file = "nested/path/to/file", download_url = "https://example.com/some-file" },
            })
        end)

        assert.is_true(result:is_success())

        assert.spy(ctx.fs.mkdirp).was_called(3)
        assert.spy(ctx.fs.mkdirp).was_called_with(match.is_ref(ctx.fs), "lib")
        assert.spy(ctx.fs.mkdirp).was_called_with(match.is_ref(ctx.fs), "doc")
        assert.spy(ctx.fs.mkdirp).was_called_with(match.is_ref(ctx.fs), "nested/path/to")
    end)
end)

describe("common manager :: build", function()
    it("should run build instruction", function()
        local ctx = test_helpers.create_context()
        local uv = require "mason-core.async.uv"
        spy.on(ctx, "promote_cwd")
        stub(uv, "write")
        stub(uv, "shutdown")
        stub(uv, "close")
        local stdin = mock.new()
        stub(
            ctx.spawn,
            "bash", ---@param args SpawnArgs
            function(args)
                args.on_spawn(mock.new(), { stdin })
                return Result.success()
            end
        )

        local result = ctx:execute(function()
            return common.run_build_instruction {
                run = [[npm install && npm run compile]],
                env = {
                    MASON_VERSION = "2023-03-09",
                    SOME_VALUE = "here",
                },
            }
        end)

        assert.is_true(result:is_success())
        assert.spy(ctx.promote_cwd).was_called(0)
        assert.spy(ctx.spawn.bash).was_called(1)
        assert.spy(ctx.spawn.bash).was_called_with(match.tbl_containing {
            on_spawn = match.is_function(),
            env = match.same {
                MASON_VERSION = "2023-03-09",
                SOME_VALUE = "here",
            },
        })
        assert.spy(uv.write).was_called(2)
        assert.spy(uv.write).was_called_with(stdin, "set -euxo pipefail;\n")
        assert.spy(uv.write).was_called_with(stdin, "npm install && npm run compile")
        assert.spy(uv.shutdown).was_called_with(stdin)
        assert.spy(uv.close).was_called_with(stdin)
    end)

    it("should promote cwd if not staged", function()
        local ctx = test_helpers.create_context()
        stub(ctx, "promote_cwd")
        stub(ctx.spawn, "bash", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return common.run_build_instruction {
                run = "make",
                staged = false,
            }
        end)

        assert.is_true(result:is_success())
        assert.spy(ctx.promote_cwd).was_called(1)
        assert.spy(ctx.spawn.bash).was_called(1)
    end)
end)
