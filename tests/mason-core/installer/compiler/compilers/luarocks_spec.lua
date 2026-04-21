local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local luarocks = require "mason-core.installer.compiler.compilers.luarocks"
local match = require "luassert.match"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:luarocks/namespace/name@1.0.0"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("luarocks compiler :: parsing", function()
    it("should parse package", function()
        assert.same(
            Result.success {
                package = "namespace/name",
                version = "1.0.0",
                server = nil,
                dev = false,
            },
            luarocks.parse({}, purl())
        )
    end)

    it("should parse package dev flag", function()
        assert.same(
            Result.success {
                package = "namespace/name",
                version = "1.0.0",
                server = nil,
                dev = true,
            },
            luarocks.parse({}, purl { qualifiers = { dev = "true" } })
        )
    end)

    it("should parse package server flag", function()
        assert.same(
            Result.success {
                package = "namespace/name",
                version = "1.0.0",
                server = "https://luarocks.org/dev",
                dev = false,
            },
            luarocks.parse({}, purl { qualifiers = { repository_url = "https://luarocks.org/dev" } })
        )
    end)
end)

describe("luarocks compiler :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install luarocks packages", function()
        local ctx = test_helpers.create_context()
        local manager = require "mason-core.installer.managers.luarocks"
        local ret_val = Result.success()
        stub(manager, "install", mockx.returns(ret_val))

        local result = ctx:execute(function()
            return luarocks.install(ctx, {
                package = "namespace/name",
                version = "1.0.0",
                server = "https://luarocks.org/dev",
                dev = false,
            })
        end)

        assert.is_true(match.is_ref(ret_val)(result))
        assert.spy(manager.install).was_called(1)
        assert.spy(manager.install).was_called_with("namespace/name", "1.0.0", {
            dev = false,
            server = "https://luarocks.org/dev",
        })
    end)
end)
