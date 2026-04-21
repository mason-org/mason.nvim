local InstallContext = require "mason-core.installer.context"

local M = {}

---@return InstallContext
function M.context()
    return coroutine.yield(InstallContext.CONTEXT_REQUEST)
end

return M
