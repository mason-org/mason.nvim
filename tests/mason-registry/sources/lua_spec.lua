local LuaRegistrySource = require "mason-registry.sources.lua"

describe("Lua registry source", function()
    it("should get package", function()
        local source = LuaRegistrySource:new {
            mod = "dummy-registry.index",
        }
        assert.is_true(source:install():is_success())
        assert.is_not_nil(source:get_package "dummy")
        assert.is_nil(source:get_package "non-existent")
    end)

    it("should get all package names", function()
        local source = LuaRegistrySource:new {
            mod = "dummy-registry.index",
        }
        assert.is_true(source:install():is_success())
        local package_names = source:get_all_package_names()
        table.sort(package_names)
        assert.same({
            "dummy",
            "dummy2",
            "registry",
        }, package_names)
    end)

    it("should check if is installed", function()
        local installed_source = LuaRegistrySource:new {
            mod = "dummy-registry.index",
        }
        local uninstalled_source = LuaRegistrySource:new {
            mod = "non-existent",
        }

        assert.is_true(installed_source:install():is_success())
        assert.is_true(installed_source:is_installed())
        assert.is_false(uninstalled_source:is_installed())
    end)

    it("should stringify instances", function()
        assert.equals("LuaRegistrySource(mod=pkg-index)", tostring(LuaRegistrySource:new { mod = "pkg-index" }))
    end)
end)
