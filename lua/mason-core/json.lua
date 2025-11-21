local M = {}

---@param depth integer
local function indent(depth)
    return string.rep(" ", depth * 2)
end

---@param str string
local function json_escape_string(str)
    local escaped = str:gsub('([\b\f\n\r\t\\"])', {
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
        ["\\"] = "\\\\",
        ['"'] = '\\"',
    })
    return escaped
end

---@param value any
---@param depth integer
---@param buffer string[]
local function _pretty_json(value, depth, buffer)
    local typ = type(value)
    if typ == "number" or typ == "boolean" then
        buffer[#buffer + 1] = tostring(value)
    elseif typ == "string" then
        buffer[#buffer + 1] = '"' .. json_escape_string(value) .. '"'
    elseif typ == "table" then
        -- we also check that metatable is nil, mainly to ensure vim.empty_dict() values doesn't serialize as array
        if getmetatable(value) == nil and vim.tbl_islist(value) then
            if #value == 0 then
                buffer[#buffer + 1] = "[]"
            else
                local should_split_lines = #value > 3
                local prefix = should_split_lines and ("\n" .. indent(depth + 1)) or ""
                local suffix = should_split_lines and "," or ", "
                buffer[#buffer + 1] = "["
                for idx, item in ipairs(value) do
                    buffer[#buffer + 1] = prefix
                    _pretty_json(item, depth + 1, buffer)
                    if idx ~= #value then
                        buffer[#buffer + 1] = suffix
                    end
                end
                if should_split_lines then
                    buffer[#buffer + 1] = "\n"
                end
                buffer[#buffer + 1] = "]"
            end
        else
            local keys = vim.tbl_keys(value)
            if #keys == 0 then
                buffer[#buffer + 1] = "{}"
            else
                table.sort(keys)
                buffer[#buffer + 1] = "{\n"
                for idx, key in ipairs(keys) do
                    buffer[#buffer + 1] = indent(depth + 1)
                    buffer[#buffer + 1] = '"' .. json_escape_string(tostring(key)) .. '": '
                    _pretty_json(value[key], depth + 1, buffer)
                    if idx ~= #keys then
                        buffer[#buffer + 1] = ","
                    end
                    buffer[#buffer + 1] = "\n"
                end
                buffer[#buffer + 1] = indent(depth)
                buffer[#buffer + 1] = "}"
            end
        end
    elseif typ == "nil" or value == vim.NIL then
        buffer[#buffer + 1] = "null"
    end
end

function M.encode_formatted(value)
    local buffer = {}
    _pretty_json(value, 0, buffer)
    return table.concat(buffer)
end

return M
