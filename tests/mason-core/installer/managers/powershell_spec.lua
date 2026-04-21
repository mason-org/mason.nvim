local a = require "mason-core.async"
local match = require "luassert.match"
local mock = require "luassert.mock"
local spawn = require "mason-core.spawn"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

describe("powershell manager", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    local function powershell()
        package.loaded["mason-core.installer.managers.powershell"] = nil
        return require "mason-core.installer.managers.powershell"
    end

    it("should use pwsh if available", function()
        stub(spawn, "pwsh", function() end)
        stub(spawn, "powershell", function() end)
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("pwsh").returns(1)

        powershell().command "echo 'Is this bash?'"

        assert.spy(spawn.pwsh).was_called(1)
        assert.spy(spawn.powershell).was_called(0)
    end)

    it("should use powershell if pwsh is not available", function()
        stub(spawn, "pwsh", function() end)
        stub(spawn, "powershell", function() end)
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("pwsh").returns(0)

        local powershell = powershell()
        a.run_blocking(powershell.command, "echo 'Is this bash?'")

        assert.spy(spawn.pwsh).was_called(0)
        assert.spy(spawn.powershell).was_called(1)
    end)

    it("should use the provided spawner for commands", function()
        spy.on(spawn, "pwsh")
        local custom_spawn = mock.new { pwsh = mockx.just_runs }
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("pwsh").returns(1)
        powershell().command("echo 'Is this bash?'", {}, custom_spawn)

        assert.spy(spawn.pwsh).was_called(0)
        assert.spy(custom_spawn.pwsh).was_called(1)
    end)

    it("should provide default powershell options via command interface", function()
        stub(spawn, "pwsh", function() end)
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("pwsh").returns(1)

        powershell().command "echo 'Is this bash?'"

        assert.spy(spawn.pwsh).was_called(1)
        assert.spy(spawn.pwsh).was_called_with(match.tbl_containing {
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            [[ $ErrorActionPreference = "Stop";  $ProgressPreference = 'SilentlyContinue';  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; echo 'Is this bash?']],
        })
    end)

    it("should close stdin", function()
        local stdin = {
            close = spy.new(),
        }
        stub(
            spawn,
            "pwsh",
            ---@param args SpawnArgs
            function(args)
                args.on_spawn(mock.new(), {
                    stdin,
                }, 1)
            end
        )
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("pwsh").returns(1)

        powershell().command "Powershell-Command"

        assert.spy(spawn.pwsh).was_called(1)
        assert.spy(stdin.close).was_called(1)
        assert.spy(stdin.close).was_called_with(match.is_ref(stdin))
    end)
end)
