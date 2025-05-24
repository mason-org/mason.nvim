local a = require "mason-core.async"
local fs = require "mason-core.fs"
local path = require "mason-core.path"
local registry = require "mason-registry"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

local WIN_CMD_SCRIPT = [[@ECHO off
GOTO start
:find_dp0
SET dp0=%%~dp0
EXIT /b
:start
SETLOCAL
CALL :find_dp0

endLocal & goto #_undefined_# 2>NUL || title %%COMSPEC%% & "%%dp0%%\%s" %%*]]

describe("linker", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    ---@module "mason-core.installer.linker"
    local linker
    ---@module "mason-core.platform"
    local platform

    before_each(function()
        package.loaded["mason-core.platform"] = nil
        package.loaded["mason-core.installer.linker"] = nil
        platform = require "mason-core.platform"
        linker = require "mason-core.installer.linker"
    end)

    it("should symlink executable on Unix", function()
        local ctx = test_helpers.create_context()

        stub(fs.async, "file_exists")
        stub(fs.async, "symlink")
        stub(fs.async, "write_file")

        fs.async.file_exists.on_call_with(ctx.location:bin "my-executable").returns(false)
        fs.async.file_exists.on_call_with(ctx.location:bin "another-executable").returns(false)
        fs.async.file_exists
            .on_call_with(path.concat { ctx:get_install_path(), "nested", "path", "my-executable" })
            .returns(true)
        fs.async.file_exists.on_call_with(path.concat { ctx:get_install_path(), "another-executable" }).returns(true)

        ctx:link_bin("my-executable", path.concat { "nested", "path", "my-executable" })
        ctx:link_bin("another-executable", "another-executable")
        local result = a.run_blocking(linker.link, ctx)
        assert.is_true(result:is_success())

        assert.spy(fs.async.write_file).was_called(0)
        assert.spy(fs.async.symlink).was_called(2)
        assert
            .spy(fs.async.symlink)
            .was_called_with("../packages/dummy/another-executable", ctx.location:bin "another-executable")
        assert
            .spy(fs.async.symlink)
            .was_called_with("../packages/dummy/nested/path/my-executable", ctx.location:bin "my-executable")
    end)

    it("should write executable wrapper on Windows", function()
        local ctx = test_helpers.create_context()

        platform.is.darwin = false
        platform.is.mac = false
        platform.is.linux = false
        platform.is.unix = false
        platform.is.win = true

        stub(fs.async, "file_exists")
        stub(fs.async, "symlink")
        stub(fs.async, "write_file")

        fs.async.file_exists.on_call_with(ctx.location:bin "my-executable").returns(false)
        fs.async.file_exists.on_call_with(ctx.location:bin "another-executable").returns(false)
        fs.async.file_exists
            .on_call_with(path.concat { ctx:get_install_path(), "nested", "path", "my-executable" })
            .returns(true)
        fs.async.file_exists.on_call_with(path.concat { ctx:get_install_path(), "another-executable" }).returns(true)

        ctx:link_bin("my-executable", path.concat { "nested", "path", "my-executable" })
        ctx:link_bin("another-executable", "another-executable")

        local result = a.run_blocking(linker.link, ctx)
        assert.is_true(result:is_success())

        assert.spy(fs.async.symlink).was_called(0)
        assert.spy(fs.async.write_file).was_called(2)
        assert
            .spy(fs.async.write_file)
            .was_called_with(ctx.location:bin "another-executable.cmd", WIN_CMD_SCRIPT:format "..\\packages\\dummy\\another-executable")
        assert
            .spy(fs.async.write_file)
            .was_called_with(
                ctx.location:bin "my-executable.cmd",
                WIN_CMD_SCRIPT:format "..\\packages\\dummy\\nested\\path\\my-executable"
            )
    end)

    it("should symlink share files", function()
        local ctx = test_helpers.create_context()

        stub(fs.async, "mkdirp")
        stub(fs.async, "dir_exists")
        stub(fs.async, "file_exists")
        stub(fs.async, "symlink")
        stub(fs.async, "write_file")

        -- mock non-existent dest files
        fs.async.file_exists.on_call_with(ctx.location:share "share-file").returns(false)
        fs.async.file_exists.on_call_with(ctx.location:share(path.concat { "nested", "share-file" })).returns(false)

        fs.async.dir_exists.on_call_with(ctx.location:share "nested/path").returns(false)

        -- mock existent source files
        fs.async.file_exists.on_call_with(path.concat { ctx:get_install_path(), "share-file" }).returns(true)
        fs.async.file_exists
            .on_call_with(path.concat { ctx:get_install_path(), "nested", "path", "to", "share-file" })
            .returns(true)

        ctx.links.share["nested/path/share-file"] = path.concat { "nested", "path", "to", "share-file" }
        ctx.links.share["share-file"] = "share-file"

        local result = a.run_blocking(linker.link, ctx)

        assert.is_true(result:is_success())

        assert.spy(fs.async.write_file).was_called(0)
        assert.spy(fs.async.symlink).was_called(2)
        assert.spy(fs.async.symlink).was_called_with("../packages/dummy/share-file", ctx.location:share "share-file")
        assert
            .spy(fs.async.symlink)
            .was_called_with("../../../packages/dummy/nested/path/to/share-file", ctx.location:share "nested/path/share-file")

        assert.spy(fs.async.mkdirp).was_called(2)
        assert.spy(fs.async.mkdirp).was_called_with(ctx.location:share "nested/path")
    end)

    it("should copy share files on Windows", function()
        local ctx = test_helpers.create_context()

        platform.is.darwin = false
        platform.is.mac = false
        platform.is.linux = false
        platform.is.unix = false
        platform.is.win = true

        stub(fs.async, "mkdirp")
        stub(fs.async, "dir_exists")
        stub(fs.async, "file_exists")
        stub(fs.async, "copy_file")

        -- mock non-existent dest files
        fs.async.file_exists.on_call_with(ctx.location:share "share-file").returns(false)
        fs.async.file_exists.on_call_with(ctx.location:share(path.concat { "nested", "share-file" })).returns(false)

        fs.async.dir_exists.on_call_with(ctx.location:share "nested/path").returns(false)

        -- mock existent source files
        fs.async.file_exists.on_call_with(path.concat { ctx:get_install_path(), "share-file" }).returns(true)
        fs.async.file_exists
            .on_call_with(path.concat { ctx:get_install_path(), "nested", "path", "to", "share-file" })
            .returns(true)

        ctx.links.share["nested/path/share-file"] = path.concat { "nested", "path", "to", "share-file" }
        ctx.links.share["share-file"] = "share-file"

        local result = linker.link(ctx)

        assert.is_true(result:is_success())

        assert.spy(fs.async.copy_file).was_called(2)
        assert
            .spy(fs.async.copy_file)
            .was_called_with(path.concat { ctx:get_install_path(), "share-file" }, ctx.location:share "share-file", { excl = true })
        assert.spy(fs.async.copy_file).was_called_with(
            path.concat { ctx:get_install_path(), "nested", "path", "to", "share-file" },
            ctx.location:share "nested/path/share-file",
            { excl = true }
        )

        assert.spy(fs.async.mkdirp).was_called(2)
        assert.spy(fs.async.mkdirp).was_called_with(ctx.location:share "nested/path")
    end)
end)
