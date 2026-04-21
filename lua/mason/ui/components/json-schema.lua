-- Here be dragons
local Ui = require "mason-core.ui"
local _ = require "mason-core.functional"
local settings = require "mason.settings"

local property_type_highlights = {
    ["string"] = "String",
    ["string[]"] = "String",
    ["boolean"] = "Boolean",
    ["number"] = "Number",
    ["number[]"] = "Number",
    ["integer"] = "Number",
    ["integer[]"] = "Number",
}

local function resolve_type(property_schema)
    if _.is_list(property_schema.type) then
        return table.concat(property_schema.type, " | ")
    elseif property_schema.type == "array" then
        if property_schema.items then
            return ("%s[]"):format(property_schema.items.type)
        else
            return property_schema.type
        end
    end

    return property_schema.type or "N/A"
end

local function Indent(indentation, children)
    -- create a list table with as many "INDENT" entries as the numeric indentation variable
    local indent = {}
    for _ = 1, indentation do
        table.insert(indent, "INDENT")
    end
    return Ui.CascadingStyleNode(indent, children)
end

---@param pkg Package
---@param schema_id string
---@param state UiPackageState
---@param schema table
---@param key string?
---@param level number?
---@param key_width number? The width the key should occupate in the UI to produce an even column.
---@param compound_key string?
local function JsonSchema(pkg, schema_id, state, schema, key, level, key_width, compound_key)
    level = level or 0
    compound_key = ("%s%s"):format(compound_key or "", key or "")
    local toggle_expand_keybind = Ui.Keybind(
        settings.current.ui.keymaps.toggle_package_expand,
        "TOGGLE_JSON_SCHEMA_KEY",
        { package = pkg, schema_id = schema_id, key = compound_key }
    )
    local node_is_expanded = state.expanded_json_schema_keys[schema_id][compound_key]
    local key_prefix = node_is_expanded and "↓ " or "→ "

    if (schema.type == "object" or schema.type == nil) and schema.properties then
        local nodes = {}
        if key then
            -- This node belongs to some parent object - render a heading for it.
            -- It'll act as the anchor for its children.
            local heading = Ui.HlTextNode {
                key_prefix .. key,
                node_is_expanded and "Bold" or "",
            }
            nodes[#nodes + 1] = heading
            nodes[#nodes + 1] = toggle_expand_keybind
        end

        -- All level 0 nodes are expanded by default - otherwise we'd not render anything at all
        if level == 0 or node_is_expanded then
            local max_property_length = 0
            local sorted_properties = {}
            for property in pairs(schema.properties) do
                max_property_length = math.max(max_property_length, vim.api.nvim_strwidth(property))
                sorted_properties[#sorted_properties + 1] = property
            end
            table.sort(sorted_properties)
            for _, property in ipairs(sorted_properties) do
                nodes[#nodes + 1] = Indent(level, {
                    JsonSchema(
                        pkg,
                        schema_id,
                        state,
                        schema.properties[property],
                        property,
                        level + 1,
                        max_property_length,
                        compound_key
                    ),
                })
            end
        end
        return Ui.Node(nodes)
    elseif schema.oneOf then
        local nodes = {}
        for i, alternative_schema in ipairs(schema.oneOf) do
            nodes[#nodes + 1] = JsonSchema(
                pkg,
                schema_id,
                state,
                alternative_schema,
                ("%s (alt. %d)"):format(key, i),
                level,
                key_width,
                compound_key
            )
        end
        return Ui.Node(nodes)
    elseif _.is_list(schema) then
        return Ui.Node(_.map(function(sub_schema)
            return JsonSchema(pkg, schema_id, state, sub_schema)
        end, schema))
    elseif level > 0 then -- Leaf nodes cannot occupy the root level.
        -- Leaf node (aka any type that isn't an object).
        local type = resolve_type(schema)
        local heading
        local label = (key_prefix .. key .. (" "):rep(key_width or 0)):sub(1, key_width + 5) -- + 5 to account for key_prefix plus some extra whitespace
        if schema.default ~= nil then
            heading = Ui.HlTextNode {
                {
                    {
                        label,
                        node_is_expanded and "Bold" or "",
                    },
                    {
                        " default: ",
                        "Comment",
                    },
                    {
                        vim.json.encode(schema.default),
                        property_type_highlights[type] or "MasonMuted",
                    },
                },
            }
        else
            heading = Ui.HlTextNode {
                label,
                node_is_expanded and "Bold" or "",
            }
        end

        return Ui.Node {
            heading,
            toggle_expand_keybind,
            Ui.When(node_is_expanded, function()
                local description = _.map(function(line)
                    return { { line, "Comment" } }
                end, vim.split(schema.description or "No description available.", "\n"))

                local type_highlight = property_type_highlights[type] or "MasonMuted"

                local table_rows = {
                    { { "type", "MasonMuted" }, { type, type_highlight } },
                }

                if _.is_list(schema.enum) then
                    for idx, enum in ipairs(schema.enum) do
                        local enum_description = ""
                        if schema.enumDescriptions and schema.enumDescriptions[idx] then
                            enum_description = "- " .. schema.enumDescriptions[idx]
                        end
                        table_rows[#table_rows + 1] = {
                            { idx == 1 and "possible values" or "", "MasonMuted" },
                            { vim.json.encode(enum), type_highlight },
                            { enum_description, "Comment" },
                        }
                    end
                end

                return Indent(level, {
                    Ui.HlTextNode(description),
                    Ui.Table(table_rows),
                })
            end),
        }
    else
        return Ui.Node {}
    end
end

return JsonSchema
