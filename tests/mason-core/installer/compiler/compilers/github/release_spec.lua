local Purl = require "mason-core.purl"
local Result = require "mason-core.result"
local common = require "mason-core.installer.managers.common"
local compiler = require "mason-core.installer.compiler"
local github = require "mason-core.installer.compiler.compilers.github"
local match = require "luassert.match"
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

describe("github compiler :: release :: parsing", function()
    it("should parse release asset source", function()
        assert.same(
            Result.success {
                repo = "namespace/name",
                asset = {
                    file = "file-2023-03-09.jar",
                },
                downloads = {
                    {
                        out_file = "file-2023-03-09.jar",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/file-2023-03-09.jar",
                    },
                },
            },
            github.parse({
                asset = {
                    file = "file-{{version}}.jar",
                },
            }, purl())
        )
    end)

    it("should parse release asset source with multiple targets", function()
        assert.same(
            Result.success {
                repo = "namespace/name",
                asset = {
                    target = "linux_x64",
                    file = "file-linux-amd64-2023-03-09.tar.gz",
                },
                downloads = {
                    {
                        out_file = "file-linux-amd64-2023-03-09.tar.gz",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/file-linux-amd64-2023-03-09.tar.gz",
                    },
                },
            },
            github.parse({
                asset = {
                    {
                        target = "win_arm",
                        file = "file-win-arm-{{version}}.zip",
                    },
                    {
                        target = "linux_x64",
                        file = "file-linux-amd64-{{version}}.tar.gz",
                    },
                },
            }, purl(), { target = "linux_x64" })
        )
    end)

    it("should parse release asset source with output to different directory", function()
        assert.same(
            Result.success {
                repo = "namespace/name",
                asset = {
                    file = "out-dir/file-linux-amd64-2023-03-09.tar.gz",
                },
                downloads = {
                    {
                        out_file = "out-dir/file-linux-amd64-2023-03-09.tar.gz",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/file-linux-amd64-2023-03-09.tar.gz",
                    },
                },
            },
            github.parse({
                asset = {
                    file = "file-linux-amd64-{{version}}.tar.gz:out-dir/",
                },
            }, purl(), { target = "linux_x64" })
        )
    end)

    it("should expand returned asset.file to point to out_file", function()
        assert.same(
            Result.success {
                repo = "namespace/name",
                asset = {
                    file = {
                        "out-dir/linux-amd64-2023-03-09.tar.gz",
                        "LICENSE.txt",
                        "README.md",
                    },
                },
                downloads = {
                    {
                        out_file = "out-dir/linux-amd64-2023-03-09.tar.gz",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/linux-amd64-2023-03-09.tar.gz",
                    },
                    {
                        out_file = "LICENSE.txt",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/license",
                    },
                    {
                        out_file = "README.md",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/README.md",
                    },
                },
            },
            github.parse({
                asset = {
                    file = {
                        "linux-amd64-{{version}}.tar.gz:out-dir/",
                        "license:LICENSE.txt",
                        "README.md",
                    },
                },
            }, purl(), { target = "linux_x64" })
        )
    end)

    it("should interpolate asset table", function()
        assert.same(
            Result.success {
                repo = "namespace/name",
                asset = {
                    file = "linux-amd64-2023-03-09.tar.gz",
                    bin = "linux-amd64-2023-03-09",
                },
                downloads = {
                    {
                        out_file = "linux-amd64-2023-03-09.tar.gz",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/linux-amd64-2023-03-09.tar.gz",
                    },
                },
            },
            github.parse({
                asset = {
                    file = "linux-amd64-{{version}}.tar.gz",
                    bin = "linux-amd64-{{version}}",
                },
            }, purl(), { target = "linux_x64" })
        )
    end)

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

    it("should upsert version overrides", function()
        local result = compiler.parse({
            schema = "registry+v1",
            source = {
                id = "pkg:github/owner/repo@1.2.3",
                asset = {
                    {
                        target = "darwin_x64",
                        file = "asset.tar.gz",
                    },
                },
                version_overrides = {
                    {
                        constraint = "semver:<=1.0.0",
                        id = "pkg:github/owner/repo@1.0.0",
                        asset = {
                            {
                                target = "darwin_x64",
                                file = "old-asset.tar.gz",
                            },
                        },
                    },
                },
            },
        }, { version = "1.0.0", target = "darwin_x64" })
        local parsed = result:get_or_nil()

        assert.is_true(result:is_success())
        assert.same({
            id = "pkg:github/owner/repo@1.0.0",
            asset = {
                target = "darwin_x64",
                file = "old-asset.tar.gz",
            },
            downloads = {
                {
                    download_url = "https://github.com/owner/repo/releases/download/1.0.0/old-asset.tar.gz",
                    out_file = "old-asset.tar.gz",
                },
            },
            repo = "owner/repo",
        }, parsed.source)
    end)

    it("should override source if version override provides its own purl id", function()
        local result = compiler.parse({
            schema = "registry+v1",
            source = {
                id = "pkg:github/owner/repo@1.2.3",
                asset = {
                    file = "asset.tar.gz",
                },
                version_overrides = {
                    {
                        constraint = "semver:<=1.0.0",
                        id = "pkg:npm/old-package",
                    },
                },
            },
        }, { version = "1.0.0", target = "darwin_x64" })

        assert.is_true(result:is_success())
        local parsed = result:get_or_throw()
        assert.same({
            type = "npm",
            scheme = "pkg",
            name = "old-package",
            version = "1.0.0",
        }, parsed.purl)
    end)
end)

describe("github compiler :: release :: installing", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should install github release assets", function()
        local ctx = test_helpers.create_context()
        local std = require "mason-core.installer.managers.std"
        stub(std, "download_file", mockx.returns(Result.success()))
        stub(std, "unpack", mockx.returns(Result.success()))
        stub(common, "download_files", mockx.returns(Result.success()))

        local result = ctx:execute(function()
            return github.install(ctx, {
                repo = "namespace/name",
                asset = {
                    file = "file-linux-amd64-2023-03-09.tar.gz",
                },
                downloads = {
                    {
                        out_file = "file-linux-amd64-2023-03-09.tar.gz",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/file-linux-amd64-2023-03-09.tar.gz",
                    },
                    {
                        out_file = "another-file-linux-amd64-2023-03-09.tar.gz",
                        download_url = "https://github.com/namespace/name/releases/download/2023-03-09/another-file-linux-amd64-2023-03-09.tar.gz",
                    },
                },
            })
        end)

        assert.is_true(result:is_success())
        assert.spy(common.download_files).was_called(1)
        assert.spy(common.download_files).was_called_with(match.is_ref(ctx), {
            {
                out_file = "file-linux-amd64-2023-03-09.tar.gz",
                download_url = "https://github.com/namespace/name/releases/download/2023-03-09/file-linux-amd64-2023-03-09.tar.gz",
            },
            {
                out_file = "another-file-linux-amd64-2023-03-09.tar.gz",
                download_url = "https://github.com/namespace/name/releases/download/2023-03-09/another-file-linux-amd64-2023-03-09.tar.gz",
            },
        })
    end)
end)
