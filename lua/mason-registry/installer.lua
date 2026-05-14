local a = require "mason-core.async"
local log = require "mason-core.log"
local OneShotChannel = require("mason-core.async.control").OneShotChannel
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local fs = require "mason-core.fs"

local M = {}

---@param sources LazySourceCollection
---@param time integer
local function update_registry_state(sources, time)
    log.trace("Updating registry state", sources, time)
    local state_file = sources:get_state_file()
    local dir = vim.fn.fnamemodify(state_file, ":h")
    if not fs.sync.dir_exists(dir) then
        fs.sync.mkdirp(dir)
    end
    fs.sync.write_file(state_file, _.join("\n", { sources:checksum(), tostring(time) }))
end

---@async
---@param sources LazySourceCollection
---@param on_progress fun(finished: RegistrySource[], all: RegistrySource[])
---@return Result # Result<RegistrySource[]>
function M.install(sources, on_progress)
    log.debug("Installing registries.", sources)
    assert(not sources.install_channel, "Cannot install when channel is active.")
    sources.install_channel = OneShotChannel:new()

    local finished_registries = {}
    local registries = sources:to_list { include_uninstalled = true, include_synthesized = false }

    local results = {
        a.wait_all(_.map(
            ---@param source RegistrySource
            function(source)
                return function()
                    log.trace("Installing registry.", source)
                    return source
                        :install()
                        :map(_.always(source))
                        :map_err(function(err)
                            return ("%s failed to install: %s"):format(source, err)
                        end)
                        :on_success(function()
                            table.insert(finished_registries, source)
                            on_progress(finished_registries, registries)
                        end)
                end
            end,
            registries
        )),
    }

    local any_failed = _.any(Result.is_failure, results)

    if any_failed then
        local unwrap_failures = _.compose(_.map(Result.err_or_nil), _.filter(Result.is_failure))
        local result = Result.failure(unwrap_failures(results))
        sources.install_channel:send(result)
        sources.install_channel = nil
        return result
    else
        local result = Result.success(_.map(Result.get_or_nil, results))
        a.scheduler()
        update_registry_state(sources, os.time())
        sources.install_channel:send(result)
        sources.install_channel = nil
        return result
    end
end

return M
