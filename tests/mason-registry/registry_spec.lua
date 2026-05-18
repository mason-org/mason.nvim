local Pkg = require "mason-core.package"
local match = require "luassert.match"
local registry = require "mason-registry"
local spy = require "luassert.spy"
local test_helpers = require "mason-test.helpers"

describe("mason-registry", function()
    it("should return package", function()
        assert.is_true(getmetatable(registry.get_package "dummy").__index == Pkg)
    end)

    it("should error when getting non-existent package", function()
        local err = assert.has_error(function()
            registry.get_package "non-existent"
        end)
        assert.equals([[Cannot find package "non-existent".]], err)
    end)

    it("should check whether package exists", function()
        assert.is_true(registry.has_package "dummy")
        assert.is_false(registry.has_package "non-existent")
    end)

    it("should get all package specs", function()
        assert.equals(3, #registry.get_all_package_specs())
    end)

    it("should check if package is installed", function()
        local dummy = registry.get_package "dummy"
        -- TODO unflake this in a better way
        if dummy:is_installed() then
            test_helpers.sync_uninstall(dummy)
        end
        assert.is_false(registry.is_installed "dummy")
        test_helpers.sync_install(dummy)
        assert.is_true(registry.is_installed "dummy")
    end)

    describe("refresh/update", function()
        local a = require "mason-core.async"
        local settings = require "mason.settings"
        local installer = require "mason-registry.installer"

        after_each(function()
            settings.set(settings._DEFAULT_SETTINGS)
        end)

        it("should refresh registry synchronously", function()
            local ok, updated_registries = registry.refresh()
            assert.is_true(ok)
            assert.same({}, updated_registries)
        end)

        it("should call registry.refresh callback", function()
            local spy = spy.new()
            registry.refresh(spy)
            assert.wait(function()
                assert.spy(spy).was_called(1)
                assert.spy(spy).was_called_with(true, {})
            end)
        end)

        it("should call registry.update callback", function()
            local spy = spy.new()
            registry.update(spy)
            assert.wait(function()
                assert.spy(spy).was_called(1)
                assert.spy(spy).was_called_with(true, match.is_table())
            end)
        end)

        it("should immediately return if refresh is disabled", function()
            settings.current.registry_cache.refresh = false
            local ok, registries = registry.refresh()
            assert.is_true(ok)
            assert.same({}, registries)

            local spy = spy.new()
            registry.refresh(spy)
            assert.spy(spy).was_called(1)
            assert.spy(spy).was_called_with(true, {})
        end)
    end)
end)
