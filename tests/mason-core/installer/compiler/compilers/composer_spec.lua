local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local composer = require "mason-core.installer.compiler.compilers.composer"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:composer/vendor/package@2.0.0"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("composer compiler :: parsing", function()
    it("should parse package", function()
        assert.same(
            Result.success {
                package = "vendor/package",
                version = "2.0.0",
            },
            composer.parse({}, purl())
        )
    end)
end)

describe("composer compiler :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install composer packages", function()
        local ctx = test_helpers.create_context()
        local manager = require "mason-core.installer.managers.composer"
        stub(manager, "install", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return composer.install(ctx, {
                package = "vendor/package",
                version = "1.2.0",
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(manager.install).was_called(1)
        assert.spy(manager.install).was_called_with("vendor/package", "1.2.0")
    end)
end)
