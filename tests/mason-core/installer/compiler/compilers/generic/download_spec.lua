local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local generic = require "mason-core.installer.compiler.compilers.generic"
local match = require "luassert.match"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:generic/namespace/name@v1.2.0"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("generic compiler :: download :: parsing", function()
    it("should parse single download target", function()
        assert.same(
            Result.success {
                downloads = {
                    {
                        out_file = "name.tar.gz",
                        download_url = "https://getpackage.org/downloads/1.2.0/name.tar.gz",
                    },
                },
                download = {
                    files = {
                        ["name.tar.gz"] = [[https://getpackage.org/downloads/1.2.0/name.tar.gz]],
                    },
                },
            },
            generic.parse({
                download = {
                    files = {
                        ["name.tar.gz"] = [[https://getpackage.org/downloads/{{version | strip_prefix "v"}}/name.tar.gz]],
                    },
                },
            }, purl())
        )
    end)

    it("should coalesce download target", function()
        assert.same(
            Result.success {
                downloads = {
                    {
                        out_file = "name.tar.gz",
                        download_url = "https://getpackage.org/downloads/linux-aarch64/1.2.0/name.tar.gz",
                    },
                },
                download = {
                    target = "linux_arm64",
                    files = {
                        ["name.tar.gz"] = [[https://getpackage.org/downloads/linux-aarch64/1.2.0/name.tar.gz]],
                    },
                },
            },
            generic.parse({
                download = {
                    {
                        target = "linux_arm64",
                        files = {
                            ["name.tar.gz"] = [[https://getpackage.org/downloads/linux-aarch64/{{version | strip_prefix "v"}}/name.tar.gz]],
                        },
                    },
                    {
                        target = "win_arm64",
                        files = {
                            ["name.tar.gz"] = [[https://getpackage.org/downloads/win-aarch64/{{version | strip_prefix "v"}}/name.tar.gz]],
                        },
                    },
                },
            }, purl(), { target = "linux_arm64" })
        )
    end)

    it("should check supported platforms", function()
        assert.same(
            Result.failure "PLATFORM_UNSUPPORTED",
            generic.parse(
                {
                    download = {
                        {
                            target = "win_arm64",
                            files = {
                                ["name.tar.gz"] = [[https://getpackage.org/downloads/win-aarch64/{{version | strip_prefix "v"}}/name.tar.gz]],
                            },
                        },
                    },
                },
                purl(),
                {
                    target = "linux_arm64",
                }
            )
        )
    end)
end)

describe("generic compiler :: download :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install generic packages", function()
        local ctx = test_helpers.create_context()
        local common = require "mason-core.installer.managers.common"
        stub(common, "download_files", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return generic.install(ctx, {
                downloads = {
                    {
                        out_file = "name.tar.gz",
                        download_url = "https://getpackage.org/downloads/linux-aarch64/1.2.0/name.tar.gz",
                    },
                },
                download = {
                    target = "linux_arm64",
                    files = {
                        ["name.tar.gz"] = [[https://getpackage.org/downloads/linux-aarch64/1.2.0/name.tar.gz]],
                    },
                },
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(common.download_files).was_called(1)
        assert.spy(common.download_files).was_called_with(match.is_ref(ctx), {
            {
                out_file = "name.tar.gz",
                download_url = "https://getpackage.org/downloads/linux-aarch64/1.2.0/name.tar.gz",
            },
        })
    end)
end)
