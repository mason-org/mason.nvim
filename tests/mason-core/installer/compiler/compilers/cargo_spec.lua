local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local cargo = require "mason-core.installer.compiler.compilers.cargo"
local providers = require "mason-core.providers"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:cargo/crate-name@1.4.3"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("cargo compiler :: parsing", function()
    it("should parse package", function()
        assert.same(
            Result.success {
                crate = "crate-name",
                version = "1.4.3",
                features = nil,
                locked = true,
                git = nil,
            },
            cargo.parse({}, purl())
        )
    end)

    it("should respect repository_url qualifier", function()
        assert.same(
            Result.success {
                crate = "crate-name",
                version = "1.4.3",
                features = nil,
                locked = true,
                git = { url = "https://github.com/crate-org/crate-name", rev = false },
            },
            cargo.parse({}, purl { qualifiers = { repository_url = "https://github.com/crate-org/crate-name" } })
        )
    end)

    it("should respect repository_url qualifier with rev=true qualifier", function()
        assert.same(
            Result.success {
                crate = "crate-name",
                version = "1.4.3",
                features = nil,
                locked = true,
                git = { url = "https://github.com/crate-org/crate-name", rev = true },
            },
            cargo.parse(
                {},
                purl { qualifiers = { repository_url = "https://github.com/crate-org/crate-name", rev = "true" } }
            )
        )
    end)

    it("should respect features qualifier", function()
        assert.same(
            Result.success {
                crate = "crate-name",
                version = "1.4.3",
                features = "lsp,cli",
                locked = true,
                git = nil,
            },
            cargo.parse({}, purl { qualifiers = { features = "lsp,cli" } })
        )
    end)

    it("should respect locked qualifier", function()
        assert.same(
            Result.success {
                crate = "crate-name",
                version = "1.4.3",
                features = nil,
                locked = false,
                git = nil,
            },
            cargo.parse({}, purl { qualifiers = { locked = "false" } })
        )
    end)

    it("should check supported platforms", function()
        assert.same(
            Result.failure "PLATFORM_UNSUPPORTED",
            cargo.parse({
                supported_platforms = { "VIC64" },
            }, purl { qualifiers = { locked = "false" } })
        )
    end)
end)

describe("cargo compiler :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install cargo packages", function()
        local ctx = test_helpers.create_context()
        local manager = require "mason-core.installer.managers.cargo"
        stub(manager, "install", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return cargo.install(ctx, {
                crate = "crate-name",
                version = "1.2.0",
                features = nil,
                locked = true,
                git = nil,
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(manager.install).was_called(1)
        assert.spy(manager.install).was_called_with("crate-name", "1.2.0", {
            git = nil,
            features = nil,
            locked = true,
        })
    end)
end)

describe("cargo compiler :: versions", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should recognize github cargo source", function()
        stub(providers.github, "get_all_tags", function()
            return Result.success { "1.0.0", "2.0.0", "3.0.0" }
        end)

        local result = cargo.get_versions(purl {
            qualifiers = {
                repository_url = "https://github.com/rust-lang/rust-analyzer",
            },
        })

        assert.is_true(result:is_success())
        assert.same({ "1.0.0", "2.0.0", "3.0.0" }, result:get_or_throw())
        assert.spy(providers.github.get_all_tags).was_called(1)
        assert.spy(providers.github.get_all_tags).was_called_with "rust-lang/rust-analyzer"
    end)

    it("should not provide git commit SHAs", function()
        local result = cargo.get_versions(purl {
            qualifiers = {
                repository_url = "https://github.com/rust-lang/rust-analyzer",
                rev = "true",
            },
        })

        assert.is_false(result:is_success())
        assert.equals("Unable to retrieve commit SHAs.", result:err_or_nil())
    end)
end)
