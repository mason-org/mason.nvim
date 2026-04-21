local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local expr = require "mason-core.installer.compiler.expr"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local platform = require "mason-core.platform"

local M = {}

local filter_empty_values = _.compose(
    _.from_pairs,
    _.filter(function(pair)
        return pair[2] ~= ""
    end),
    _.to_pairs
)

local bin_delegates = {
    ["luarocks"] = function(target)
        return require("mason-core.installer.managers.luarocks").bin_path(target)
    end,
    ["composer"] = function(target)
        return require("mason-core.installer.managers.composer").bin_path(target)
    end,
    ["opam"] = function(target)
        return require("mason-core.installer.managers.opam").bin_path(target)
    end,
    ["python"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        if not ctx.fs:file_exists(target) then
            return Result.failure(("Cannot write python wrapper for path %q as it doesn't exist."):format(target))
        end
        return Result.pcall(function()
            local python = platform.is.win and "python" or "python3"
            return ctx:write_shell_exec_wrapper(
                bin,
                ("%s %q"):format(python, path.concat { ctx:get_install_path(), target })
            )
        end)
    end,
    ["php"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_php_exec_wrapper(bin, target)
        end)
    end,
    ["pyvenv"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_pyvenv_exec_wrapper(bin, target)
        end)
    end,
    ["dotnet"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        if not ctx.fs:file_exists(target) then
            return Result.failure(("Cannot write dotnet wrapper for path %q as it doesn't exist."):format(target))
        end
        return Result.pcall(function()
            return ctx:write_shell_exec_wrapper(
                bin,
                ("dotnet %q"):format(path.concat {
                    ctx:get_install_path(),
                    target,
                })
            )
        end)
    end,
    ["node"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_node_exec_wrapper(bin, target)
        end)
    end,
    ["ruby"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_ruby_exec_wrapper(bin, target)
        end)
    end,
    ["exec"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        return Result.pcall(function()
            return ctx:write_exec_wrapper(bin, target)
        end)
    end,
    ["java-jar"] = function(target, bin)
        local installer = require "mason-core.installer"
        local ctx = installer.context()
        if not ctx.fs:file_exists(target) then
            return Result.failure(("Cannot write Java JAR wrapper for path %q as it doesn't exist."):format(target))
        end
        return Result.pcall(function()
            return ctx:write_shell_exec_wrapper(
                bin,
                ("java -jar %q"):format(path.concat {
                    ctx:get_install_path(),
                    target,
                })
            )
        end)
    end,
    ["nuget"] = function(target)
        return require("mason-core.installer.managers.nuget").bin_path(target)
    end,
    ["npm"] = function(target)
        return require("mason-core.installer.managers.npm").bin_path(target)
    end,
    ["gem"] = function(target)
        return require("mason-core.installer.managers.gem").create_bin_wrapper(target)
    end,
    ["cargo"] = function(target)
        return require("mason-core.installer.managers.cargo").bin_path(target)
    end,
    ["pypi"] = function(target)
        return require("mason-core.installer.managers.pypi").bin_path(target)
    end,
    ["golang"] = function(target)
        return require("mason-core.installer.managers.golang").bin_path(target)
    end,
}

---Expands bin specification from spec and registers bins to be linked.
---@async
---@param ctx InstallContext
---@param spec RegistryPackageSpec
---@param purl Purl
---@param source ParsedPackageSource
local function expand_bin(ctx, spec, purl, source)
    log.debug("Registering bin links", ctx.package, spec.bin)
    return Result.try(function(try)
        local expr_ctx = {
            version = purl.version,
            source = source,
        }

        local bin_table = spec.bin
        if not bin_table then
            log.fmt_debug("%s spec provides no bin.", ctx.package)
            return
        end

        local interpolated_bins = filter_empty_values(try(expr.tbl_interpolate(bin_table, expr_ctx)))

        local expanded_bin_table = {}
        for bin, target in pairs(interpolated_bins) do
            -- Expand "npm:typescript-language-server"-like expressions
            local delegated_bin = _.match("^(.+):(.+)$", target)
            if #delegated_bin > 0 then
                local bin_type, executable = unpack(delegated_bin)
                log.fmt_trace("Transforming managed executable=%s via %s", executable, bin_type)
                local delegate =
                    try(Optional.of_nilable(bin_delegates[bin_type]):ok_or(("Unknown bin type: %s"):format(bin_type)))
                target = try(delegate(executable, bin))
            end

            log.fmt_debug("Expanded bin link %s -> %s", bin, target)
            if not ctx.fs:file_exists(target) then
                return Result.failure(("Tried to link bin %q to non-existent target %q."):format(bin, target))
            end

            if platform.is.unix then
                ctx.fs:chmod_exec(target)
            end

            expanded_bin_table[bin] = target
        end
        return expanded_bin_table
    end)
end

local is_dir_path = _.matches "/$"

---Expands symlink path specifications from spec and returns symlink file table.
---@async
---@param ctx InstallContext
---@param purl Purl
---@param source ParsedPackageSource
---@param file_spec_table table<string, string>
local function expand_file_spec(ctx, purl, source, file_spec_table)
    log.debug("Registering symlinks", ctx.package, file_spec_table)
    return Result.try(function(try)
        local expr_ctx = { version = purl.version, source = source }

        ---@type table<string, string>
        local interpolated_paths = filter_empty_values(try(expr.tbl_interpolate(file_spec_table, expr_ctx)))

        ---@type table<string, string>
        local expanded_links = {}

        for dest, source_path in pairs(interpolated_paths) do
            local cwd = ctx.cwd:get()

            if is_dir_path(dest) then
                -- linking dir -> dir
                if not is_dir_path(source_path) then
                    return Result.failure(("Cannot link file %q to dir %q."):format(source_path, dest))
                end

                a.scheduler()

                local glob = path.concat { cwd, source_path } .. "**/*"
                log.fmt_trace("Symlink glob for %s: %s", ctx.package, glob)

                ---@type string[]
                local files = _.filter_map(function(abs_path)
                    if not fs.sync.file_exists(abs_path) then
                        -- only link actual files (e.g. exclude directory entries from glob)
                        return Optional.empty()
                    end
                    -- turn into relative paths
                    return Optional.of(abs_path:sub(#cwd + 2)) -- + 2 to remove leading path separator (/)
                end, vim.fn.glob(glob, false, true))

                log.fmt_trace("Expanded glob %s: %s", glob, files)

                for __, file in ipairs(files) do
                    -- File destination should be relative to the source directory. For example, should the source_path
                    -- be "gh_2.22.1_macOS_amd64/share/man/" and dest be "man/", it should link source files to the
                    -- following destinations:
                    --
                    --   gh_2.22.1_macOS_amd64/share/man/                     man/
                    --   -------------------------------------------------------------------------
                    --   gh_2.22.1_macOS_amd64/share/man/man1/gh.1            man/man1/gh.1
                    --   gh_2.22.1_macOS_amd64/share/man/man1/gh-run.1        man/man1/gh-run.1
                    --   gh_2.22.1_macOS_amd64/share/man/man1/gh-ssh-key.1    man/man1/gh-run.1
                    --
                    local file_dest = path.concat {
                        _.trim_end_matches("/", dest),
                        file:sub(#source_path + 1),
                    }
                    expanded_links[file_dest] = file
                end
            else
                -- linking file -> file
                if is_dir_path(source_path) then
                    return Result.failure(("Cannot link dir %q to file %q."):format(source_path, dest))
                end
                expanded_links[dest] = source_path
            end
        end

        return expanded_links
    end)
end

---@async
---@param ctx InstallContext
---@param spec RegistryPackageSpec
---@param purl Purl
---@param source ParsedPackageSource
---@nodiscard
M.bin = function(ctx, spec, purl, source)
    return expand_bin(ctx, spec, purl, source):on_success(function(links)
        ctx.links.bin = vim.tbl_extend("force", ctx.links.bin, links)
    end)
end

---@async
---@param ctx InstallContext
---@param spec RegistryPackageSpec
---@param purl Purl
---@param source ParsedPackageSource
---@nodiscard
M.share = function(ctx, spec, purl, source)
    return expand_file_spec(ctx, purl, source, spec.share):on_success(function(links)
        ctx.links.share = vim.tbl_extend("force", ctx.links.share, links)
    end)
end

---@async
---@param ctx InstallContext
---@param spec RegistryPackageSpec
---@param purl Purl
---@param source ParsedPackageSource
---@nodiscard
M.opt = function(ctx, spec, purl, source)
    return expand_file_spec(ctx, purl, source, spec.opt):on_success(function(links)
        ctx.links.opt = vim.tbl_extend("force", ctx.links.opt, links)
    end)
end

return M
