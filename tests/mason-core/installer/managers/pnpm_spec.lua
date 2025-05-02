local Result = require "mason-core.result"
local installer = require "mason-core.installer"
local match = require "luassert.match"
local pnpm = require "mason-core.installer.managers.pnpm"
local spawn = require "mason-core.spawn"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

describe("pnpm manager", function()
    it("should init package.json", function()
        local ctx = create_dummy_context()
        stub(ctx.fs, "read_file")
        stub(ctx.fs, "write_file")
        stub(spawn, "pnpm")
        ctx.fs.read_file.returns '{"name": "my-package", "version": "1.0.0"}'
        spawn.pnpm.returns(Result.success {})
        installer.exec_in_context(ctx, function()
            pnpm.init()
        end)

        assert.spy(ctx.spawn.pnpm).was_called(1)
        assert.spy(ctx.spawn.pnpm).was_called_with { "init" }
        assert.spy(ctx.fs.read_file).was_called(1)
        assert.spy(ctx.fs.read_file).was_called_with(match.is_ref(ctx.fs), "package.json")
        assert.spy(ctx.fs.write_file).was_called(1)
        assert
            .spy(ctx.fs.write_file)
            .was_called_with(match.is_ref(ctx.fs), "package.json", match.has_match '"name":"@mason/my--package"')
    end)

    it("should install extra packages", function()
        local ctx = create_dummy_context()
        installer.exec_in_context(ctx, function()
            pnpm.install("my-package", "1.0.0", {
                extra_packages = { "extra-package" },
            })
        end)

        assert.spy(ctx.spawn.pnpm).was_called(1)
        assert.spy(ctx.spawn.pnpm).was_called_with {
            "add",
            "my-package@1.0.0",
            { "extra-package" },
        }
    end)
end)
