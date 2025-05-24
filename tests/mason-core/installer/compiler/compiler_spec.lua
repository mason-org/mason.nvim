local Result = require "mason-core.result"
local compiler = require "mason-core.installer.compiler"
local match = require "luassert.match"
local spy = require "luassert.spy"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"
local util = require "mason-core.installer.compiler.util"

---@type InstallerCompiler
local dummy_compiler = {
    ---@param source RegistryPackageSource
    ---@param purl Purl
    ---@param opts PackageInstallOpts
    parse = function(source, purl, opts)
        return Result.try(function(try)
            if source.supported_platforms then
                try(util.ensure_valid_platform(source.supported_platforms))
            end
            return {
                package = purl.name,
                extra_info = source.extra_info,
                should_fail = source.should_fail,
            }
        end)
    end,
    install = function(ctx, source)
        if source.should_fail then
            return Result.failure "This is a failure."
        else
            return Result.success()
        end
    end,
    get_versions = function()
        return Result.success { "v1.0.0", "v2.0.0" }
    end,
}

describe("registry compiler :: parsing", function()
    it("should parse valid package specs", function()
        compiler.register_compiler("dummy", dummy_compiler)

        local result = compiler.parse({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
                extra_info = "here",
            },
        }, {})
        local parsed = result:get_or_nil()

        assert.is_true(result:is_success())
        assert.is_true(match.is_ref(dummy_compiler)(parsed.compiler))
        assert.same({
            name = "package-name",
            scheme = "pkg",
            type = "dummy",
            version = "v1.2.3",
        }, parsed.purl)
        assert.same({
            id = "pkg:dummy/package-name@v1.2.3",
            package = "package-name",
            extra_info = "here",
        }, parsed.source)
    end)

    it("should keep unmapped fields", function()
        compiler.register_compiler("dummy", dummy_compiler)

        local result = compiler.parse({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
                bin = "node:server.js",
            },
        }, {})
        local parsed = result:get_or_nil()

        assert.is_true(result:is_success())
        assert.same({
            id = "pkg:dummy/package-name@v1.2.3",
            package = "package-name",
            bin = "node:server.js",
        }, parsed.source)
    end)

    it("should reject incompatible schema versions", function()
        compiler.register_compiler("dummy", dummy_compiler)

        local result = compiler.parse({
            schema = "registry+v1337",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
            },
        }, {})
        assert.same(
            Result.failure [[Current version of mason.nvim is not capable of parsing package schema version "registry+v1337".]],
            result
        )
    end)

    it("should use requested version", function()
        compiler.register_compiler("dummy", dummy_compiler)

        local result = compiler.parse({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
            },
        }, { version = "v2.0.0" })

        assert.is_true(result:is_success())
        local parsed = result:get_or_nil()

        assert.same({
            name = "package-name",
            scheme = "pkg",
            type = "dummy",
            version = "v2.0.0",
        }, parsed.purl)
    end)

    it("should handle PLATFORM_UNSUPPORTED", function()
        compiler.register_compiler("dummy", dummy_compiler)

        local result = compiler.compile_installer({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
                supported_platforms = { "VIC64" },
            },
        }, { version = "v2.0.0" })

        assert.same(Result.failure "The current platform is unsupported.", result)
    end)

    it("should error upon parsing failures", function()
        compiler.register_compiler("dummy", dummy_compiler)

        local result = compiler.compile_installer({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
                supported_platforms = { "VIC64" },
            },
        }, { version = "v2.0.0" })

        assert.same(Result.failure "The current platform is unsupported.", result)
    end)
end)

