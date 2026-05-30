local Path = require "mason-core.path"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local a = require "mason-core.async"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local platform = require "mason-core.platform"

local M = {}

---@alias LinkContext { type: '"bin"' | '"opt"' | '"share"', prefix: fun(path: string, location: InstallLocation): string }

local LinkContext = {
    ---@type LinkContext
    BIN = {
        type = "bin",
        ---@param path string
        ---@param location InstallLocation
        prefix = function(path, location)
            return location:bin(path)
        end,
    },
    ---@type LinkContext
    OPT = {
        type = "opt",
        ---@param path string
        ---@param location InstallLocation
        prefix = function(path, location)
            return location:opt(path)
        end,
    },
    ---@type LinkContext
    SHARE = {
        type = "share",
        ---@param path string
        ---@param location InstallLocation
        prefix = function(path, location)
            return location:share(path)
        end,
    },
}

local SystemLinkContext = {
    ---@type LinkContext
    BIN = {
        type = "bin",
        ---@param path string
        ---@param location InstallLocation
        prefix = function(path, location)
            return location:opt(Path.concat { "mason", "system", "bin", path })
        end,
    },
    ---@type LinkContext
    OPT = {
        type = "opt",
        ---@param path string
        ---@param location InstallLocation
        prefix = function(path, location)
            return location:opt(Path.concat { "mason", "system", "opt", path })
        end,
    },
    ---@type LinkContext
    SHARE = {
        type = "share",
        ---@param path string
        ---@param location InstallLocation
        prefix = function(path, location)
            return location:opt(Path.concat { "mason", "system", "share", path })
        end,
    },
}

---@param receipt InstallReceipt
---@param link_context LinkContext
---@param location InstallLocation
local function unlink(receipt, link_context, location)
    return Result.pcall(function()
        local links = receipt:get_links()[link_context.type]
        if not links then
            return
        end
        for linked_file in pairs(links) do
            if receipt:get_schema_version() == "1.0" and link_context.type == "bin" and platform.is.win then
                linked_file = linked_file .. ".cmd"
            end
            local share_path = link_context.prefix(linked_file, location)
            fs.sync.unlink(share_path)
        end
    end)
end

---@param pkg AbstractPackage
---@param receipt InstallReceipt
---@param location InstallLocation
---@nodiscard
function M.unlink(pkg, receipt, location)
    log.fmt_debug("Unlinking %s", pkg, receipt:get_links())
    local link_context = pkg.spec.system and SystemLinkContext or LinkContext
    return Result.try(function(try)
        try(unlink(receipt, link_context.BIN, location))
        try(unlink(receipt, link_context.SHARE, location))
        try(unlink(receipt, link_context.OPT, location))
    end)
end

---@async
---@param context InstallContext
---@param link_context LinkContext
---@param link_fn async fun(new_abs_path: string, target_abs_path: string, target_rel_path: string): Result
local function link(context, link_context, link_fn)
    log.trace("Linking", context.package, link_context.type, context.links[link_context.type])
    return Result.try(function(try)
        for name, rel_path in pairs(context.links[link_context.type]) do
            if platform.is.win and link_context.type == "bin" then
                name = ("%s.cmd"):format(name)
            end
            local new_abs_path = link_context.prefix(name, context.location)
            local target_abs_path = Path.concat { context:get_install_path(), rel_path }
            local target_rel_path = Path.relative(new_abs_path, target_abs_path)

            -- 1. Ensure destination directory exists
            a.scheduler()
            local dir = vim.fn.fnamemodify(new_abs_path, ":h")
            if not fs.async.dir_exists(dir) then
                try(Result.pcall(fs.sync.mkdirp, dir))
            end

            -- 2. Ensure source file exists and target doesn't yet exist OR if --force unlink target if it already
            -- exists.
            if context.opts.force then
                if fs.async.file_exists(new_abs_path) then
                    try(Result.pcall(fs.async.unlink, new_abs_path))
                end
            elseif fs.async.file_exists(new_abs_path) then
                return Result.failure(("%q is already linked."):format(new_abs_path, name))
            end
            if not fs.async.file_exists(target_abs_path) then
                return Result.failure(("Link target %q does not exist."):format(target_abs_path))
            end

            -- 3. Execute link.
            try(link_fn(new_abs_path, target_abs_path, target_rel_path))
            context.receipt:with_link(link_context.type, name, rel_path)
        end
    end)
end

---@param context InstallContext
---@param link_context LinkContext
local function symlink(context, link_context)
    return link(context, link_context, function(new_abs_path, _, target_rel_path)
        return Result.pcall(fs.async.symlink, target_rel_path, new_abs_path)
    end)
end

---@param context InstallContext
---@param link_context LinkContext
local function copyfile(context, link_context)
    return link(context, link_context, function(new_abs_path, target_abs_path)
        return Result.pcall(fs.async.copy_file, target_abs_path, new_abs_path, { excl = true })
    end)
end

---@param context InstallContext
---@param link_context LinkContext
local function win_bin_wrapper(context, link_context)
    return link(context, link_context, function(new_abs_path, __, target_rel_path)
        local windows_target_rel_path = target_rel_path:gsub("/", "\\")
        return Result.pcall(
            fs.async.write_file,
            new_abs_path,
            _.dedent(([[
                @ECHO off
                GOTO start
                :find_dp0
                SET dp0=%%~dp0
                EXIT /b
                :start
                SETLOCAL
                CALL :find_dp0

                endLocal & goto #_undefined_# 2>NUL || title %%COMSPEC%% & "%%dp0%%\%s" %%*
            ]]):format(windows_target_rel_path))
        )
    end)
end

---@async
---@param context InstallContext
---@nodiscard
function M.link(context)
    log.fmt_debug("Linking %s", context.package)
    local link_context = context.package.spec.system and SystemLinkContext or LinkContext
    return Result.try(function(try)
        if platform.is.win then
            try(win_bin_wrapper(context, link_context.BIN))
            try(copyfile(context, link_context.SHARE))
            try(copyfile(context, link_context.OPT))
        else
            try(symlink(context, link_context.BIN))
            try(symlink(context, link_context.SHARE))
            try(symlink(context, link_context.OPT))
        end
    end)
end

return M
