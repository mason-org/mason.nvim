local _ = require "mason-core.functional"

describe("functional: type", function()
    it("should check nil value", function()
        assert.is_true(_.is_nil(nil))
        assert.is_false(_.is_nil(1))
        assert.is_false(_.is_nil {})
        assert.is_false(_.is_nil(function() end))
    end)

    it("should check types", function()
        local is_fun = _.is "function"
        local is_string = _.is "string"
        local is_number = _.is "number"
        local is_boolean = _.is "boolean"

        assert.is_true(is_fun(function() end))
        assert.is_false(is_fun(1))
        assert.is_true(is_string "")
        assert.is_false(is_string(1))
        assert.is_true(is_number(1))
        assert.is_false(is_number "")
        assert.is_true(is_boolean(true))
        assert.is_false(is_boolean(1))
    end)

    it("should check is_list", function()
        assert.is_true(_.is_list {})
        assert.is_true(_.is_list { 1, 2, 3 })
        assert.is_true(_.is_list { 1, "a" })
        assert.is_false(_.is_list(vim.empty_dict()))
        assert.is_false(_.is_list { 1, 2, keyed = "value" })
        if vim.fn.has "nvim-0.10.0" == 1 then
            -- meh
            assert.is_false(_.is_list { 1, 2, nil, 3 })
        end
    end)
end)
