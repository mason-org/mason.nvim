local _ = require "mason-core.functional"
local log = require "mason-core.log"

---@class RegistrySource
---@field id string
---@field system boolean
---@field get_package fun(self: RegistrySource, pkg_name: string): Package?
---@field get_all_package_names fun(self: RegistrySource): string[]
---@field get_all_package_specs fun(self: RegistrySource): RegistryPackageSpec[]
---@field get_display_name fun(self: RegistrySource): string
---@field is_installed fun(self: RegistrySource): boolean
---@field install fun(self: RegistrySource): Result
---@field serialize fun(self: RegistrySource): InstallReceiptRegistry
---@field is_same_location fun(self: RegistrySource, other: RegistrySource): boolean

---@alias RegistrySourceType '"github"' | '"lua"' | '"file"' | '"synthesized"'

---@class LazySource
---@field type RegistrySourceType
---@field id string
---@field init fun(id: string, system: boolean): RegistrySource
---@field system boolean
local LazySource = {}
LazySource.__index = LazySource

---@param id string
---@param system boolean
function LazySource.GitHub(id, system)
    local namespace, name = id:match "^(.+)/(.+)$"
    if not namespace or not name then
        error(("Failed to parse repository from GitHub registry: %q"):format(id), 0)
    end
    local name, version = unpack(vim.split(name, "@"))
    local GitHubRegistrySource = require "mason-registry.sources.github"
    return GitHubRegistrySource:new({
        id = id,
        namespace = namespace,
        name = name,
        version = version,
    }, system)
end

---@param id string
---@param system boolean
function LazySource.Lua(id, system)
    local LuaRegistrySource = require "mason-registry.sources.lua"
    return LuaRegistrySource:new({
        id = id,
        mod = id,
    }, system)
end

---@param id string
---@param system boolean
function LazySource.File(id, system)
    local FileRegistrySource = require "mason-registry.sources.file"
    return FileRegistrySource:new({
        id = id,
        path = id,
    }, system)
end

function LazySource.Synthesized()
    local SynthesizedSource = require "mason-registry.sources.synthesized"
    return SynthesizedSource:new()
end

---@param type RegistrySourceType
---@param id string
---@param init fun(id: string): RegistrySource
---@param system boolean
function LazySource:new(type, id, init, system)
    ---@type LazySource
    local instance = setmetatable({}, self)
    instance.type = type
    instance.id = id
    instance.init = init
    instance.system = system
    return instance
end

function LazySource:get()
    if not self.instance then
        self.instance = self.init(self.id, self.system)
    end
    return self.instance
end

---TODO this is pulling in a bunch of extra modules at startup due to unique_insert
---@param other LazySource
function LazySource:is_same_location(other)
    if self.type == other.type then
        return self:get():is_same_location(other:get())
    end
    return false
end

function LazySource:get_full_id()
    return ("%s:%s"):format(self.type, self.id)
end

function LazySource:__tostring()
    return ("LazySource(type=%s, id=%s)"):format(self.type, self.id)
end

---@param str string
local function split_once_left(str, char)
    for i = 1, #str do
        if str:sub(i, i) == char then
            local segment = str:sub(1, i - 1)
            return segment, str:sub(i + 1)
        end
    end
    return str
end

---@param registry_id string
---@param system boolean
local function parse(registry_id, system)
    local type, id = split_once_left(registry_id, ":")
    assert(id, ("Malformed registry %q"):format(registry_id))
    if type == "github" then
        return LazySource:new(type, id, LazySource.GitHub, system)
    elseif type == "lua" then
        return LazySource:new(type, id, LazySource.Lua, system)
    elseif type == "file" then
        return LazySource:new(type, id, LazySource.File, system)
    end
    error(("Unknown registry type: %s"):format(type))
end

---@class LazySourceCollection
---@field state_file string
---@field system boolean?
---@field list LazySource[]
---@field synthesized LazySource
---@field install_channel OneShotChannel?
local LazySourceCollection = {}
LazySourceCollection.__index = LazySourceCollection

