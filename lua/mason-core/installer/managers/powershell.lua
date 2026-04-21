local _ = require "mason-core.functional"
local a = require "mason-core.async"
local process = require "mason-core.process"
local spawn = require "mason-core.spawn"

local M = {}

local PWSHOPT = {
    progress_preference = [[ $ProgressPreference = 'SilentlyContinue'; ]], -- https://stackoverflow.com/a/63301751
    security_protocol = [[ [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ]],
    error_action_preference = [[ $ErrorActionPreference = "Stop"; ]],
}

local powershell = _.lazy(function()
    a.scheduler()
    if vim.fn.executable "pwsh" == 1 then
        return "pwsh"
    else
        return "powershell"
    end
end)

---@async
---@param command string
---@param opts SpawnArgs?
---@param custom_spawn JobSpawn?
function M.command(command, opts, custom_spawn)
    opts = opts or {}
    ---@type JobSpawn
    local spawner = custom_spawn or spawn
    return spawner[powershell()](vim.tbl_extend("keep", {
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        PWSHOPT.error_action_preference .. PWSHOPT.progress_preference .. PWSHOPT.security_protocol .. command,
        env_raw = process.graft_env(opts.env or {}, { "PSMODULEPATH" }),
        on_spawn = function(_, stdio)
            local stdin = stdio[1]
            stdin:close()
        end,
    }, opts))
end

return M
