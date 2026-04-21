local _ = require "mason-core.functional"
local fetch = require "mason-core.fetch"

local api = {}

-- https://github.com/mason-org/mason-registry-api
local BASE_URL = "https://api.mason-registry.dev"

local stringify_params = _.compose(_.join "&", _.map(_.join "="), _.sort_by(_.head), _.to_pairs)

---@alias ApiFetchOpts { params: table<string, any>? }

---@async
---@param path string
---@param opts ApiFetchOpts?
---@return Result # JSON decoded response.
function api.get(path, opts)
    if opts and opts.params then
        local params = stringify_params(opts.params)
        path = ("%s?%s"):format(path, params)
    end
    return fetch(("%s%s"):format(BASE_URL, path), {
        headers = {
            Accept = "application/vnd.mason-registry.v1+json; q=1.0, application/json; q=0.8",
        },
    }):map_catching(vim.json.decode)
end

---@alias ApiSignature<T> async fun(path_params: T, opts?: ApiFetchOpts): Result

---@param char string
local function percent_encode(char)
    return ("%%%x"):format(string.byte(char, 1, 1))
end

api.encode_uri_component = _.gsub("[!#%$&'%(%)%*%+,/:;=%?@%[%]]", percent_encode)

---@param path_template string
local function get(path_template)
    ---@async
    ---@param path_params table
    ---@param opts ApiFetchOpts?
    return function(path_params, opts)
        local path = path_template:gsub("{([%w_%.0-9]+)}", function(prop)
            return path_params[prop]
        end)
        -- This is done so that test stubs trigger as expected (you have to explicitly match against nil arguments)
        if opts then
            return api.get(path, opts)
        else
            return api.get(path)
        end
    end
end

api.github = {
    releases = {
        ---@type ApiSignature<{ repo: string }>
        latest = get "/api/github/{repo}/releases/latest",
        ---@type ApiSignature<{ repo: string }>
        all = get "/api/github/{repo}/releases/all",
    },
    tags = {
        ---@type ApiSignature<{ repo: string }>
        latest = get "/api/github/{repo}/tags/latest",
        ---@type ApiSignature<{ repo: string }>
        all = get "/api/github/{repo}/tags/all",
    },
}

api.npm = {
    versions = {
        ---@type ApiSignature<{ package: string }>
        latest = get "/api/npm/{package}/versions/latest",
        ---@type ApiSignature<{ package: string }>
        all = get "/api/npm/{package}/versions/all",
    },
}

api.pypi = {
    versions = {
        ---@type ApiSignature<{ package: string }>
        latest = get "/api/pypi/{package}/versions/latest",
        ---@type ApiSignature<{ package: string }>
        all = get "/api/pypi/{package}/versions/all",
        ---@type ApiSignature<{ package: string, version: string }>
        get = get "/api/pypi/{package}/versions/{version}",
    },
}

api.rubygems = {
    versions = {
        ---@type ApiSignature<{ gem: string }>
        latest = get "/api/rubygems/{gem}/versions/latest",
        ---@type ApiSignature<{ gem: string }>
        all = get "/api/rubygems/{gem}/versions/all",
    },
}

api.packagist = {
    versions = {
        ---@type ApiSignature<{ pkg: string }>
        latest = get "/api/packagist/{pkg}/versions/latest",
        ---@type ApiSignature<{ pkg: string }>
        all = get "/api/packagist/{pkg}/versions/all",
    },
}

api.crate = {
    versions = {
        ---@type ApiSignature<{ crate: string }>
        latest = get "/api/crate/{crate}/versions/latest",
        ---@type ApiSignature<{ crate: string }>
        all = get "/api/crate/{crate}/versions/all",
    },
}

api.golang = {
    versions = {
        ---@type ApiSignature<{ pkg: string }>
        all = get "/api/golang/{pkg}/versions/all",
    },
}

api.openvsx = {
    versions = {
        ---@type ApiSignature<{ namespace: string, extension: string }>
        latest = get "/api/openvsx/{namespace}/{extension}/versions/latest",
        ---@type ApiSignature<{ namespace: string, extension: string }>
        all = get "/api/openvsx/{namespace}/{extension}/versions/all",
    },
}

return api