---@return LazySourceCollection
---@param state_file string
---@param system boolean?
function LazySourceCollection:new(state_file, system)
    ---@type LazySourceCollection
    local instance = {}
    setmetatable(instance, self)
    instance.state_file = state_file
    instance.system = system
    instance.list = {}
    instance.synthesized = LazySource:new("synthesized", "synthesized", LazySource.Synthesized)
    return instance
end

---@return { checksum: string, timestamp: integer }?
function LazySourceCollection:get_install_state()
    local fs = require "mason-core.fs"
    if fs.sync.file_exists(self.state_file) then
        local parse_state_file =
            _.compose(_.evolve { timestamp = tonumber }, _.zip_table { "checksum", "timestamp" }, _.split "\n")
        return parse_state_file(fs.sync.read_file(self.state_file))
    end
end

function LazySourceCollection:get_state_file()
    return self.state_file
end

---@param registry string
function LazySourceCollection:append(registry)
    self:unique_insert(parse(registry, not not self.system))
    return self
end

---@param registry string
function LazySourceCollection:prepend(registry)
    self:unique_insert(parse(registry, not not self.system), 1)
    return self
end

---@param source LazySource
---@param idx? integer
function LazySourceCollection:unique_insert(source, idx)
    idx = idx or #self.list + 1
    if idx > 1 then
        for i = 1, math.min(idx, #self.list) do
            if self.list[i]:is_same_location(source) then
                log.fmt_warn(
                    "Ignoring duplicate registry entry %s (duplicate of %s)",
                    source:get_full_id(),
                    self.list[i]:get_full_id()
                )
                return
            end
        end
    end
    for i = #self.list, idx, -1 do
        if self.list[i]:is_same_location(source) then
            table.remove(self.list, i)
        end
    end
    table.insert(self.list, idx, source)
end

function LazySourceCollection:is_all_installed()
    for source in self:iterate { include_uninstalled = true } do
        if not source:is_installed() then
            return false
        end
    end
    return true
end

function LazySourceCollection:checksum()
    ---@type string[]
    local registry_ids = vim.tbl_map(
        ---@param source LazySource
        function(source)
            return source.id
        end,
        self.list
    )
    table.sort(registry_ids)
    return vim.fn.sha256(table.concat(registry_ids, ""))
end

---@alias LazySourceCollectionIterate { include_uninstalled?: boolean, include_synthesized?: boolean }

---@param opts? LazySourceCollectionIterate
function LazySourceCollection:iterate(opts)
    opts = opts or {}

    local idx = 1
    return function()
        while idx <= #self.list do
            local source = self.list[idx]:get()
            idx = idx + 1
            if opts.include_uninstalled or source:is_installed() then
                return source
            end
        end

        -- We've exhausted the true registry sources, fall back to the synthesized registry source.
        if idx == #self.list + 1 and opts.include_synthesized ~= false then
            idx = idx + 1
            return self.synthesized:get()
        end
    end
end

---@param registry RegistrySource
function LazySourceCollection:contains(registry)
    for _, lazy_source in ipairs(self.list) do
        local reg = lazy_source:get()
        if getmetatable(reg) == getmetatable(registry) and registry:is_same_location(reg) then
            return true
        end
    end
    return false
end

---@param opts? LazySourceCollectionIterate
function LazySourceCollection:to_list(opts)
    opts = opts or {}
    local list = {}
    for source in self:iterate(opts) do
        table.insert(list, source)
    end
    return list
end

---@param idx integer
function LazySourceCollection:get(idx)
    return self.list[idx]
end

function LazySourceCollection:size()
    return #self.list
end

function LazySourceCollection:__tostring()
    return ("LazySourceCollection(list={%s})"):format(table.concat(vim.tbl_map(tostring, self.list), ", "))
end

return LazySourceCollection
