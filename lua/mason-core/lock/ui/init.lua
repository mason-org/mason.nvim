return {
    close = function()
        local instance = require "mason-core.lock.ui.instance"
        instance.close()
    end,
    open = function()
        local instance = require "mason-core.lock.ui.instance"
        instance.open()
    end,
    restore = function ()
        local instance = require "mason-core.lock.ui.instance"
        instance.restore()
    end
}
