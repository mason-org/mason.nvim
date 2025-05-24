local InstallLocation = require "mason-core.installer.InstallLocation"
local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local fetch = require "mason-core.fetch"
local fs = require "mason-core.fs"
local log = require "mason-core.log"
local path = require "mason-core.path"
local providers = require "mason-core.providers"
local settings = require "mason.settings"
local util = require "mason-registry.sources.util"

-- Parse sha256sum text output to a table<filename: string, sha256sum: string> structure
local parse_checksums = _.compose(_.from_pairs, _.map(_.compose(_.reverse, _.split "  ")), _.split "\n", _.trim)

---@class GitHubRegistrySourceSpec
---@field id string
---@field namespace string
---@field name string
---@field version string?

---@class GitHubRegistrySource : RegistrySource
---@field spec GitHubRegistrySourceSpec
---@field repo string
---@field root_dir string
---@field private data_file string
---@field private info_file string
---@field buffer table<string, Package>?
local GitHubRegistrySource = {}
GitHubRegistrySource.__index = GitHubRegistrySource

---@param spec GitHubRegistrySourceSpec
function GitHubRegistrySource:new(spec)
    ---@type GitHubRegistrySource
    local instance = {}
    setmetatable(instance, GitHubRegistrySource)
    local root_dir = InstallLocation.global():registry(path.concat { "github", spec.namespace, spec.name })
    instance.id = spec.id
    instance.spec = spec
    instance.repo = ("%s/%s"):format(spec.namespace, spec.name)
    instance.root_dir = root_dir
    instance.data_file = path.concat { root_dir, "registry.json" }
    instance.info_file = path.concat { root_dir, "info.json" }
    return instance
end

function GitHubRegistrySource:is_installed()
    return fs.sync.file_exists(self.data_file) and fs.sync.file_exists(self.info_file)
end

---@return RegistryPackageSpec[]
function GitHubRegistrySource:get_all_package_specs()
    if not self:is_installed() then
        return {}
    end
    local data = vim.json.decode(fs.sync.read_file(self.data_file)) --[[@as RegistryPackageSpec[] ]]
    return _.filter_map(util.map_registry_spec, data)
end

function GitHubRegistrySource:reload()
    if not self:is_installed() then
        return
    end
    self.buffer = _.compose(_.index_by(_.prop "name"), _.map(util.hydrate_package(self, self.buffer or {})))(
        self:get_all_package_specs()
    )
    return self.buffer
end

function GitHubRegistrySource:get_buffer()
    return self.buffer or self:reload() or {}
end

---@param pkg string
---@return Package?
function GitHubRegistrySource:get_package(pkg)
    return self:get_buffer()[pkg]
end

function GitHubRegistrySource:get_all_package_names()
    return _.map(_.prop "name", self:get_all_package_specs())
end

---@async
function GitHubRegistrySource:install()
    local zzlib = require "mason-vendor.zzlib"

    return Result.try(function(try)
        local version = self.spec.version
        if self:is_installed() and self:get_info().version == version then
            -- Fixed version is already installed - nothing to update
            return
        end

        if not fs.async.dir_exists(self.root_dir) then
            log.debug("Creating registry directory", self)
            try(Result.pcall(fs.async.mkdirp, self.root_dir))
        end

        if version == nil then
            log.trace("Resolving latest version for registry", self)
            ---@type GitHubRelease
            local release = try(
                providers.github
                    .get_latest_release(self.repo)
                    :map_err(_.always "Failed to fetch latest registry version from GitHub API.")
            )
            version = release.tag_name
            log.trace("Resolved latest registry version", self, version)
        end

        local zip_file = path.concat { self.root_dir, "registry.json.zip" }
        try(fetch(settings.current.github.download_url_template:format(self.repo, version, "registry.json.zip"), {
            out_file = zip_file,
        }):map_err(_.always "Failed to download registry archive."))
        local zip_buffer = fs.async.read_file(zip_file)
        local registry_contents = try(
            Result.pcall(zzlib.unzip, zip_buffer, "registry.json")
                :on_failure(_.partial(log.error, "Failed to unpack registry archive."))
                :map_err(_.always "Failed to unpack registry archive.")
        )
        pcall(fs.async.unlink, zip_file)

        local checksums = try(
            fetch(settings.current.github.download_url_template:format(self.repo, version, "checksums.txt")):map_err(
                _.always "Failed to download checksums.txt."
            )
        )

        try(Result.pcall(fs.async.write_file, self.data_file, registry_contents))
        try(Result.pcall(
            fs.async.write_file,
            self.info_file,
            vim.json.encode {
                checksums = parse_checksums(checksums),
                version = version,
                download_timestamp = os.time(),
            }
        ))
    end)
        :on_success(function()
            self:reload()
        end)
        :on_failure(function(err)
            log.fmt_error("Failed to install registry %s. %s", self, err)
        end)
end

---@return { checksums: table<string, string>, version: string, download_timestamp: integer }
function GitHubRegistrySource:get_info()
    return vim.json.decode(fs.sync.read_file(self.info_file))
end

function GitHubRegistrySource:get_display_name()
    if self:is_installed() then
        local info = self:get_info()
        return ("github.com/%s version: %s"):format(self.repo, info.version)
    else
        return ("github.com/%s [uninstalled]"):format(self.repo)
    end
end

function GitHubRegistrySource:serialize()
    local info = self:get_info()
    return {
        proto = "github",
        namespace = self.spec.namespace,
        name = self.spec.name,
        version = info.version,
        checksums = info.checksums,
    }
end

---@param other GitHubRegistrySource
function GitHubRegistrySource:is_same_location(other)
    return self.spec.namespace == other.spec.namespace and self.spec.name == other.spec.name
end

function GitHubRegistrySource:__tostring()
    if self.spec.version then
        return ("GitHubRegistrySource(repo=%s, version=%s)"):format(self.repo, self.spec.version)
    else
        return ("GitHubRegistrySource(repo=%s)"):format(self.repo)
    end
end

return GitHubRegistrySource
