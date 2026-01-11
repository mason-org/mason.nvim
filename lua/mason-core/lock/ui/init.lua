return {
    close = function ()
        local api = require "mason-core.lock.ui.instance"
        api.close()
    end,
    open = function ()
        local api = require "mason-core.lock.ui.instance"
        api.open()
    end,
}
