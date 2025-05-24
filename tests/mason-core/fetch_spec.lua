local Result = require "mason-core.result"
local fetch = require "mason-core.fetch"
local match = require "luassert.match"
local spawn = require "mason-core.spawn"
local stub = require "luassert.stub"
local version = require "mason.version"

describe("fetch", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should exhaust all candidates", function()
        stub(spawn, "wget")
        stub(spawn, "curl")
        spawn.wget.returns(Result.failure "wget failure")
        spawn.curl.returns(Result.failure "curl failure")

        local result = fetch("https://api.github.com", {
            headers = { ["X-Custom-Header"] = "here" },
        })
        assert.is_true(result:is_failure())
        assert.spy(spawn.wget).was_called(1)
        assert.spy(spawn.curl).was_called(1)
        assert.spy(spawn.wget).was_called_with {
            {
                ("--header=User-Agent: mason.nvim %s (+https://github.com/mason-org/mason.nvim)"):format(
                    version.VERSION
                ),
                "--header=X-Custom-Header: here",
            },
            "-nv",
            "-o",
            "/dev/null",
            "-O",
            "-",
            "--timeout=30",
            "--method=GET",
            vim.NIL, -- body-data
            "https://api.github.com",
        }

        assert.spy(spawn.curl).was_called_with(match.tbl_containing {
            match.same {
                {
                    "-H",
                    ("User-Agent: mason.nvim %s (+https://github.com/mason-org/mason.nvim)"):format(version.VERSION),
                },
                {
                    "-H",
                    "X-Custom-Header: here",
                },
            },
            "-fsSL",
            match.same { "-X", "GET" },
            vim.NIL, -- data
            vim.NIL, -- out file
            match.same { "--connect-timeout", 30 },
            "https://api.github.com",
            on_spawn = match.is_function(),
        })
    end)

    it("should return stdout", function()
        stub(spawn, "curl")
        spawn.curl.returns(Result.success {
            stdout = [[{"data": "here"}]],
        })
        local result = fetch "https://api.github.com/data"
        assert.is_true(result:is_success())
        assert.equals([[{"data": "here"}]], result:get_or_throw())
    end)

    it("should respect out_file opt", function()
        stub(spawn, "wget")
        stub(spawn, "curl")
        spawn.wget.returns(Result.failure "wget failure")
        spawn.curl.returns(Result.failure "curl failure")
        fetch("https://api.github.com/data", { out_file = "/test.json" })

        assert.spy(spawn.wget).was_called_with {
            {
                ("--header=User-Agent: mason.nvim %s (+https://github.com/mason-org/mason.nvim)"):format(
                    version.VERSION
                ),
            },
            "-nv",
            "-o",
            "/dev/null",
            "-O",
            "/test.json",
            "--timeout=30",
            "--method=GET",
            vim.NIL, -- body-data
            "https://api.github.com/data",
        }

        assert.spy(spawn.curl).was_called_with(match.tbl_containing {
            match.same {
                {
                    "-H",
                    ("User-Agent: mason.nvim %s (+https://github.com/mason-org/mason.nvim)"):format(version.VERSION),
                },
            },
            "-fsSL",
            match.same { "-X", "GET" },
            vim.NIL, -- data
            match.same { "-o", "/test.json" },
            match.same { "--connect-timeout", 30 },
            "https://api.github.com/data",
            on_spawn = match.is_function(),
        })
    end)
end)
