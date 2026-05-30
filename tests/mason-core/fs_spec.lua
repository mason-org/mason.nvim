local fs = require "mason-core.fs"
local mason = require "mason"

describe("fs", function()
    before_each(function()
        mason.setup {
            install_root_dir = "/foo",
        }
    end)

    it("refuses to rmrf paths outside of boundary", function()
        local e = assert.has_error(function()
            fs.sync.rmrf "/thisisa/path"
        end)

        assert.equals(
            [[Refusing to rmrf "/thisisa/path" which is outside of the allowed boundary "/foo". Please report this error at https://github.com/mason-org/mason.nvim/issues/new]],
            e
        )
    end)

    it("should mkdirp", function()
        local temp = vim.fn.tempname()
        local nested = vim.fs.joinpath(temp, "nested", "directory", "here")

        assert.has_error(function()
            assert(vim.uv.fs_stat(nested))
        end)

        fs.sync.mkdirp(nested)
        local stat = assert(vim.uv.fs_stat(nested), "fs_stat returned no value")
        assert.equals("directory", stat.type)
    end)
end)
