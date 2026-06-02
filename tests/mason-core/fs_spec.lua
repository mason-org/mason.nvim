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

    it("should check if file_exists", function()
        local temp = vim.fn.tempname()

        assert.is_false(fs.sync.file_exists(temp))
        fs.sync.write_file(temp, "")
        assert.is_true(fs.sync.file_exists(temp))

        local temp_dir = vim.fn.tempname()
        fs.sync.mkdir(temp_dir)
        assert.is_false(fs.sync.file_exists(temp_dir))
    end)

    it("should check if dir_exists", function()
        local temp = vim.fn.tempname()

        assert.is_false(fs.sync.dir_exists(temp))
        fs.sync.mkdir(temp)
        assert.is_true(fs.sync.dir_exists(temp))

        local temp_file = vim.fn.tempname()
        fs.sync.write_file(temp_file, "")
        assert.is_false(fs.sync.dir_exists(temp_file))
    end)
end)
