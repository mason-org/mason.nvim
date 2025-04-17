local Pkg = require "mason-core.package"
local a = require "mason-core.async"
local match = require "luassert.match"
local mock = require "luassert.mock"
local registry = require "mason-registry"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

describe("package", function()
    before_each(function()
        registry.get_package("dummy"):uninstall()
        package.loaded["dummy_package"] = nil
    end)

    it("should parse package specifiers", function()
        local function parse(str)
            local name, version = Pkg.Parse(str)
            return { name, version }
        end

        assert.same({ "rust-analyzer", nil }, parse "rust-analyzer")
        assert.same({ "rust-analyzer", "" }, parse "rust-analyzer@")
        assert.same({ "rust-analyzer", "nightly" }, parse "rust-analyzer@nightly")
    end)

    if vim.fn.has "nvim-0.11" == 1 then
        it("should validate spec", function()
            local valid_spec = {
                name = "Package name",
                desc = "Package description",
                homepage = "https://example.com",
                categories = { Pkg.Cat.LSP },
                languages = { Pkg.Lang.Rust },
                install = function() end,
            }
            local function spec(fields)
                return setmetatable(fields, { __index = valid_spec })
            end
            assert.equals(
                "name: expected string, got number",
                assert.has_error(function()
                    Pkg.new(spec { name = 23 })
                end)
            )

            assert.equals(
                "desc: expected string, got number",
                assert.has_error(function()
                    Pkg.new(spec { desc = 23 })
                end)
            )

            assert.equals(
                "homepage: expected string, got number",
                assert.has_error(function()
                    Pkg.new(spec { homepage = 23 })
                end)
            )

            assert.equals(
                "categories: expected table, got number",
                assert.has_error(function()
                    Pkg.new(spec { categories = 23 })
                end)
            )

            assert.equals(
                "languages: expected table, got number",
                assert.has_error(function()
                    Pkg.new(spec { languages = 23 })
                end)
            )

            assert.equals(
                "install: expected function, got number",
                assert.has_error(function()
                    Pkg.new(spec { install = 23 })
                end)
            )
        end)
    end

    it("should create new handle", function()
        local dummy = registry.get_package "dummy"
        -- yo dawg
        local handle_handler = spy.new()
        dummy:once("handle", handle_handler)
        local handle = dummy:new_handle()
        assert.spy(handle_handler).was_called(1)
        assert.spy(handle_handler).was_called_with(match.ref(handle))
        handle:close()
    end)

    it("should not create new handle if one already exists", function()
        local dummy = registry.get_package "dummy"
        dummy.handle = mock.new {
            is_closed = mockx.returns(false),
        }
        local handle_handler = spy.new()
        dummy:once("handle", handle_handler)
        local err = assert.has_error(function()
            dummy:new_handle()
        end)
        assert.equals("Cannot create new handle because existing handle is not closed.", err)
        assert.spy(handle_handler).was_called(0)
        dummy.handle = nil
    end)

    it(
        "should successfully install package",
        async_test(function()
            local dummy = registry.get_package "dummy"
            local package_install_success_handler = spy.new()
            local package_install_failed_handler = spy.new()
            local install_success_handler = spy.new()
            local install_failed_handler = spy.new()
            registry:once("package:install:success", package_install_success_handler)
            registry:once("package:install:failed", package_install_failed_handler)
            dummy:once("install:success", install_success_handler)
            dummy:once("install:failed", install_failed_handler)

            local handle = dummy:install { version = "1337" }

            assert.wait_for(function()
                assert.is_true(handle:is_closed())
                assert.is_true(dummy:is_installed())
            end)

            assert.spy(install_success_handler).was_called(1)
            assert.spy(install_success_handler).was_called_with(match.is_ref(handle))
            assert.spy(package_install_success_handler).was_called(1)
            assert.spy(package_install_success_handler).was_called_with(match.is_ref(dummy), match.is_ref(handle))
            assert.spy(package_install_failed_handler).was_called(0)
            assert.spy(install_failed_handler).was_called(0)
        end)
    )

    it(
        "should fail to install package",
        async_test(function()
            local dummy = registry.get_package "dummy"
            stub(dummy.spec, "install")
            dummy.spec.install.invokes(function()
                error "I simply refuse to be installed."
            end)
            local package_install_success_handler = spy.new()
            local package_install_failed_handler = spy.new()
            local install_success_handler = spy.new()
            local install_failed_handler = spy.new()
            registry:once("package:install:success", package_install_success_handler)
            registry:once("package:install:failed", package_install_failed_handler)
            dummy:once("install:success", install_success_handler)
            dummy:once("install:failed", install_failed_handler)

            local handle = dummy:install { version = "1337" }

            assert.wait_for(function()
                assert.is_true(handle:is_closed())
                assert.is_false(dummy:is_installed())
            end)

            assert.spy(install_failed_handler).was_called(1)
            assert.spy(install_failed_handler).was_called_with(match.is_ref(handle))
            assert.spy(package_install_failed_handler).was_called(1)
            assert.spy(package_install_failed_handler).was_called_with(match.is_ref(dummy), match.is_ref(handle))
            assert.spy(package_install_success_handler).was_called(0)
            assert.spy(install_success_handler).was_called(0)
        end)
    )

    it(
        "should be able to start package installation outside of main loop",
        async_test(function()
            local dummy = registry.get_package "dummy"

            -- Move outside the main loop
            a.wait(function(resolve)
                local timer = vim.loop.new_timer()
                timer:start(0, 0, function()
                    timer:close()
                    resolve()
                end)
            end)

            assert.is_true(vim.in_fast_event())

            local handle = assert.is_not.has_error(function()
                return dummy:install()
            end)

            assert.wait_for(function()
                assert.is_true(handle:is_closed())
            end)
        end)
    )

    it(
        "should be able to instantiate package outside of main loop",
        async_test(function()
            local dummy = registry.get_package "registry"

            -- Move outside the main loop
            a.wait(function(resolve)
                local timer = vim.loop.new_timer()
                timer:start(0, 0, function()
                    timer:close()
                    resolve()
                end)
            end)

            assert.is_true(vim.in_fast_event())

            local pkg = assert.is_not.has_error(function()
                return Pkg.new(dummy.spec)
            end)

            assert.same(dummy.spec, pkg.spec)
        end)
    )
end)
