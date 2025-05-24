local _ = require "mason-core.functional"
local fetch = require "mason-core.fetch"
local spawn = require "mason-core.spawn"

local stringify_params = _.compose(_.join "&", _.map(_.join "="), _.sort_by(_.head), _.to_pairs)

---@param path string
---@param opts { params: table<string, any>? }?
---@return Result # JSON decoded response.
local function gh_api_call(path, opts)
    if opts and opts.params then
        local params = stringify_params(opts.params)
        path = ("%s?%s"):format(path, params)
    end
    return spawn
        .gh({ "api", path, env = { CLICOLOR_FORCE = 0 } })
        :map(_.prop "stdout")
        :or_else(function()
            return fetch(("https://api.github.com/%s"):format(path), {
                headers = {
                    Accept = "application/vnd.github.v3+json; q=1.0, application/json; q=0.8",
                },
            })
        end)
        :map_catching(vim.json.decode)
end

---@type GitHubProvider
return {
    get_latest_release = function(repo)
        local path = ("repos/%s/releases/latest"):format(repo)
        return gh_api_call(path)
    end,
    get_all_release_versions = function(repo)
        local path = ("repos/%s/releases"):format(repo)
        return gh_api_call(path):map(_.map(_.prop "tag_name"))
    end,
    get_all_tags = function(repo)
        local path = ("repos/%s/git/matching-refs/tags"):format(repo)
        return gh_api_call(path):map(_.map(_.compose(_.gsub("^refs/tags/", ""), _.prop "ref")))
    end,
}
