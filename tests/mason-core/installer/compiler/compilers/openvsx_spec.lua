local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local common = require "mason-core.installer.managers.common"
local match = require "luassert.match"
local openvsx = require "mason-core.installer.compiler.compilers.openvsx"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param overrides Purl
local function purl(overrides)
    local purl = Purl.parse("pkg:openvsx/namespace/name@1.10.1"):get_or_throw()
    if not overrides then
        return purl
    end
    return vim.tbl_deep_extend("force", purl, overrides)
end

describe("openvsx provider :: download :: parsing", function()
    it("should parse download source", function()
        assert.same(
            Result.success {
                download = {
                    file = "file-1.10.1.jar",
                },
                downloads = {
                    {
                        out_file = "file-1.10.1.jar",
                        download_url = "https://open-vsx.org/api/namespace/name/1.10.1/file/file-1.10.1.jar",
                    },
                },
            },
            openvsx.parse({
                download = {
                    file = "file-{{version}}.jar",
                },
            }, purl())
        )
    end)

    it("should parse download source with multiple targets", function()
        assert.same(
            Result.success {
                download = {
                    target = "linux_x64",
                    file = "file-linux-amd64-1.0.0.vsix",
                },
                downloads = {
                    {
                        out_file = "file-linux-amd64-1.0.0.vsix",
                        download_url = "https://open-vsx.org/api/namespace/name/1.0.0/file/file-linux-amd64-1.0.0.vsix",
                    },
                },
            },
            openvsx.parse({
                download = {
                    {
                        target = "win_arm",
                        file = "file-win-arm-{{version}}.vsix",
                    },
                    {
                        target = "linux_x64",
                        file = "file-linux-amd64-{{version}}.vsix",
                    },
                },
            }, purl { version = "1.0.0" }, { target = "linux_x64" })
        )
    end)

    it("should parse download source with output to different directory", function()
        assert.same(
            Result.success {
                download = {
                    file = "out-dir/file-linux-amd64-1.10.1.vsix",
                },
                downloads = {
                    {
                        out_file = "out-dir/file-linux-amd64-1.10.1.vsix",
                        download_url = "https://open-vsx.org/api/namespace/name/1.10.1/file/file-linux-amd64-1.10.1.vsix",
                    },
                },
            },
            openvsx.parse({
                download = {
                    file = "file-linux-amd64-{{version}}.vsix:out-dir/",
                },
            }, purl(), { target = "linux_x64" })
        )
    end)

    it("should recognize target_platform when available", function()
        assert.same(
            Result.success {
                download = {
                    file = "file-linux-1.10.1@win32-arm64.vsix",
                    target = "win_arm64",
                    target_platform = "win32-arm64",
                },
                downloads = {
                    {
                        out_file = "file-linux-1.10.1@win32-arm64.vsix",
                        download_url = "https://open-vsx.org/api/namespace/name/win32-arm64/1.10.1/file/file-linux-1.10.1@win32-arm64.vsix",
                    },
                },
            },
            openvsx.parse({
                download = {
                    {
                        target = "win_arm64",
                        file = "file-linux-{{version}}@win32-arm64.vsix",
                        target_platform = "win32-arm64",
                    },
                },
            }, purl(), { target = "win_arm64" })
        )
    end)
end)

describe("openvsx provider :: download :: installing", function()
    it("should install openvsx assets", function()
        local ctx = test_helpers.create_context()
        stub(common, "download_files", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return openvsx.install(ctx, {
                download = {
                    file = "file-1.10.1.jar",
                },
                downloads = {
                    {
                        out_file = "file-1.10.1.jar",
                        download_url = "https://open-vsx.org/api/namespace/name/1.10.1/file/file-1.10.1.jar",
                    },
                },
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(common.download_files).was_called(1)
        assert.spy(common.download_files).was_called_with(match.is_ref(ctx), {
            {
                out_file = "file-1.10.1.jar",
                download_url = "https://open-vsx.org/api/namespace/name/1.10.1/file/file-1.10.1.jar",
            },
        })
    end)
end)
