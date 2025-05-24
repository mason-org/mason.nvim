local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local log = require "mason-core.log"
local platform = require "mason-core.platform"
local process = require "mason-core.process"

local is_not_nil = _.complement(_.equals(vim.NIL))

---@alias JobSpawn table<string, async fun(opts: SpawnArgs): Result>
---@type JobSpawn
local spawn = {
    _flatten_cmd_args = _.compose(_.filter(is_not_nil), _.flatten),
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

local has_path = _.any(_.starts_with "PATH=")

---@class SpawnArgs
---@field with_paths string[]? Paths to add to the PATH environment variable.
---@field env table<string, string>? Example { SOME_ENV = "value", SOME_OTHER_ENV = "some_value" }
---@field env_raw string[]? Example: { "SOME_ENV=value", "SOME_OTHER_ENV=some_value" }
---@field stdio_sink StdioSink? If provided, will be used to write to stdout and stderr.
---@field cwd string?
---@field on_spawn (fun(handle: luv_handle, stdio: luv_pipe[], pid: integer))? Will be called when the process successfully spawns.

setmetatable(spawn, {
    ---@param canonical_cmd string
    __index = function(self, canonical_cmd)
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

            if not spawn_args.stdio_sink then
                spawn_args.stdio_sink = process.BufferedSink:new()
            end

            local cmd = canonical_cmd

            -- Find the executable path via vim.fn.exepath on Windows because libuv fails to resolve certain executables
            -- in PATH.
            if platform.is.win and (spawn_args.env and has_path(spawn_args.env)) == nil then
                a.scheduler()
                local expanded_cmd = vim.fn.exepath(canonical_cmd)
                if expanded_cmd ~= "" then
                    cmd = expanded_cmd
                end
            end

            local _, exit_code, signal = a.wait(function(resolve)
                local handle, stdio, pid = process.spawn(cmd, spawn_args, resolve)
                if args.on_spawn and handle and stdio and pid then
                    args.on_spawn(handle, stdio, pid)
                end
            end)

            if exit_code == 0 and signal == 0 then
                if getmetatable(spawn_args.stdio_sink) == process.BufferedSink then
                    local sink = spawn_args.stdio_sink --[[@as BufferedSink]]
                    return Result.success {
                        stdout = table.concat(sink.buffers.stdout, "") or nil,
                        stderr = table.concat(sink.buffers.stderr, "") or nil,
                    }
                else
                    return Result.success()
                end
            else
                if getmetatable(spawn_args.stdio_sink) == process.BufferedSink then
                    local sink = spawn_args.stdio_sink --[[@as BufferedSink]]
                    return Failure({
                        exit_code = exit_code,
                        signal = signal,
                        stdout = table.concat(sink.buffers.stdout, "") or nil,
                        stderr = table.concat(sink.buffers.stderr, "") or nil,
                    }, canonical_cmd)
                else
                    return Failure({
                        exit_code = exit_code,
                        signal = signal,
                    }, canonical_cmd)
                end
            end
        end
    end,
})

return spawn
