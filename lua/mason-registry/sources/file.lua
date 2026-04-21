local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local async_uv = require "mason-core.async.uv"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local process = require "mason-core.process"
local spawn = require "mason-core.spawn"
local util = require "mason-registry.sources.util"

---@class FileRegistrySourceSpec
---@field id string
---@field path string

---@class FileRegistrySource : RegistrySource
---@field spec FileRegistrySourceSpec
---@field root_dir string
---@field buffer { specs: RegistryPackageSpec[], instances: table<string, Package> }?
local FileRegistrySource = {}
FileRegistrySource.__index = FileRegistrySource

---@param spec FileRegistrySourceSpec
function FileRegistrySource:new(spec)
    ---@type FileRegistrySource
    local instance = {}
    setmetatable(instance, self)
    instance.id = spec.id
    instance.spec = spec
    return instance
end

function FileRegistrySource:is_installed()
    return self.buffer ~= nil
end

---@return RegistryPackageSpec[]
function FileRegistrySource:get_all_package_specs()
    return _.filter_map(util.map_registry_spec, self:get_buffer().specs)
end

---@param specs RegistryPackageSpec[]
function FileRegistrySource:reload(specs)
    self.buffer = _.assoc("specs", specs, self.buffer or {})
    self.buffer.instances = _.compose(
        _.index_by(_.prop "name"),
        _.map(util.hydrate_package(self, self.buffer.instances or {}))
    )(self:get_all_package_specs())
    return self.buffer
end

function FileRegistrySource:get_buffer()
    return self.buffer or {
        specs = {},
        instances = {},
    }
end

---@param pkg_name string
---@return Package?
function FileRegistrySource:get_package(pkg_name)
    return self:get_buffer().instances[pkg_name]
end

function FileRegistrySource:get_all_package_names()
    return _.map(_.prop "name", self:get_all_package_specs())
end

---@async
function FileRegistrySource:install()
    return Result.try(function(try)
        a.scheduler()
        if vim.fn.executable "yq" ~= 1 then
            return Result.failure "yq is not installed."
        end
        local yq = vim.fn.exepath "yq"

        local registry_dir = vim.fn.expand(self.spec.path) --[[@as string]]
        local packages_dir = path.concat { registry_dir, "packages" }
        if not fs.async.dir_exists(registry_dir) then
            return Result.failure(("Directory %s does not exist."):format(registry_dir))
        end

        if not fs.async.dir_exists(packages_dir) then
            return Result.failure "packages/ directory is missing."
        end

        ---@type ReaddirEntry[]
        local entries = _.filter(_.prop_eq("type", "directory"), fs.async.readdir(packages_dir))

        local streaming_parser = coroutine.wrap(function()
            local buffer = ""
            while true do
                local delim = buffer:find("\n", 1, true)
                if delim then
                    local content = buffer:sub(1, delim - 1)
                    buffer = buffer:sub(delim + 1)
                    local chunk = coroutine.yield(content)
                    buffer = buffer .. chunk
                else
                    local chunk = coroutine.yield()
                    buffer = buffer .. chunk
                end
            end
        end)

        -- Initialize parser coroutine.
        streaming_parser()

        local specs = {}
        local stderr_buffer = {}
        local parse_failures = 0

        ---@param raw_spec string
        local function handle_spec(raw_spec)
            local ok, result = pcall(vim.json.decode, raw_spec)
            if ok then
                specs[#specs + 1] = result
            else
                log.fmt_error("Failed to parse JSON, err=%s, json=%s", result, raw_spec)
                parse_failures = parse_failures + 1
            end
        end

        try(spawn
            [yq]({
                "-I0", -- output one document per line
                { "-o", "json" },
                stdio_sink = process.StdioSink:new {
                    stdout = function(chunk)
                        local raw_spec = streaming_parser(chunk)
                        if raw_spec then
                            handle_spec(raw_spec)
                        end
                    end,
                    stderr = function(chunk)
                        stderr_buffer[#stderr_buffer + 1] = chunk
                    end,
                },
                on_spawn = a.scope(function(_, stdio)
                    local stdin = stdio[1]
                    for _, entry in ipairs(entries) do
                        local contents = fs.async.read_file(path.concat { packages_dir, entry.name, "package.yaml" })
                        async_uv.write(stdin, contents)
                    end
                    async_uv.shutdown(stdin)
                    async_uv.close(stdin)
                end),
            })
            :map_err(function()
                return ("Failed to parse package YAML: %s"):format(table.concat(stderr_buffer, ""))
            end))

        -- Exhaust parser coroutine.
        for raw_spec in
            function()
                return streaming_parser ""
            end
        do
            handle_spec(raw_spec)
        end

        if parse_failures > 0 then
            return Result.failure(("Failed to parse %d packages."):format(parse_failures))
        end

        return specs
    end)
        :on_success(function(specs)
            self:reload(specs)
        end)
        :on_failure(function(err)
            log.fmt_error("Failed to install registry %s. %s", self, err)
        end)
end

function FileRegistrySource:get_display_name()
    if self:is_installed() then
        return ("local: %s"):format(self.spec.path)
    else
        return ("local: %s [uninstalled]"):format(self.spec.path)
    end
end

function FileRegistrySource:serialize()
    return {
        proto = "file",
        path = self.id,
    }
end

---@param other FileRegistrySource
function FileRegistrySource:is_same_location(other)
    return vim.fn.expand(self.spec.path) == vim.fn.expand(other.spec.path)
end

function FileRegistrySource:__tostring()
    return ("FileRegistrySource(path=%s)"):format(self.spec.path)
end

return FileRegistrySource
