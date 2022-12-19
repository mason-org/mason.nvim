local a = require "mason-core.async"
local _ = require "mason-core.functional"
local Result = require "mason-core.result"
local process = require "mason-core.process"
local platform = require "mason-core.platform"
local log = require "mason-core.log"

---@alias JobSpawn table<string, async fun(opts: SpawnArgs): Result>
---@type JobSpawn
local spawn = {
    _flatten_cmd_args = _.compose(_.filter(_.complement(_.equals(vim.NIL))), _.flatten),
}

local function Failure(err, cmd)
    return Result.failure(setmetatable(err, {
        __tostring = function()
            return ("spawn: %s failed with exit code %s and signal %s. %s"):format(
                cmd,
                err.exit_code or "-",
                err.signal or "-",
                err.stderr or ""
            )
        end,
    }))
end

local exepath = _.memoize(function(cmd)
    if vim.in_fast_event() then
        a.scheduler()
    end
    local exepath = vim.fn.exepath(cmd)
    if exepath == "" then
        return nil
    else
        return exepath
    end
end, _.identity)

---@class SpawnArgs
---@field with_paths string[]? Paths to add to the PATH environment variable.
---@field env table<string, string>? Example { SOME_ENV = "value", SOME_OTHER_ENV = "some_value" }
---@field env_raw string[]? Example: { "SOME_ENV=value", "SOME_OTHER_ENV=some_value" }
---@field stdio_sink StdioSink? If provided, will be used to write to stdout and stderr.
---@field cwd string?
---@field on_spawn (fun(handle: luv_handle, stdio: luv_pipe[], pid: integer))? Will be called when the process successfully spawns.

setmetatable(spawn, {
    ---@param cmd string
    __index = function(self, cmd)
        ---@param args SpawnArgs
        return function(args)
            local cmd_args = self._flatten_cmd_args(args)
            local env = args.env

            if args.with_paths then
                env = env or {}
                env.PATH = process.extend_path(args.with_paths)
            end

            ---@type JobSpawnOpts
            local spawn_args = {
                stdio_sink = args.stdio_sink,
                cwd = args.cwd,
                env = env and process.graft_env(env) or args.env_raw,
                args = cmd_args,
            }

            local stdio
            if not spawn_args.stdio_sink then
                stdio = process.in_memory_sink()
                spawn_args.stdio_sink = stdio.sink
            end

            -- Ensure that the cmd is executable (only if PATH is not modified).
            if (env and env.PATH) == nil then
                local expanded_cmd = exepath(cmd)
                if expanded_cmd == nil then
                    log.fmt_debug("%s is not executable", cmd)
                    return Failure({
                        stderr = ("%s is not executable"):format(cmd),
                    }, cmd)
                end
                cmd = expanded_cmd
            end

            local _, exit_code, signal = a.wait(function(resolve)
                local handle, stdio, pid = process.spawn(cmd, spawn_args, resolve)
                if args.on_spawn and handle and stdio and pid then
                    args.on_spawn(handle, stdio, pid)
                end
            end)

            if exit_code == 0 and signal == 0 then
                return Result.success {
                    stdout = stdio and table.concat(stdio.buffers.stdout, "") or nil,
                    stderr = stdio and table.concat(stdio.buffers.stderr, "") or nil,
                }
            else
                return Failure({
                    exit_code = exit_code,
                    signal = signal,
                    stdout = stdio and table.concat(stdio.buffers.stdout, "") or nil,
                    stderr = stdio and table.concat(stdio.buffers.stderr, "") or nil,
                }, cmd)
            end
        end
    end,
})

return spawn
