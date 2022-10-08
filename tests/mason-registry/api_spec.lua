local stub = require "luassert.stub"
local Result = require "mason-core.result"

describe("mason-registry API", function()
    ---@module "mason-registry.api"
    local api
    local fetch
    before_each(function()
        fetch = stub.new()
        package.loaded["mason-core.fetch"] = fetch
        package.loaded["mason-registry.api"] = nil
        api = require "mason-registry.api"
    end)

    it("should stringify query parameters", function()
        fetch.returns(Result.success [[{}]])

        api.get("/api/data", {
            params = {
                page = 2,
                page_limit = 10,
                sort = "ASC",
            },
        })

        assert.spy(fetch).was_called(1)
        assert.spy(fetch).was_called_with "https://api.mason-registry.dev/api/data?page=2&page_limit=10&sort=ASC"
    end)

    it("should deserialize JSON", function()
        fetch.returns(Result.success [[{"field": ["value"]}]])

        local result = api.get("/"):get_or_throw()

        assert.same({ field = { "value" } }, result)
    end)
end)
