local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local async_uv = require "mason-core.async.uv"
local log = require "mason-core.log"
local platform = require "mason-core.platform"
local powershell = require "mason-core.installer.managers.powershell"
local spawn = require "mason-core.spawn"
local version = require "mason.version"

local USER_AGENT = ("mason.nvim %s (+https://github.com/mason-org/mason.nvim)"):format(version.VERSION)

local TIMEOUT_SECONDS = 30

---@alias FetchMethod
---| '"GET"'
---| '"POST"'
---| '"PUT"'
---| '"PATCH"'
---| '"DELETE"'

---@alias FetchOpts {out_file: string?, method: FetchMethod?, headers: table<string, string>?, data: string?}

---@async
---@param url string The url to fetch.
---@param opts FetchOpts?
---@return Result # Result<string>
local function fetch(url, opts)
    opts = opts or {}
    if not opts.headers then
        opts.headers = {}
    end
    if not opts.method then
        opts.method = "GET"
    end
    opts.headers["User-Agent"] = USER_AGENT
    log.fmt_debug("Fetching URL %s", url)

    local platform_specific = Result.failure

    if platform.is.win then
        local header_entries = _.join(
            "; ",
            _.map(function(pair)
                return ("%q=%q"):format(pair[1], pair[2])
            end, _.to_pairs(opts.headers))
        )
        local headers = ("-Headers @{%s}"):format(header_entries)
        if opts.out_file then
            platform_specific = function()
                return powershell.command(
                    ([[iwr %s -TimeoutSec %s -UseBasicParsing -Method %q -Uri %q %s -OutFile %q;]]):format(
                        headers,
                        TIMEOUT_SECONDS,
                        opts.method,
                        url,
                        opts.data and ("-Body %s"):format(opts.data) or "",
                        opts.out_file
                    )
                )
            end
        else
            platform_specific = function()
                return powershell.command(
                    ([[Write-Output (iwr %s -TimeoutSec %s -Method %q -UseBasicParsing %s -Uri %q).Content;]]):format(
                        headers,
                        TIMEOUT_SECONDS,
                        opts.method,
                        opts.data and ("-Body %s"):format(opts.data) or "",
                        url
                    )
                )
            end
        end
    end

    local function wget()
        local headers =
            _.sort_by(_.identity, _.map(_.compose(_.format "--header=%s", _.join ": "), _.to_pairs(opts.headers)))
        return spawn.wget {
            headers,
            "-nv",
            "-o",
            "/dev/null",
            "-O",
            opts.out_file or "-",
            ("--timeout=%s"):format(TIMEOUT_SECONDS),
            ("--method=%s"):format(opts.method),
            opts.data and {
                ("--body-data=%s"):format(opts.data) or vim.NIL,
            } or vim.NIL,
            url,
        }
    end

    local function curl()
        local headers = _.sort_by(
            _.nth(2),
            _.map(
                _.compose(function(header)
                    return { "-H", header }
                end, _.join ": "),
                _.to_pairs(opts.headers)
            )
        )
        return spawn.curl {
            headers,
            "-fsSL",
            {
                "-X",
                opts.method,
            },
            opts.data and { "-d", "@-" } or vim.NIL,
            opts.out_file and { "-o", opts.out_file } or vim.NIL,
            { "--connect-timeout", TIMEOUT_SECONDS },
            url,
            on_spawn = a.scope(function(_, stdio)
                local stdin = stdio[1]
                if opts.data then
                    log.trace("Writing stdin to curl", opts.data)
                    async_uv.write(stdin, opts.data)
                end
                async_uv.shutdown(stdin)
                async_uv.close(stdin)
            end),
        }
    end

    return curl():or_else(wget):or_else(platform_specific):map(function(result)
        if opts.out_file then
            return result
        else
            return result.stdout
        end
    end)
end

return fetch