describe("registry compiler :: compiling", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should run compiled installer function successfully", function()
        compiler.register_compiler("dummy", dummy_compiler)
        spy.on(dummy_compiler, "get_versions")

        ---@type PackageInstallOpts
        local opts = {}

        local result = compiler.compile_installer({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
            },
        }, opts)

        assert.is_true(result:is_success())
        local installer_fn = result:get_or_throw()

        local ctx = test_helpers.create_context()
        local installer_result = ctx:execute(installer_fn)

        assert.same(Result.success(), installer_result)
        assert.spy(dummy_compiler.get_versions).was_not_called()
    end)

    it("should ensure valid version", function()
        compiler.register_compiler("dummy", dummy_compiler)
        spy.on(dummy_compiler, "get_versions")

        ---@type PackageInstallOpts
        local opts = { version = "v2.0.0" }

        local result = compiler.compile_installer({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
            },
        }, opts)

        assert.is_true(result:is_success())
        local installer_fn = result:get_or_throw()

        local ctx = test_helpers.create_context { install_opts = opts }
        local installer_result = ctx:execute(installer_fn)
        assert.same(Result.success(), installer_result)

        assert.spy(dummy_compiler.get_versions).was_called(1)
        assert.spy(dummy_compiler.get_versions).was_called_with({
            name = "package-name",
            scheme = "pkg",
            type = "dummy",
            version = "v2.0.0",
        }, {
            id = "pkg:dummy/package-name@v1.2.3",
        })
    end)

    it("should reject invalid version", function()
        compiler.register_compiler("dummy", dummy_compiler)
        spy.on(dummy_compiler, "get_versions")

        ---@type PackageInstallOpts
        local opts = { version = "v13.3.7" }

        local result = compiler.compile_installer({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
            },
        }, opts)

        assert.is_true(result:is_success())
        local installer_fn = result:get_or_throw()

        local ctx = test_helpers.create_context { install_opts = opts }
        local err = assert.has_error(function()
            ctx:execute(installer_fn):get_or_throw()
        end)

        assert.equals([[Version "v13.3.7" is not available.]], err)
        assert.spy(dummy_compiler.get_versions).was_called(1)
        assert.spy(dummy_compiler.get_versions).was_called_with({
            name = "package-name",
            scheme = "pkg",
            type = "dummy",
            version = "v13.3.7",
        }, {
            id = "pkg:dummy/package-name@v1.2.3",
        })
    end)

    it("should raise errors upon installer failures", function()
        compiler.register_compiler("dummy", dummy_compiler)

        ---@type PackageInstallOpts
        local opts = {}

        local result = compiler.compile_installer({
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
                should_fail = true,
            },
        }, opts)

        assert.is_true(result:is_success())
        local installer_fn = result:get_or_nil()

        local ctx = test_helpers.create_context()
        local err = assert.has_error(function()
            ctx:execute(installer_fn):get_or_throw()
        end)
        assert.equals("This is a failure.", err)
    end)

    it("should register links", function()
        compiler.register_compiler("dummy", dummy_compiler)
        local link = require "mason-core.installer.compiler.link"
        stub(link, "bin", mockx.returns(Result.success()))
        stub(link, "share", mockx.returns(Result.success()))
        stub(link, "opt", mockx.returns(Result.success()))

        local spec = {
            schema = "registry+v1",
            source = {
                id = "pkg:dummy/package-name@v1.2.3",
            },
            bin = { ["exec"] = "exec" },
            opt = { ["opt/"] = "opt/" },
            share = { ["share/"] = "share/" },
        }
        ---@type PackageInstallOpts
        local opts = {}

        local result = compiler.compile_installer(spec, opts)

        assert.is_true(result:is_success())
        local installer_fn = result:get_or_nil()

        local ctx = test_helpers.create_context()
        local installer_result = ctx:execute(installer_fn)
        assert.is_true(installer_result:is_success())

        for _, spy in ipairs { link.bin, link.share, link.opt } do
            assert.spy(spy).was_called(1)
            assert.spy(spy).was_called_with(match.is_ref(ctx), spec, {
                scheme = "pkg",
                type = "dummy",
                name = "package-name",
                version = "v1.2.3",
            }, {
                id = "pkg:dummy/package-name@v1.2.3",
                package = "package-name",
            })
        end
    end)
end)
