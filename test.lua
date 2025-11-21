local _ = require "mason-core.functional"

local parser = function(thread)
    local function resume(val)
        local ok, value = coroutine.resume(thread, val)
        if not ok then
            error(value)
        else
            return value
        end
    end

    local buffer = ""
    local fd = vim.uv.fs_open(
        vim.fs.normalize "~/.config/nvim/pack/vendor/start/mason.nvim/mason.lock",
        "r",
        tonumber("666", 8)
    )

    local size = 100
    local offset = 0

    resume()

    while true do
        local read = vim.uv.fs_read(fd, size, offset)
        offset = offset + size
        if read == "" then
            vim.uv.fs_close(fd)
            -- EOF
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

local function main()
    local thread = coroutine.create(function()
        local result = {}
        local cursor = { result }

        for line_no, line in buffered() do
            local indentation = #line:match "^%s*"
            local indent_level = indentation / 2
            local current_indent_level = (#cursor - 1)
            if math.fmod(indentation, 2) ~= 0 or indent_level > current_indent_level then
                error(("Invalid indentation on line %s."):format(line_no))
            end
            if indent_level < current_indent_level then
                table.remove(cursor)
            end

            if line == "" then
                -- empty line
            elseif _.matches("^%s*#", line) then
                -- comment
            else
                local key, val = unpack(_.split(" ", line:sub(indentation + 1)))
                if val then
                    cursor[#cursor][key] = val
                else
                    cursor[#cursor][key] = {}
                    cursor[#cursor + 1] = cursor[#cursor][key]
                end
            end
        end

        return result
    end)
    vim.print(parser(thread))
end

main()
