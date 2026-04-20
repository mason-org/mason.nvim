local fun = require "mason-core.functional.function"

local _ = {}

---@param pattern string
---@param str string
_.matches = fun.curryN(function(pattern, str)
    return str:match(pattern) ~= nil
end, 2)

_.match = fun.curryN(function(pattern, str)
    return { str:match(pattern) }
end, 2)

---@param template string
---@param str string
_.format = fun.curryN(function(template, str)
    return template:format(str)
end, 2)

---@param sep string
---@param str string
_.split = fun.curryN(function(sep, str)
    return vim.split(str, sep)
end, 2)

---@param pattern string
---@param repl string|function|table
---@param str string
_.gsub = fun.curryN(function(pattern, repl, str)
    return string.gsub(str, pattern, repl)
end, 3)

_.trim = fun.curryN(function(str)
    return vim.trim(str)
end, 1)

---https://github.com/nvim-lua/nvim-package-specification/blob/93475e47545b579fd20b6c5ce13c4163e7956046/lua/packspec/schema.lua#L8-L37
---@param str string
---@return string
_.dedent = fun.curryN(function(str)
    local lines = {}
    local indent = nil

    for line in str:gmatch "[^\n]*\n?" do
        if indent == nil then
            if not line:match "^%s*$" then
                -- save pattern for indentation from the first non-empty line
                indent, line = line:match "^(%s*)(.*)$"
                indent = "^" .. indent .. "(.*)$"
                table.insert(lines, line)
            end
        else
            if line:match "^%s*$" then
                -- replace empty lines with a single newline character.
                -- empty lines are handled separately to allow the
                -- closing "]]" to be one indentation level lower.
                table.insert(lines, "\n")
            else
                -- strip indentation on non-empty lines
                line = assert(line:match(indent), "inconsistent indentation")
                table.insert(lines, line)
            end
        end
    end

    lines = table.concat(lines)
    -- trim trailing whitespace
    return lines:match "^(.-)%s*$"
end, 1)

---@param prefix string
---@str string
_.starts_with = fun.curryN(function(prefix, str)
    return vim.startswith(str, prefix)
end, 2)

---@param str string
_.to_upper = function(str)
    return str:upper()
end

---@param str string
_.to_lower = function(str)
    return str:lower()
end

---@param pattern string
---@param str string
_.trim_start_matches = fun.curryN(function(pattern, str)
    for i = 1, #str do
        if not str:sub(i, i):match(pattern) then
            return str:sub(i)
        end
    end
    return str
end, 2)

---@param pattern string
---@param str string
_.trim_end_matches = fun.curryN(function(pattern, str)
    for i = #str, 1, -1 do
        if not str:sub(i, i):match(pattern) then
            return str:sub(1, i)
        end
    end
    return str
end, 2)

_.strip_prefix = fun.curryN(function(prefix_pattern, str)
    if str == nil then
        return str
    end
    if #prefix_pattern > #str then
        return str
    end
    for i = 1, #prefix_pattern do
        if str:sub(i, i) ~= prefix_pattern:sub(i, i) then
            return str
        end
    end
    return str:sub(#prefix_pattern + 1)
end, 2)

_.strip_suffix = fun.curryN(function(suffix_pattern, str)
    if str == nil then
        return str
    end
    if #suffix_pattern > #str then
        return str
    end
    for i = 1, #suffix_pattern do
        if str:sub(-i, -i) ~= suffix_pattern:sub(-i, -i) then
            return str
        end
    end
    return str:sub(1, -#suffix_pattern - 1)
end, 2)

return _
