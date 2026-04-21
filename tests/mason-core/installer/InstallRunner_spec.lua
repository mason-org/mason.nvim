local InstallHandle = require "mason-core.installer.InstallHandle"
local InstallLocation = require "mason-core.installer.InstallLocation"
local InstallRunner = require "mason-core.installer.InstallRunner"
local fs = require "mason-core.fs"
local match = require "luassert.match"
local receipt = require "mason-core.receipt"
local spy = require "luassert.spy"
local stub = require "luassert.stub"
local Semaphore = require("mason-core.async.control").Semaphore
local a = require "mason-core.async"
local registry = require "mason-registry"
local test_helpers = require "mason-test.helpers"

describe("InstallRunner ::", function()
    local dummy = registry.get_package "dummy"
    local dummy2 = registry.get_package "dummy2"

    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
        if dummy:is_installed() then
            test_helpers.sync_uninstall(dummy)
        end
        if dummy2:is_installed() then
            test_helpers.sync_uninstall(dummy2)
        end
    end)

    after_each(function()
        snapshot:revert()
    end)

    describe("locking ::", function()
        it("should respect semaphore locks", function()
            local semaphore = Semaphore:new(1)
            local location = InstallLocation.global()
            local dummy_handle = InstallHandle:new(dummy, location)
            local runner_1 = InstallRunner:new(dummy_handle, semaphore)
            local runner_2 = InstallRunner:new(InstallHandle:new(dummy2, location), semaphore)

            stub(dummy.spec.source, "install", function(ctx)
                ctx:await(function() end)
            end)
            spy.on(dummy2.spec.source, "install", function() end)

            local callback1 = spy.new()
            local callback2 = spy.new()
            local run = a.scope(function()
                runner_1:execute({}, callback1)
                runner_2:execute({}, callback2)
            end)

            run()

            assert.wait(function()
                assert.spy(dummy.spec.source.install).was_called(1)
                assert.spy(dummy2.spec.source.install).was_not_called()
            end)

            dummy_handle:terminate()

            assert.wait(function()
                assert.spy(dummy2.spec.source.install).was_called(1)
            end)

            assert.wait(function()
                assert.spy(callback1).was_called()
                assert.spy(callback2).was_called()
            end)
        end)

        it("should write lockfile", function()
            local semaphore = Semaphore:new(1)
            local location = InstallLocation.global()
            local dummy_handle = InstallHandle:new(dummy, location)
            local runner = InstallRunner:new(dummy_handle, semaphore)

            spy.on(fs.async, "write_file")

            test_helpers.sync_runner_execute(runner, {})

            assert.wait(function()
                assert.spy(fs.async.write_file).was_called_with(location:lockfile(dummy.name), vim.fn.getpid())
            end)
        end)

        it("should abort installation if installation lock exists", function()
            local semaphore = Semaphore:new(1)
            local location = InstallLocation.global()
            local dummy_handle = InstallHandle:new(dummy, location)
            local runner = InstallRunner:new(dummy_handle, semaphore)

            stub(fs.async, "file_exists")
            stub(fs.async, "read_file")
            fs.async.file_exists.on_call_with(location:lockfile(dummy.name)).returns(true)
            fs.async.read_file.on_call_with(location:lockfile(dummy.name)).returns "1337"

            local callback = test_helpers.sync_runner_execute(runner, {})

            assert.wait(function()
                assert.spy(callback).was_called()
                assert.spy(callback).was_called_with(
                    false,
                    "Lockfile exists, installation is already running in another process (pid: 1337). Run with :MasonInstall --force to bypass."
                )
            end)
        end)

        it("should not abort installation if installation lock exists with force=true", function()
            local semaphore = Semaphore:new(1)
            local location = InstallLocation.global()
            local dummy_handle = InstallHandle:new(dummy, location)
            local runner = InstallRunner:new(dummy_handle, semaphore)

            stub(fs.async, "file_exists")
            stub(fs.async, "read_file")
            fs.async.file_exists.on_call_with(location:lockfile(dummy.name)).returns(true)
            fs.async.read_file.on_call_with(location:lockfile(dummy.name)).returns "1337"

            local callback = test_helpers.sync_runner_execute(runner, { force = true })

            assert.wait(function()
                assert.spy(callback).was_called()
                assert.spy(callback).was_called_with(true, match.instanceof(receipt.InstallReceipt))
            end)
        end)

        it("should release lock after successful installation", function()
            local semaphore = Semaphore:new(1)
            local location = InstallLocation.global()
            local dummy_handle = InstallHandle:new(dummy, location)
            local runner = InstallRunner:new(dummy_handle, semaphore)
            stub(dummy.spec.source, "install", function()
                a.sleep(1000)
            end)

            local callback = spy.new()
            runner:execute({}, callback)

            assert.wait(function()
                assert.is_true(fs.sync.file_exists(location:lockfile(dummy.name)))
            end)
            assert.wait(function()
                assert.spy(callback).was_called_with(true, match.instanceof(receipt.InstallReceipt))
            end)
            assert.is_false(fs.sync.file_exists(location:lockfile(dummy.name)))
        end)
    end)

    it("should initialize install location", function()
        local location = InstallLocation.global()
        local runner = InstallRunner:new(InstallHandle:new(dummy, location), Semaphore:new(1))

        spy.on(location, "initialize")

        test_helpers.sync_runner_execute(runner, {})

        assert.wait(function()
            assert.spy(location.initialize).was_called(1)
        end)
    end)

    it("should emit failures", function()
        local registry_spy = spy.new()
        local package_spy = spy.new()
        registry:once("package:install:failed", registry_spy)
        dummy:once("install:failed", package_spy)

        local location = InstallLocation.global()
        local handle = InstallHandle:new(dummy, location)
        local runner = InstallRunner:new(handle, Semaphore:new(1))

        stub(dummy.spec.source, "install", function()
            error("I've made a mistake.", 0)
        end)

        local callback = test_helpers.sync_runner_execute(runner, {})

        assert.spy(registry_spy).was_called(1)
        assert.spy(registry_spy).was_called_with(match.is_ref(dummy), "I've made a mistake.")
        assert.spy(package_spy).was_called(1)
        assert.spy(package_spy).was_called_with "I've made a mistake."

        assert.spy(callback).was_called(1)
        assert.spy(callback).was_called_with(false, "I've made a mistake.")
    end)

    it("should terminate installation", function()
        local location = InstallLocation.global()
        local handle = InstallHandle:new(dummy, location)
        local runner = InstallRunner:new(handle, Semaphore:new(1))

        local capture = spy.new()
        stub(dummy.spec.source, "install", function()
            capture(1)
            handle:terminate()
            a.sleep(0)
            capture(2)
        end)

        local callback = test_helpers.sync_runner_execute(runner, {})

        assert.spy(callback).was_called_with(false, "Installation was aborted.")
        assert.spy(capture).was_called(1)
        assert.spy(capture).was_called_with(1)
    end)

    it("should write debug logs when debug=true", function()
        local location = InstallLocation.global()
        local handle = InstallHandle:new(dummy, location)
        local runner = InstallRunner:new(handle, Semaphore:new(1))

        stub(dummy.spec.source, "install", function(ctx)
            ctx.stdio_sink:stdout "Hello "
            ctx.stdio_sink:stderr "world!"
        end)

        local callback = test_helpers.sync_runner_execute(runner, { debug = true })

        assert.spy(callback).was_called_with(true, match.instanceof(receipt.InstallReceipt))
        assert.is_true(fs.sync.file_exists(location:package "dummy/mason-debug.log"))
        assert.equals("Hello world!", fs.sync.read_file(location:package "dummy/mason-debug.log"))
    end)

    it("should not retain installation directory on failure", function()
        local location = InstallLocation.global()
        local handle = InstallHandle:new(dummy, location)
        local runner = InstallRunner:new(handle, Semaphore:new(1))

        stub(dummy.spec.source, "install", function(ctx)
            ctx.stdio_sink:stderr "Something will go terribly wrong.\n"
            error("This went terribly wrong.", 0)
        end)

        local callback = test_helpers.sync_runner_execute(runner, {})

        assert.spy(callback).was_called_with(false, "This went terribly wrong.")
        assert.is_false(fs.sync.dir_exists(location:staging "dummy"))
        assert.is_false(fs.sync.dir_exists(location:package "dummy"))
    end)

    it("should retain installation directory on failure and debug=true", function()
        local location = InstallLocation.global()
        local handle = InstallHandle:new(dummy, location)
        local runner = InstallRunner:new(handle, Semaphore:new(1))

        stub(dummy.spec.source, "install", function(ctx)
            ctx.stdio_sink:stderr "Something will go terribly wrong.\n"
            error("This went terribly wrong.", 0)
        end)

        local callback = test_helpers.sync_runner_execute(runner, { debug = true })

        assert.spy(callback).was_called_with(false, "This went terribly wrong.")
        assert.is_true(fs.sync.dir_exists(location:staging "dummy"))
        assert.equals(
            "Something will go terribly wrong.\nThis went terribly wrong.\n",
            fs.sync.read_file(location:staging "dummy/mason-debug.log")
        )
    end)

    describe("receipt ::", function()
        it("should write receipt", function()
            local location = InstallLocation.global()
            local runner = InstallRunner:new(InstallHandle:new(dummy, location), Semaphore:new(1))

            test_helpers.sync_runner_execute(runner, {})

            local receipt_file = location:package "dummy/mason-receipt.json"

            assert.is_true(fs.sync.file_exists(receipt_file))
            assert.is_true(match.tbl_containing {
                name = "dummy",
                schema_version = "2.0",
                install_options = match.same {},
                metrics = match.tbl_containing {
                    completion_time = match.is_number(),
                    start_time = match.is_number(),
                },
                registry = match.same {
                    proto = "lua",
                    mod = "dummy-registry.index",
                },
                source = match.same {
                    id = "pkg:mason/dummy@1.0.0",
                    type = "registry+v1",
                    raw = {
                        id = "pkg:mason/dummy@1.0.0",
                    },
                },
                links = match.same {
                    bin = {},
                    opt = {},
                    share = {},
                },
            }(vim.json.decode(fs.sync.read_file(receipt_file))))
        end)
    end)
end)
