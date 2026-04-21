" Avoid neovim/neovim#11362
set display=lastline
set directory=""
set noswapfile

let $mason = getcwd()
let $test_helpers = getcwd() .. "/tests/helpers"
let $dependencies = getcwd() .. "/dependencies"

set rtp^=$mason,$test_helpers
set packpath=$dependencies

packloadall

lua require("luassertx")

lua <<EOF
mockx = {
    just_runs = function() end,
    returns = function(val)
        return function()
            return val
        end
    end,
    throws = function(exception)
        return function()
            error(exception, 2)
        end
    end,
}
EOF

lua <<EOF
local path = require "mason-core.path"

require("mason").setup {
    log_level = vim.log.levels.DEBUG,
    install_root_dir = vim.env.INSTALL_ROOT_DIR or path.concat { vim.loop.cwd(), "tests", "fixtures", "mason"},
    registries = {
        "lua:dummy-registry.index"
    }
}

require("mason-registry").refresh()
EOF

function! RunTests() abort
    lua <<EOF
    require("plenary.test_harness").test_directory(os.getenv("FILE") or "./tests", {
        minimal_init = vim.fn.getcwd() .. "/tests/minimal_init.vim",
        sequential = true,
    })
EOF
endfunction
