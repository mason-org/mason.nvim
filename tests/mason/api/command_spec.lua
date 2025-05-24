local log = require "mason-core.log"
local match = require "luassert.match"
local spy = require "luassert.spy"
local stub = require "luassert.stub"

local Pkg = require "mason-core.package"
local a = require "mason-core.async"
local api = require "mason.api.command"
local registry = require "mason-registry"

describe(":Mason", function()
    it("should open the UI window", function()
        api.Mason()
        a.run_blocking(a.wait, vim.schedule)
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)
        assert.equals("mason", vim.api.nvim_buf_get_option(buf, "filetype"))
    end)
end)

describe(":MasonInstall", function()
    it("should install the provided packages", function()
        local dummy = registry.get_package "dummy"
        local dummy2 = registry.get_package "dummy2"
        spy.on(Pkg, "install")
        api.MasonInstall { "dummy@1.0.0", "dummy2" }
        assert.spy(Pkg.install).was_called(2)
        assert.spy(Pkg.install).was_called_with(match.is_ref(dummy), { version = "1.0.0" }, match.is_function())
        assert
            .spy(Pkg.install)
            .was_called_with(match.is_ref(dummy2), match.tbl_containing { version = match.is_nil() }, match.is_function())
    end)

    it("should install provided packages in debug mode", function()
        local dummy = registry.get_package "dummy"
        local dummy2 = registry.get_package "dummy2"
        spy.on(Pkg, "install")
        vim.cmd [[MasonInstall --debug dummy dummy2]]
        assert.spy(Pkg.install).was_called(2)
        assert
            .spy(Pkg.install)
            .was_called_with(match.is_ref(dummy), { version = nil, debug = true }, match.is_function())
        assert
            .spy(Pkg.install)
            .was_called_with(match.is_ref(dummy2), { version = nil, debug = true }, match.is_function())
    end)

    it("should open the UI window", function()
        local dummy = registry.get_package "dummy"
        spy.on(dummy, "install")
        api.MasonInstall { "dummy" }
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)
        assert.equals("mason", vim.api.nvim_buf_get_option(buf, "filetype"))
    end)
end)

describe(":MasonUninstall", function()
    it("should uninstall the provided packages", function()
        local dummy = registry.get_package "dummy"
        local dummy2 = registry.get_package "dummy"
        spy.on(Pkg, "uninstall")
        api.MasonUninstall { "dummy", "dummy2" }
        assert.spy(Pkg.uninstall).was_called(2)
        assert.spy(Pkg.uninstall).was_called_with(match.is_ref(dummy))
        assert.spy(Pkg.uninstall).was_called_with(match.is_ref(dummy2))
    end)
end)

describe(":MasonLog", function()
    it("should open the log file", function()
        api.MasonLog()
        assert.equals(2, #vim.api.nvim_list_tabpages())
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_buf_call(buf, function()
            assert.equals(log.outfile, vim.fn.expand "%")
        end)
    end)
end)

describe(":MasonUpdate", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should update registries", function()
        stub(registry, "update", function(cb)
            cb(true, { {} })
        end)
        spy.on(vim, "notify")
        api.MasonUpdate()
        assert.spy(vim.notify).was_called(2)
        assert.spy(vim.notify).was_called_with("Updating registries…", vim.log.levels.INFO, {
            title = "mason.nvim",
        })
        assert.spy(vim.notify).was_called_with("Successfully updated 1 registry.", vim.log.levels.INFO, {
            title = "mason.nvim",
        })
    end)

    it("should notify errors", function()
        stub(registry, "update", function(cb)
            cb(false, "Some error.")
        end)
        spy.on(vim, "notify")
        api.MasonUpdate()
        assert.spy(vim.notify).was_called(2)
        assert.spy(vim.notify).was_called_with("Updating registries…", vim.log.levels.INFO, {
            title = "mason.nvim",
        })
        assert.spy(vim.notify).was_called_with("Failed to update registries: Some error.", vim.log.levels.ERROR, {
            title = "mason.nvim",
        })
    end)
end)
