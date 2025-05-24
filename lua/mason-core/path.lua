local M = {}

---@param path_components string[]
---@return string
function M.concat(path_components)
    return vim.fs.normalize(table.concat(path_components, "/"))
end

---@path root_path string
---@path path string
function M.is_subdirectory(root_path, path)
    local root_path_normalized = vim.fs.normalize(root_path)
    local path_normalized = vim.fs.normalize(path)
    if path_normalized == root_path_normalized then
        return true
    end
    for dir in vim.fs.parents(path_normalized) do
        if root_path_normalized == dir then
            return true
        end
    end
    return false
end

local function find_closest_common_parent(from, to)
    local distance = 0
    for parent in vim.fs.parents(from) do
        if to:find(parent, 1, true) then
            return parent, distance
        else
            distance = distance + 1
        end
    end
    return "/", distance
end

function M.relative(from, to)
    local from_normalized = vim.fs.normalize(from)
    local to_normalized = vim.fs.normalize(to)

    local common_parent, distance = find_closest_common_parent(from_normalized, to_normalized)
    local relative_path_component = distance == 0 and "." or (".."):rep(distance, "/")
    return M.concat { relative_path_component, to_normalized:sub(#common_parent + 1) }
end

return M
