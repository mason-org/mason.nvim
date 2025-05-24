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
end)
