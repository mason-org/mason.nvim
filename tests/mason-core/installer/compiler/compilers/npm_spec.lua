local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local npm = require "mason-core.installer.compiler.compilers.npm"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:npm/%40namespace/package@v1.5.0"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("npm compiler :: parsing", function()
    it("should parse package", function()
        assert.same(
            Result.success {
                package = "@namespace/package",
                version = "v1.5.0",
                extra_packages = { "extra" },
            },
            npm.parse({ extra_packages = { "extra" } }, purl())
        )
    end)
end)

describe("npm compiler :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install npm packages", function()
        local ctx = test_helpers.create_context()
        local manager = require "mason-core.installer.managers.npm"
        stub(manager, "init", mockx.returns(Result.success()))
        stub(manager, "install", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return npm.install(ctx, {
                package = "@namespace/package",
                version = "v1.5.0",
                extra_packages = { "extra" },
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(manager.init).was_called(1)
        assert.spy(manager.install).was_called(1)
        assert.spy(manager.install).was_called_with("@namespace/package", "v1.5.0", { extra_packages = { "extra" } })
    end)
end)
