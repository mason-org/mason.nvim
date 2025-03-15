local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local api = require "mason-registry.api"
local gem = require "mason-core.managers.gem"
local installer = require "mason-core.installer"
local match = require "luassert.match"
local mock = require "luassert.mock"
local spawn = require "mason-core.spawn"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

describe("gem manager", function()
    it(
        "should call gem install",
        async_test(function()
            local handle = InstallHandleGenerator "dummy"
            local ctx = InstallContextGenerator(handle, { version = "42.13.37" })
            installer.prepare_installer(ctx):get_or_throw()
            installer.exec_in_context(ctx, gem.packages { "main-package", "supporting-package", "supporting-package2" })
            assert.spy(ctx.spawn.gem).was_called(1)
            assert.spy(ctx.spawn.gem).was_called_with(match.tbl_containing {
                "install",
                "--no-user-install",
                "--no-format-executable",
                "--env-shebang",
                "--install-dir=.",
                "--bindir=bin",
                "--no-document",
                match.tbl_containing {
                    "main-package:42.13.37",
                    "supporting-package",
                    "supporting-package2",
                },
            })
        end)
    )

    it(
        "should provide receipt information",
        async_test(function()
            local handle = InstallHandleGenerator "dummy"
            local ctx = InstallContextGenerator(handle, { version = "42.13.37" })
            installer.prepare_installer(ctx):get_or_throw()
            installer.exec_in_context(ctx, gem.packages { "main-package", "supporting-package", "supporting-package2" })
            assert.same({
                type = "gem",
                package = "main-package",
            }, ctx.receipt.primary_source)
            assert.same({
                {
                    type = "gem",
                    package = "supporting-package",
                },
                {
                    type = "gem",
                    package = "supporting-package2",
                },
            }, ctx.receipt.secondary_sources)
        end)
    )
end)

describe("gem version check", function()
    it(
        "should return current version",
        async_test(function()
            stub(spawn, "gem")
            spawn.gem.returns(Result.success {
                stdout = _.dedent [[
                    shellwords (default: 0.1.0)
                    singleton (default: 0.1.1)
                    solargraph (0.44.0)
                    stringio (default: 3.0.1)
                    strscan (default: 3.0.1)
                ]],
            })

            local result = gem.get_installed_primary_package_version(
                mock.new {
                    primary_source = mock.new {
                        type = "gem",
                        package = "solargraph",
                    },
                },
                "/tmp/install/dir"
            )

            assert.spy(spawn.gem).was_called(1)
            assert.spy(spawn.gem).was_called_with(match.tbl_containing {
                "list",
                cwd = "/tmp/install/dir",
                env = match.tbl_containing {
                    GEM_HOME = "/tmp/install/dir",
                    GEM_PATH = "/tmp/install/dir",
                    PATH = match.matches "^/tmp/install/dir/bin:.*$",
                },
            })
            assert.is_true(result:is_success())
            assert.equals("0.44.0", result:get_or_nil())
        end)
    )

    it(
        "should return outdated primary package",
        async_test(function()
            stub(spawn, "gem")
            spawn.gem.returns(Result.success {
                stdout = _.dedent [[
                    shellwords (default: 0.1.0)
                    singleton (default: 0.1.1)
                    solargraph (0.44.0)
                    stringio (default: 3.0.1)
                    strscan (default: 3.0.1)
                ]],
            })
            stub(api, "get")
            api.get.on_call_with("/api/rubygems/solargraph/versions/latest").returns(Result.success {
                name = "solargraph",
                version = "0.44.3",
            })

            local result = gem.check_outdated_primary_package(
                mock.new {
                    primary_source = mock.new {
                        type = "gem",
                        package = "solargraph",
                    },
                },
                "/tmp/install/dir"
            )

            assert.is_true(result:is_success())
            assert.same({
                name = "solargraph",
                current_version = "0.44.0",
                latest_version = "0.44.3",
            }, result:get_or_nil())
        end)
    )

    it(
        "should return failure if primary package is not outdated",
        async_test(function()
            stub(spawn, "gem")
            spawn.gem.returns(Result.success {
                stdout = _.dedent [[
                    shellwords (default: 0.1.0)
                    singleton (default: 0.1.1)
                    solargraph (0.44.0)
                    stringio (default: 3.0.1)
                    strscan (default: 3.0.1)
                ]],
            })
            stub(api, "get")
            api.get.on_call_with("/api/rubygems/solargraph/versions/latest").returns(Result.success {
                name = "solargraph",
                version = "0.44.0",
            })

            local result = gem.check_outdated_primary_package(
                mock.new {
                    primary_source = mock.new {
                        type = "gem",
                        package = "solargraph",
                    },
                },
                "/tmp/install/dir"
            )

            assert.is_true(result:is_failure())
            assert.equals("Primary package is not outdated.", result:err_or_nil())
        end)
    )

    it("should parse gem list output", function()
        assert.same(
            {
                ["solargraph"] = "0.44.3",
                ["unicode-display_width"] = "2.1.0",
            },
            gem.parse_gem_list_output [[

*** LOCAL GEMS ***

nokogiri (1.13.3 arm64-darwin)
solargraph (0.44.3)
unicode-display_width (2.1.0)
]]
        )
    end)
end)
