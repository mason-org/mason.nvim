local LazySourceCollection = require "mason-registry.sources"
local SynthesizedSource = require "mason-registry.sources.synthesized"

describe("LazySourceCollection", function()
    it("should dedupe registries on append/prepend", function()
        local coll = LazySourceCollection:new()

        coll:append "github:mason-org/mason-registry" -- 4
        coll:prepend "github:mason-org/mason-registry@2025-05-16" -- 3
        coll:prepend "github:my-own/registry" -- 2
        coll:prepend "lua:registry" -- 1
        coll:append "lua:registry" -- deduped
        coll:append "file:~/registry" -- 5
        coll:append "file:$HOME/registry" -- deduped

        assert.equals(5, coll:size())
        assert.same("lua:registry", coll:get(1):get_full_id())
        assert.same("github:my-own/registry", coll:get(2):get_full_id())
        assert.same("github:mason-org/mason-registry@2025-05-16", coll:get(3):get_full_id())
        assert.same("github:mason-org/mason-registry", coll:get(4):get_full_id())
        assert.same("file:~/registry", coll:get(5):get_full_id())
    end)

    it("should fall back to synthesized source", function()
        local coll = LazySourceCollection:new()

        for source in coll:iterate() do
            assert.is_true(getmetatable(source) == SynthesizedSource)
            return
        end
        error "Did not fall back to synthesized source"
    end)

    it("should exclude synthesized source", function()
        local coll = LazySourceCollection:new()

        for source in coll:iterate { include_synthesized = false } do
            error "Should not iterate."
        end
    end)
end)
