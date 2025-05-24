local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local opam = require "mason-core.installer.compiler.compilers.opam"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:opam/package@2.2.0"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("opam compiler :: parsing", function()
    it("should parse package", function()
        assert.same(
            Result.success {
                package = "package",
                version = "2.2.0",
            },
            opam.parse({}, purl())
        )
    end)
end)

describe("opam compiler :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install opam packages", function()
        local ctx = test_helpers.create_context()
        local manager = require "mason-core.installer.managers.opam"
        stub(manager, "install", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return opam.install(ctx, {
                package = "package",
                version = "1.5.0",
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(manager.install).was_called(1)
        assert.spy(manager.install).was_called_with("package", "1.5.0")
    end)
end)
