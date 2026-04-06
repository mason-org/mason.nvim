local parser = require "mason-core.lock.parser"

describe("lockfile parser", function()

    it("should shit", function ()
        vim.print(parser.deserialize("aöskjdasd aös \n         asdkjasd"))
        vim.print(parser.deserialize("aöskjdasd aös \n         asdkjasd"))
        vim.print(parser.deserialize("aöskjdasd aös \n         asdkjasd"))
        vim.print(parser.deserialize("aöskjdasd aös \n         asdkjasd"))
        vim.print(parser.deserialize("aöskjdasd aös \n         asdkjasd"))
        vim.print(parser.deserialize("aöskjdasd aös \n         asdkjasd"))
    end)
end)

