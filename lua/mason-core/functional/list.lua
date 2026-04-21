local data = require "mason-core.functional.data"
local fun = require "mason-core.functional.function"

local _ = {}

---@generic T
---@param list T[]
---@return T[]
_.reverse = function(list)
    local result = {}
    for i = #list, 1, -1 do
        result[#result + 1] = list[i]
    end
    return result
end

_.list_not_nil = function(...)
    local result = {}
    local args = data.table_pack(...)
    for i = 1, args.n do
        if args[i] ~= nil then
            result[#result + 1] = args[i]
        end
    end
    return result
end

---@generic T
---@param predicate fun(item: T): boolean
---@param list T[]
---@return T | nil
_.find_first = fun.curryN(function(predicate, list)
    local result
    for i = 1, #list do
        local entry = list[i]
        if predicate(entry) then
            return entry
        end
    end
    return result
end, 2)

---@generic T
---@param predicate fun(item: T): boolean
---@param list T[]
---@return boolean
_.any = fun.curryN(function(predicate, list)
    for i = 1, #list do
        if predicate(list[i]) then
            return true
        end
    end
    return false
end, 2)

---@generic T
---@param predicate fun(item: T): boolean
---@param list T[]
---@return boolean
_.all = fun.curryN(function(predicate, list)
    for i = 1, #list do
        if not predicate(list[i]) then
            return false
        end
    end
    return true
end, 2)

---@generic T
---@type fun(filter_fn: (fun(item: T): boolean), items: T[]): T[]
_.filter = fun.curryN(vim.tbl_filter, 2)

---@generic T, U
---@type fun(map_fn: (fun(item: T): U), items: T[]): U[]
_.map = fun.curryN(vim.tbl_map, 2)

---@param tbl table
---@return table
_.flatten = function(tbl)
    local result = {}
    --- @param _tbl table<any,any>
    local function _tbl_flatten(_tbl)
        local n = #_tbl
        for i = 1, n do
            local v = _tbl[i]
            if type(v) == "table" then
                _tbl_flatten(v)
            elseif v then
                table.insert(result, v)
            end
        end
    end
    _tbl_flatten(tbl)
    return result
end

---@generic T
---@param map_fn fun(item: T): Optional
---@param list T[]
---@return any[]
_.filter_map = fun.curryN(function(map_fn, list)
    local ret = {}
    for i = 1, #list do
        map_fn(list[i]):if_present(function(value)
            ret[#ret + 1] = value
        end)
    end
    return ret
end, 2)

---@generic T
---@param fn fun(item: T, index: integer)
---@param list T[]
_.each = fun.curryN(function(fn, list)
    for k, v in pairs(list) do
        fn(v, k)
    end
end, 2)

---@generic T
---@type fun(list: T[]): T[]
_.list_copy = _.map(fun.identity)

_.concat = fun.curryN(function(a, b)
    if type(a) == "table" then
        assert(type(b) == "table", "concat: expected table")
        return vim.list_extend(_.list_copy(a), b)
    elseif type(a) == "string" then
        assert(type(b) == "string", "concat: expected string")
        return a .. b
    end
end, 2)

---@generic T
---@param value T
---@param list T[]
---@return T[]
_.append = fun.curryN(function(value, list)
    local list_copy = _.list_copy(list)
    list_copy[#list_copy + 1] = value
    return list_copy
end, 2)

---@generic T
---@param value T
---@param list T[]
---@return T[]
_.prepend = fun.curryN(function(value, list)
    local list_copy = _.list_copy(list)
    table.insert(list_copy, 1, value)
    return list_copy
end, 2)

---@generic T
---@generic U
---@param keys T[]
---@param values U[]
---@return table<T, U>
_.zip_table = fun.curryN(function(keys, values)
    local res = {}
    for i, key in ipairs(keys) do
        res[key] = values[i]
    end
    return res
end, 2)

---@generic T
---@param offset number
---@param value T[]|string
---@return T|string|nil
_.nth = fun.curryN(function(offset, value)
    local index = offset < 0 and (#value + (offset + 1)) or offset
    if type(value) == "string" then
        return string.sub(value, index, index)
    else
        return value[index]
    end
end, 2)

_.head = _.nth(1)

---@generic T
---@param list T[]
---@return T?
_.last = function(list)
    return list[#list]
end

---@param value string|any[]
_.length = function(value)
    return #value
end

---@generic T
---@param comp fun(item: T): any
---@param list T[]
---@return T[]
_.sort_by = fun.curryN(function(comp, list)
    local copied_list = _.list_copy(list)
    table.sort(copied_list, function(a, b)
        return comp(a) < comp(b)
    end)
    return copied_list
end, 2)

---@param sep string
---@param list any[]
_.join = fun.curryN(function(sep, list)
    return table.concat(list, sep)
end, 2)

---@generic T
---@param id fun(item: T): any
---@param list T[]
---@return T[]
_.uniq_by = fun.curryN(function(id, list)
    local set = {}
    local result = {}
    for i = 1, #list do
        local item = list[i]
        local uniq_key = id(item)
        if not set[uniq_key] then
            set[uniq_key] = true
            table.insert(result, item)
        end
    end
    return result
end, 2)

---@generic T
---@param predicate fun(item: T): boolean
---@param list T[]
---@return T[][] # [T[], T[]]
_.partition = fun.curryN(function(predicate, list)
    local partitions = { {}, {} }
    for _, item in ipairs(list) do
        table.insert(partitions[predicate(item) and 1 or 2], item)
    end
    return partitions
end, 2)

---@generic T
---@param n integer
---@param list T[]
---@return T[]
_.take = fun.curryN(function(n, list)
    local result = {}
    for i = 1, math.min(n, #list) do
        result[#result + 1] = list[i]
    end
    return result
end, 2)

---@generic T
---@param n integer
---@param list T[]
---@return T[]
_.drop = fun.curryN(function(n, list)
    local result = {}
    for i = n + 1, #list do
        result[#result + 1] = list[i]
    end
    return result
end, 2)

---@generic T
---@param n integer
---@param list T[]
---@return T[]
_.drop_last = fun.curryN(function(n, list)
    local result = {}
    for i = 1, #list - n do
        result[#result + 1] = list[i]
    end
    return result
end, 2)

---@generic T, U
---@param fn fun(acc: U, item: T): U
---@param acc U
---@param list T[]
---@return U
_.reduce = fun.curryN(function(fn, acc, list)
    for i = 1, #list do
        acc = fn(acc, list[i])
    end
    return acc
end, 3)

---@generic T
---@param n integer
---@param list T[]
---@return T[][]
_.split_every = fun.curryN(function(n, list)
    assert(n > 0, "n needs to be greater than 0.")
    local res = {}
    local idx = 1
    while idx <= #list do
        table.insert(res, { unpack(list, idx, idx + n - 1) })
        idx = idx + n
    end
    return res
end, 2)

---@generic T, U
---@param index fun(item: T): U
---@param list T[]
---@return table<U, T>
_.index_by = fun.curryN(function(index, list)
    local res = {}
    for _, item in ipairs(list) do
        res[index(item)] = item
    end
    return res
end, 2)

return _
