local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local installer = require "mason-core.installer"
local nuget = require "mason-core.installer.registry.providers.nuget"
local stub = require "luassert.stub"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:nuget/package@2.2.0?repository_url=https://api.nuget.org/v3/index.json"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("nuget provider :: parsing", function()
    it("should parse package", function()
        assert.same(
            Result.success {
                package = "package",
                version = "2.2.0",
                repository_url = "https://api.nuget.org/v3/index.json"
            },
            nuget.parse({}, purl())
        )
    end)
end)

describe("nuget provider :: installing", function()
    it("should install nuget packages", function()
        local ctx = create_dummy_context()
        local manager = require "mason-core.installer.managers.nuget"
        stub(manager, "install", mockx.returns(Result.success()))

        local result = installer.exec_in_context(ctx, function()
            return nuget.install(ctx, {
                package = "package",
                version = "1.5.0",
                repository_url = "https://api.nuget.org/v3/index.json"
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(manager.install).was_called(1)
        assert.spy(manager.install).was_called_with("package", "1.5.0", "https://api.nuget.org/v3/index.json")
    end)
end)
