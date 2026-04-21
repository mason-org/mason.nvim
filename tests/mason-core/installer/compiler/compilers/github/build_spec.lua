local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local github = require "mason-core.installer.compiler.compilers.github"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:github/namespace/name@2023-03-09"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("github compiler :: build :: parsing", function()
    it("should parse build source", function()
        assert.same(
            Result.success {
                build = {
                    run = [[npm install && npm run compile]],
                    env = {},
                },
                repo = "https://github.com/namespace/name.git",
                rev = "2023-03-09",
            },
            github.parse({
                build = {
                    run = [[npm install && npm run compile]],
                },
            }, purl())
        )
    end)

    it("should parse build source with multiple targets", function()
        assert.same(
            Result.success {
                build = {
                    target = "win_x64",
                    run = [[npm install]],
                    env = {},
                },
                repo = "https://github.com/namespace/name.git",
                rev = "2023-03-09",
            },
            github.parse({
                build = {
                    {
                        target = "linux_arm64",
                        run = [[npm install && npm run compile]],
                    },
                    {
                        target = "win_x64",
                        run = [[npm install]],
                    },
                },
            }, purl(), { target = "win_x64" })
        )
    end)
end)

describe("github compiler :: build :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install github build sources", function()
        local ctx = test_helpers.create_context()
        local std = require "mason-core.installer.managers.std"
        local common = require "mason-core.installer.managers.common"
        stub(std, "clone", mockx.returns(Result.success()))
        stub(common, "run_build_instruction", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return github.install(ctx, {
                repo = "namespace/name",
                rev = "2023-03-09",
                build = {
                    run = [[npm install && npm run compile]],
                    env = {
                        SOME_VALUE = "here",
                    },
                },
            }, purl())
        end)

        assert.is_true(result:is_success())
        assert.spy(std.clone).was_called(1)
        assert.spy(std.clone).was_called_with("namespace/name", { rev = "2023-03-09" })
        assert.spy(common.run_build_instruction).was_called(1)
        assert.spy(common.run_build_instruction).was_called_with {
            run = [[npm install && npm run compile]],
            env = {
                SOME_VALUE = "here",
            },
        }
    end)
end)
