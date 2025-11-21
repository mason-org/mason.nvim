local _ = require "mason-core.functional"
local uv = vim.uv

---@param str string
---@param char string
local function split_once_left(str, char)
    for i = 1, #str do
        if str:sub(i, i) == char then
            local segment = str:sub(1, i - 1)
            return segment, str:sub(i + 1)
        end
    end
    return str
end

local parser = function(thread, file)
    local function resume(val)
        local ok, value = coroutine.resume(thread, val)
        if not ok then
            error(value)
        else
            return value
        end
    end

    local buffer = ""
    local fd = uv.fs_open(file, "r", tonumber("666", 8))

    local size = 100
    local offset = 0

    resume()

    while true do
        local read = uv.fs_read(fd, size, offset)
        offset = offset + size
        if read == "" then
            -- EOF
            uv.fs_close(fd)
            return resume(nil)
        else
            resume(read)
        end
    end
end

local function buffered()
    local split = _.split "\n"
    local buffer = {}
    local tail = nil
    local exhausted = false
    local i = 0
    return function()
        if #buffer == 0 and not exhausted then
            local chunk = coroutine.yield()
            if chunk then
                local lines = split(chunk)
                if tail then
                    lines[1] = tail .. lines[1]
                end
                tail = table.remove(lines)
                buffer = _.reverse(lines)
            else
                exhausted = true
                if tail then
                    buffer = { tail }
                end
                tail = nil
            end
        end
        local line = table.remove(buffer)
        if line then
            i = i + 1
            return i, line
        else
            return nil
        end
    end
end

local function bajs()
    local thread = coroutine.create(function()
        local header = nil
        local body = {}
        local cursor = { body }

        for line_no, line in buffered() do
            local indentation = #line:match "^%s*"
            local indent_level = indentation / 2
            local current_indent_level = (#cursor - 1)
            if math.fmod(indentation, 2) ~= 0 or indent_level > current_indent_level then
                print(indentation, indent_level, current_indent_level)
                error(("Invalid indentation on line %s."):format(line_no))
            end

            if _.matches("^%s*$", line) then
                -- empty line
            elseif _.matches("^%s*#", line) then
                -- comment
            elseif _.matches("^---$", line) then
                -- header
                assert(header == nil, ("Duplicate headers in document on line %s."):format(line_no))
                header = body
                body = {}
                cursor = { body }
            else
                if indent_level < current_indent_level then
                    cursor = _.take(indent_level + 1, cursor)
                end
                local key, val = split_once_left(line:sub(indentation + 1), " ")
                if val then
                    cursor[#cursor][key] = val
                else
                    cursor[#cursor][key] = {}
                    cursor[#cursor + 1] = cursor[#cursor][key]
                end
            end
        end

        return {
            header = header,
            body = body,
        }
    end)
    return parser(thread, vim.fs.normalize "~/.config/nvim/pack/vendor/start/mason.nvim/mason.lock")
end

main()
