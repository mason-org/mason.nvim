local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local match = require "luassert.match"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

local spawn = require "mason-core.spawn"

---@param contents string
local function stub_etc_os_release(contents)
    stub(spawn, "bash")
    spawn.bash.on_call_with({ "-c", "cat /etc/*-release" }).returns(Result.success {
        stdout = contents,
    })
end

describe("platform", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    local function platform()
        package.loaded["mason-core.platform"] = nil
        return require "mason-core.platform"
    end

    local function stub_uname(uname)
        stub(vim.loop, "os_uname")
        vim.loop.os_uname.returns(uname)
    end

    ---@param libc '"glibc"' | '"musl"'
    local function stub_libc(libc)
        stub(os, "execute")
        stub(vim.fn, "executable")
        stub(vim.fn, "system")
        vim.fn.executable.on_call_with("ldd").returns(1)
        vim.fn.executable.on_call_with("getconf").returns(1)
        if libc == "musl" then
            vim.fn.system.on_call_with({ "getconf", "GNU_LIBC_VERSION" }).returns ""
            vim.fn.system.on_call_with({ "ldd", "--version" }).returns "musl libc (aarch64)"
        elseif libc == "glibc" then
            vim.fn.system.on_call_with({ "getconf", "GNU_LIBC_VERSION" }).returns "glibc 2.35"
            vim.fn.system.on_call_with({ "ldd", "--version" }).returns "ldd (Ubuntu GLIBC 2.35-0ubuntu3.1) 2.35"
        end
    end

    local function stub_mac()
        stub(vim.fn, "has")
        vim.fn.has.on_call_with("mac").returns(1)
        vim.fn.has.on_call_with("unix").returns(1)
        vim.fn.has.on_call_with("linux").returns(0)
        vim.fn.has.on_call_with(match._).returns(0)
    end

    local function stub_linux()
        stub(vim.fn, "has")
        vim.fn.has.on_call_with("mac").returns(0)
        vim.fn.has.on_call_with("unix").returns(1)
        vim.fn.has.on_call_with("linux").returns(1)
        vim.fn.has.on_call_with(match._).returns(0)
    end

    local function stub_windows()
        stub(vim.fn, "has")
        vim.fn.has.on_call_with("win32").returns(1)
        vim.fn.has.on_call_with(match._).returns(0)
    end

    it("should be able to detect platform and arch", function()
        stub_mac()
        stub_uname { machine = "aarch64" }
        assert.is_true(platform().is.mac_arm64)
        assert.is_false(platform().is.mac_x64)
        assert.is_false(platform().is.nothing)
    end)

    it("should be able to detect macos", function()
        stub_mac()
        assert.is_true(platform().is.mac)
        assert.is_true(platform().is.darwin)
        assert.is_true(platform().is.unix)
        assert.is_false(platform().is.linux)
        assert.is_false(platform().is.win)
    end)

    it("should be able to detect linux", function()
        stub_linux()
        assert.is_false(platform().is.mac)
        assert.is_false(platform().is.darwin)
        assert.is_true(platform().is.unix)
        assert.is_true(platform().is.linux)
        assert.is_false(platform().is.win)
    end)

    it("should be able to detect windows", function()
        stub_windows()
        assert.is_false(platform().is.mac)
        assert.is_false(platform().is.darwin)
        assert.is_false(platform().is.unix)
        assert.is_false(platform().is.linux)
        assert.is_true(platform().is.win)
    end)

    it("should be able to detect correct triple based on libc", function()
        stub_linux()
        stub_uname { machine = "aarch64" }
        stub_libc "musl"
        assert.is_false(platform().is.linux_x64_musl)
        assert.is_false(platform().is.linux_x64_gnu)
        assert.is_true(platform().is.linux_arm64_musl)
        assert.is_false(platform().is.linux_arm64_gnu)
        assert.is_false(platform().is.linux_arm64_gnu)
    end)

    it("should be able to detect correct triple based on sysname", function()
        stub_linux()
        stub_uname { machine = "aarch64", sysname = "OpenBSD" }
        stub_libc "musl"
        assert.is_false(platform().is.linux_x64_musl)
        assert.is_false(platform().is.linux_x64_gnu)
        assert.is_false(platform().is.linux_arm64_gnu)
        assert.is_false(platform().is.linux_arm64_gnu)
        assert.is_true(platform().is.linux_arm64_openbsd)
    end)

    it("should run correct case on linux", function()
        local unix = spy.new()
        local win = spy.new()
        local mac = spy.new()
        local linux = spy.new()

        stub_linux()
        platform().when {
            unix = unix,
            win = win,
            linux = linux,
            mac = mac,
        }
        assert.spy(unix).was_not_called()
        assert.spy(mac).was_not_called()
        assert.spy(win).was_not_called()
        assert.spy(linux).was_called(1)
    end)

    it("should run correct case on mac", function()
        local unix = spy.new()
        local win = spy.new()
        local mac = spy.new()
        local linux = spy.new()

        stub_mac()
        platform().when {
            unix = unix,
            win = win,
            linux = linux,
            mac = mac,
        }
        assert.spy(unix).was_not_called()
        assert.spy(mac).was_called(1)
        assert.spy(win).was_not_called()
        assert.spy(linux).was_not_called()
    end)

    it("should run correct case on windows", function()
        local unix = spy.new()
        local win = spy.new()
        local mac = spy.new()
        local linux = spy.new()

        stub_windows()
        platform().when {
            unix = unix,
            win = win,
            linux = linux,
            mac = mac,
        }
        assert.spy(unix).was_not_called()
        assert.spy(mac).was_not_called()
        assert.spy(win).was_called(1)
        assert.spy(linux).was_not_called()
    end)

    it("should run correct case on mac (unix)", function()
        local unix = spy.new()
        local win = spy.new()

        stub_mac()
        platform().when {
            unix = unix,
            win = win,
        }
        assert.spy(unix).was_called(1)
        assert.spy(win).was_not_called()
    end)

    it("should run correct case on linux (unix)", function()
        local unix = spy.new()
        local win = spy.new()

        stub_linux()
        platform().when {
            unix = unix,
            win = win,
        }
        assert.spy(unix).was_called(1)
        assert.spy(win).was_not_called()
    end)

    describe("macOS distribution detection", function()
        before_each(function()
            stub_mac()
        end)

        it("detects macOS", function()
            assert.same({ id = "macOS", version = {} }, platform().os_distribution())
        end)
    end)

    describe("Windows distribution detection", function()
        before_each(function()
            stub_windows()
        end)

        it("detects Windows", function()
            assert.same({ id = "windows", version = {} }, platform().os_distribution())
        end)
    end)

    describe("Linux distribution detection", function()
        before_each(function()
            stub_linux()
        end)

        it("detects Ubuntu", function()
            stub_etc_os_release(_.dedent [[
                NAME="Ubuntu"
                VERSION="20.04.5 LTS (Focal Fossa)"
                ID=ubuntu
                ID_LIKE=debian
                PRETTY_NAME="Ubuntu 20.04.5 LTS"
                VERSION_ID="20.04"
                HOME_URL="https://www.ubuntu.com/"
                SUPPORT_URL="https://help.ubuntu.com/"
                BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
                PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
                VERSION_CODENAME=focal
                UBUNTU_CODENAME=focal
            ]])
            assert.same(
                { id = "ubuntu", version = { major = 20, minor = 4 }, version_id = "20.04" },
                platform().os_distribution()
            )
        end)

        it("detects CentOS", function()
            stub_etc_os_release(_.dedent [[
                NAME="CentOS Linux"
                VERSION="7 (Core)"
                ID="centos"
                ID_LIKE="rhel fedora"
                VERSION_ID="7"
                PRETTY_NAME="CentOS Linux 7 (Core)"
                ANSI_COLOR="0;31"
                CPE_NAME="cpe:/o:centos:centos:7"
                HOME_URL="https://www.centos.org/"
                BUG_REPORT_URL="https://bugs.centos.org/"

                CENTOS_MANTISBT_PROJECT="CentOS-7"
                CENTOS_MANTISBT_PROJECT_VERSION="7"
                REDHAT_SUPPORT_PRODUCT="centos"
                REDHAT_SUPPORT_PRODUCT_VERSION="7"
            ]])
            assert.same({ id = "centos", version = { major = 7 }, version_id = "7" }, platform().os_distribution())
        end)

        it("detects generic Linux", function()
            stub(spawn, "bash")
            spawn.bash.returns(Result.failure())
            assert.same({ id = "linux-generic", version = {} }, platform().os_distribution())
        end)

        it("detects generic Linux", function()
            stub_etc_os_release(_.dedent [[
                UNKNOWN_ID=here
            ]])
            assert.same({ id = "linux-generic", version = {} }, platform().os_distribution())
        end)
    end)
end)
