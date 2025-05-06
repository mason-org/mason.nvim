# Changelog

## [2.0.0](https://github.com/mason-org/mason.nvim/compare/v1.11.0...v2.0.0) (2025-05-06)

This release has been an ongoing effort for quite some time now and is now ready for release. Most users should not
experience any breaking changes. If you use any of the Lua APIs that Mason provides you'll find an outline of the
changes below, breaking changes are marked with `Breaking Change`.

### Repository has been moved

The repository has been transferred to the [`mason-org`](https://github.com/mason-org) organization. The new URL is
https://github.com/mason-org/mason.nvim. The previous URL will continue to function as a redirect to the new URL but
users are recommended to update to the new location. 

### Addition of new maintainers ❤️

- [@mehalter](https://github.com/mehalter)
- [@Conarius](https://github.com/Conarius)
- [@chrisgrieser](https://github.com/chrisgrieser)

### Features
- Symlinks now uses relative paths instead of absolute paths.
- Uninstalled packages now display their available version in the `:Mason` UI.
- Packages in the `:Mason` UI now display the source [`purl`](https://github.com/package-url/purl-spec).
- Official support for [custom registries](https://github.com/mason-org/registry-examples).
- Make registry installations run concurrently.
- Add support for `'winborder'`.
- Display current `mason.nvim` version in the `:Mason` UI header.

### Bug Fixes
- Only attempt unlinking package if the receipt is found.
- Expand executable paths on Windows before passing to uv_spawn.
- Fix initializing UI state when using multiple registries.
- Fix the display of outdated packages in the Mason UI under certain conditions.

### Misc
- `Breaking Change` Minimum Neovim requirement changed from 0.7.0 to 0.10.0. 
- `Breaking Change` APIs related to custom packages written in Lua has been removed.
    - All `require("mason-core.installer.managers")` modules have been removed.
    - The package structure of Lua packages has changed, refer to [custom
      registries](https://github.com/mason-org/registry-examples) for information on how to continue using custom
      packages in Lua.

### Event changes

#### Package
- `Breaking Change` `install:success` now provides the receipt as payload argument.
- `Breaking Change` `install:failed` now provides the error as payload argument.
- `Breaking Change` `uninstall:success` now provides the receipt of the uninstalled package as payload argument.
- `uninstall:failed` is now emitted when package uninstallation fails.

#### Registry
- `Breaking Change` `package:install:success` now provides the receipt as payload argument.
- `Breaking Change` `package:install:failed` now provides the error as payload argument.
- `Breaking Change` `package:uninstall:success` now provides the receipt of the uninstalled package as payload argument.
- `package:uninstall:failed` is now emitted when package uninstallation fails.
- `Breaking Change` `update` is no longer emitted when registry is updated. It's replaced by the following events:
  - `update:start` when the registry starts updating
  - `update:success` when the registry is successfully updated
  - `update:failed` when the registry failed to update
  - `update:progress` is emitted when the registry update process makes progress when multiple registries are used

### Package API changes

#### `Package:get_install_path()` has been removed.
`Breaking Change`

This method has been removed to prepare for future changes.

If you're using this method to access an executable, please consider simply using the canonical name of the executable
as Mason adds these to your `PATH` by default. If you're using the method to access other files inside the package,
please consider accessing the `$MASON/share` directory instead.

Example:

_Clarification: The `$MASON` environment variable has been available since v1.0.0._

```lua
-- 1a. There's no need to reach into the package directory via Package:get_install_path() to access the executable
print(vim.fn.exepath("kotlin-debug-adapter"))
-- /Users/william/.local/share/nvim/mason/bin/kotlin-debug-adapter

-- 1b. Alternatively if you've configured Mason to not modify PATH
print(vim.fn.expand("$MASON/bin/kotlin-debug-adapter"))
-- /Users/william/.local/share/nvim/mason/bin/kotlin-debug-adapter

-- 2. To access other files inside the package directory, consider accessing them via the share/ directory
vim.print(vim.fn.globpath("$MASON/share/java-debug-adapter", "*.jar", true, true))
-- { "/Users/william/.local/share/nvim/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin-0.53.1.jar", "/Users/william/.local/share/nvim/mason/share/java-debug-adapter/com.microsoft.java.debug.plugin.jar" }

-- 3. If you absolutely need to access the package directory (please consider raising an issue/PR in the registry if possible)
print(vim.fn.expand("$MASON/packages/kotlin-debug-adapter/adapter/bin/kotlin-debug-adapter"))
-- /Users/william/.local/share/nvim/mason/packages/kotlin-debug-adapter/adapter/bin/kotlin-debug-adapter
```

> [!NOTE]
> Why was this method removed? The contents of the package directory is not a stable interface and its structure may
> change without prior notice, for example to host multiple versions of a package. The only stable interfaces on the
> file system are files available in `bin/`, `share/` and `opt/` - these directories are only subject to breaking
> changes done by the underlying package itself.

---

#### `Package:uninstall(opts, callback)` is now asynchronous.
`Breaking Change`

This method now provides an asynchronous interface and accepts two new optional arguments `opts` and `callback`. `opts`
currently doesn't have any valid values other than an empty Lua table `{}`. `callback` is called when the package is
uninstalled, successfully or not. While the uninstall mechanism under the hood remains synchronous for the time being it
is not a guarantee going forward and users are recommended to always use the asynchronous version.

Example:

```lua
local registry = require("mason-registry")
local pkg = registry.get_package("lua-language-server")

pkg:uninstall({}, function (success, result)
    if success then
        -- Do something on success.
    else
        -- Do something on error.
    end
end)
```

---

#### `Package:check_new_version()` has been removed.
`Breaking Change`

`Package:check_new_version()` is replaced by `Package:get_latest_version()`. `Package:get_latest_version()` is a
synchronous API.

> [!NOTE]
> Similarly to before, this function returns the package version provided by the currently installed registry version.

Example:
```lua
local registry = require("mason-registry")
local pkg = registry.get_package("lua-language-server")
local latest_version = pkg:get_latest_version()
```

---

#### `Package:get_installed_version()` is now synchronous.
`Breaking Change`

This function no longer accepts a callback.

Example:
```lua
local registry = require("mason-registry")
local pkg = registry.get_package("lua-language-server")
if pkg:is_installed() then
    local installed_version = pkg:get_installed_version()
end
```

---

#### `Package:install()` will now error if the package is currently being installed.
`Breaking Change`

Use the new `Package:is_installing()` method to check whether an installation is already running.

---

#### `Package:uninstall()` will now error if the package is not already installed.
`Breaking Change`

Use the new `Package:is_installed()` method to check whether the package is installed.

---

#### `Package:install(opts, callback)` now accepts a callback.

This optional callback is called by Mason when package installation finishes, successfully or not.

Example:

```lua
local registry = require("mason-registry")
local pkg = registry.get_package("lua-language-server")

pkg:install({}, function (success, result)
    if success then
        -- Do something on success.
    else
        -- Do something on error.
    end
end)
```

### Custom registries

v2.0.0 introduces official support for custom registries. Currently supported registry protocols are `github:`, `file:`,
and `lua:`. Lua-based registries have been reworked, please see https://github.com/mason-org/registry-examples for examples. 

Thanks to all sponsors who continue to help finance monthly costs and all 181 contributors of mason.nvim and 246
contributors of the core registry!

## [1.11.0](https://github.com/williamboman/mason.nvim/compare/v1.10.0...v1.11.0) (2025-02-15)


### Features

* **pypi:** improve resolving suitable python version ([#1725](https://github.com/williamboman/mason.nvim/issues/1725)) ([0950b15](https://github.com/williamboman/mason.nvim/commit/0950b15060067f752fde13a779a994f59516ce3d))
* **ui:** add backdrop ([#1759](https://github.com/williamboman/mason.nvim/issues/1759)) ([0a3a85f](https://github.com/williamboman/mason.nvim/commit/0a3a85fa1a59e0bb0811c87556dee51f027b3358))


### Bug Fixes

* avoid calling vim.fn in fast event ([#1878](https://github.com/williamboman/mason.nvim/issues/1878)) ([3a444cb](https://github.com/williamboman/mason.nvim/commit/3a444cb7b0cee6b1e2ed31b7e76f37509075dc46))
* avoid calling vim.fn.has inside fast event ([#1705](https://github.com/williamboman/mason.nvim/issues/1705)) ([1b3d604](https://github.com/williamboman/mason.nvim/commit/1b3d60405d1d720b2c4927f19672e9479703b00f))
* fix usage of deprecated Neovim APIs ([#1703](https://github.com/williamboman/mason.nvim/issues/1703)) ([0f1cb65](https://github.com/williamboman/mason.nvim/commit/0f1cb65f436b769733d18b41572f617a1fb41f62))
* **fs:** fall back to `fs_stat` if entry type is not returned by `fs_readdir` ([#1783](https://github.com/williamboman/mason.nvim/issues/1783)) ([1114b23](https://github.com/williamboman/mason.nvim/commit/1114b2336e917d883c30f89cd63ba94050001b2d))
* **health:** support multidigit luarocks version numbers ([#1648](https://github.com/williamboman/mason.nvim/issues/1648)) ([751b1fc](https://github.com/williamboman/mason.nvim/commit/751b1fcbf3d3b783fcf8d48865264a9bcd8f9b10))
* **pypi:** allow access to system site packages by default ([#1584](https://github.com/williamboman/mason.nvim/issues/1584)) ([2be2600](https://github.com/williamboman/mason.nvim/commit/2be2600f9b5a61b0c6109a3fb161b3abe75e5195))
* **pypi:** exclude python3.12 from candidate list ([#1722](https://github.com/williamboman/mason.nvim/issues/1722)) ([f8ce876](https://github.com/williamboman/mason.nvim/commit/f8ce8768f296717c72b3910eee7bd5ac5223cdb9))
* **pypi:** prefer stock python3 if it satisfies version requirement ([#1736](https://github.com/williamboman/mason.nvim/issues/1736)) ([f96a318](https://github.com/williamboman/mason.nvim/commit/f96a31855fa8aea55599cea412fe611b85a874ed))
* **registry:** exhaust streaming parser when loading "file:" registries ([#1708](https://github.com/williamboman/mason.nvim/issues/1708)) ([49ff59a](https://github.com/williamboman/mason.nvim/commit/49ff59aded1047a773670651cfa40e76e63c6377))
* replace deprecated calls to vim.validate ([#1876](https://github.com/williamboman/mason.nvim/issues/1876)) ([5664dd5](https://github.com/williamboman/mason.nvim/commit/5664dd5deb3ac9527da90691543eb28df51c1ef8))
* **ui:** fix rendering JSON schemas ([#1757](https://github.com/williamboman/mason.nvim/issues/1757)) ([e2f7f90](https://github.com/williamboman/mason.nvim/commit/e2f7f9044ec30067bc11800a9e266664b88cda22))
* **ui:** reposition window if border is different than "none" ([#1859](https://github.com/williamboman/mason.nvim/issues/1859)) ([f9f3b46](https://github.com/williamboman/mason.nvim/commit/f9f3b464dda319288b8ce592e53f0d9cf9ca8b4e))


### Performance Improvements

* **registry:** significantly improve the "file:" protocol performance ([#1702](https://github.com/williamboman/mason.nvim/issues/1702)) ([098a56c](https://github.com/williamboman/mason.nvim/commit/098a56c385ca3a1a0d4682d129203dda35421b8e))

## [1.10.0](https://github.com/williamboman/mason.nvim/compare/v1.9.0...v1.10.0) (2024-01-29)


### Features

* don't use vim.g.python3_host_prog as a candidate for python ([#1606](https://github.com/williamboman/mason.nvim/issues/1606)) ([bce96d2](https://github.com/williamboman/mason.nvim/commit/bce96d2fd483e71826728c6f9ac721fc9dd7d2cf))
* **pypi:** attempt more python3 candidates ([#1608](https://github.com/williamboman/mason.nvim/issues/1608)) ([dcd0ea3](https://github.com/williamboman/mason.nvim/commit/dcd0ea30ccfc7d47e879878d1270d6847a519181))


### Bug Fixes

* **golang:** fix fetching package versions for packages containing subpath specifier ([#1607](https://github.com/williamboman/mason.nvim/issues/1607)) ([9c94168](https://github.com/williamboman/mason.nvim/commit/9c9416817c9f4e6f333c749327a1ed5355cfab61))
* **pypi:** fix variable shadowing ([#1610](https://github.com/williamboman/mason.nvim/issues/1610)) ([aa550fb](https://github.com/williamboman/mason.nvim/commit/aa550fb0649643eee89d5e64c67f81916e88a736))
* **ui:** don't indent empty lines ([#1597](https://github.com/williamboman/mason.nvim/issues/1597)) ([c7e6705](https://github.com/williamboman/mason.nvim/commit/c7e67059bb8ce7e126263471645c531d961b5e1d))

## [1.9.0](https://github.com/williamboman/mason.nvim/compare/v1.8.3...v1.9.0) (2024-01-06)


### Features

* add support for openvsx sources ([#1589](https://github.com/williamboman/mason.nvim/issues/1589)) ([6c68547](https://github.com/williamboman/mason.nvim/commit/6c685476df4f202e371bdd3d726729d6f3f8b9f0))


### Bug Fixes

* **cargo:** don't attempt to fetch versions when version targets commit SHA ([#1585](https://github.com/williamboman/mason.nvim/issues/1585)) ([a09da6a](https://github.com/williamboman/mason.nvim/commit/a09da6ac634926a299dd439da08bdb547a8ca011))

## [1.8.3](https://github.com/williamboman/mason.nvim/compare/v1.8.2...v1.8.3) (2023-11-08)


### Bug Fixes

* **pypi:** support MSYS2 virtual environments on Windows ([#1547](https://github.com/williamboman/mason.nvim/issues/1547)) ([3e2432a](https://github.com/williamboman/mason.nvim/commit/3e2432ad0bca01fc3356389b341aa3e5e2da9fd8))

## [1.8.2](https://github.com/williamboman/mason.nvim/compare/v1.8.1...v1.8.2) (2023-10-31)


### Bug Fixes

* **registry:** fix parsing registry identifiers that contain ":" ([#1542](https://github.com/williamboman/mason.nvim/issues/1542)) ([87eb3ac](https://github.com/williamboman/mason.nvim/commit/87eb3ac2ab4fcbf5326d8bde6842b073a3be65a7))

## [1.8.1](https://github.com/williamboman/mason.nvim/compare/v1.8.0...v1.8.1) (2023-10-10)


### Bug Fixes

* **health:** schedule vim.fn call ([#1514](https://github.com/williamboman/mason.nvim/issues/1514)) ([3ba3b79](https://github.com/williamboman/mason.nvim/commit/3ba3b79f73d5411e72c7df5445150f4e9278d4d7))

## [1.8.0](https://github.com/williamboman/mason.nvim/compare/v1.7.0...v1.8.0) (2023-09-04)


### Features

* **ui:** add setting to toggle help view ([#1468](https://github.com/williamboman/mason.nvim/issues/1468)) ([e1602c8](https://github.com/williamboman/mason.nvim/commit/e1602c868f938877057cb6f45e50859cb55cad96))


### Bug Fixes

* **registry:** reset registries state when setting registries ([#1474](https://github.com/williamboman/mason.nvim/issues/1474)) ([c811fbf](https://github.com/williamboman/mason.nvim/commit/c811fbf09c7642eebb37d6694f1a016a043f6ed3))
* **registry:** schedule vim.fn calls in FileRegistrySource ([#1471](https://github.com/williamboman/mason.nvim/issues/1471)) ([1c77412](https://github.com/williamboman/mason.nvim/commit/1c77412d7ff73e453cdc5366c8d7cd98d2242802))

## [1.7.0](https://github.com/williamboman/mason.nvim/compare/v1.6.2...v1.7.0) (2023-08-25)


### Features

* **cargo:** support fetching versions for git crates hosted on github ([#1459](https://github.com/williamboman/mason.nvim/issues/1459)) ([e9eb004](https://github.com/williamboman/mason.nvim/commit/e9eb0048cecc577a1eec534485d3e010487b46a7))
* **registry:** add file: source protocol ([#1457](https://github.com/williamboman/mason.nvim/issues/1457)) ([8544039](https://github.com/williamboman/mason.nvim/commit/85440397264a31208721e4501c93b23a4940b27e))


### Bug Fixes

* **std:** use gtar if available ([#1433](https://github.com/williamboman/mason.nvim/issues/1433)) ([a51c2d0](https://github.com/williamboman/mason.nvim/commit/a51c2d063c5377ee9e58c5f9cda7c7436787be72))
* **ui:** properly reset new package version state ([#1454](https://github.com/williamboman/mason.nvim/issues/1454)) ([68e6a15](https://github.com/williamboman/mason.nvim/commit/68e6a153d7cd1251eb85ebb48d2e351e9ab940b8))

## [1.6.2](https://github.com/williamboman/mason.nvim/compare/v1.6.1...v1.6.2) (2023-08-09)


### Bug Fixes

* **ui:** don't disable search mode if empty pattern and last-pattern is set ([#1445](https://github.com/williamboman/mason.nvim/issues/1445)) ([be6f680](https://github.com/williamboman/mason.nvim/commit/be6f680774a75a06ceede3bd7159df2388f49b04))

## [1.6.1](https://github.com/williamboman/mason.nvim/compare/v1.6.0...v1.6.1) (2023-07-21)


### Bug Fixes

* **installer:** retain unmapped source fields ([#1399](https://github.com/williamboman/mason.nvim/issues/1399)) ([0579574](https://github.com/williamboman/mason.nvim/commit/05795741895ee16062eabeb0d89bff7cbcd693fa))

## [1.6.0](https://github.com/williamboman/mason.nvim/compare/v1.5.1...v1.6.0) (2023-07-04)


### Features

* **ui:** display package deprecation message ([#1391](https://github.com/williamboman/mason.nvim/issues/1391)) ([b728115](https://github.com/williamboman/mason.nvim/commit/b7281153cd9167d2b1a5d8cbda1ba8d4ad9fa8c2))
* **ui:** don't use diagnostic messages for displaying deprecated, uninstalled, packages ([#1393](https://github.com/williamboman/mason.nvim/issues/1393)) ([c290d0e](https://github.com/williamboman/mason.nvim/commit/c290d0e4ab6da9cac1e26684e53fba0b615862ed))

## [1.5.1](https://github.com/williamboman/mason.nvim/compare/v1.5.0...v1.5.1) (2023-06-28)


### Bug Fixes

* **linker:** ensure exec wrapper target is executable ([#1380](https://github.com/williamboman/mason.nvim/issues/1380)) ([10da1a3](https://github.com/williamboman/mason.nvim/commit/10da1a33b4ac24ad4d76a9af91871720ac6b65e4))
* **purl:** percent-encoding is case insensitive ([#1382](https://github.com/williamboman/mason.nvim/issues/1382)) ([b68d3be](https://github.com/williamboman/mason.nvim/commit/b68d3be4b664671002221d43c82e74a0f1006b26))

## [1.5.0](https://github.com/williamboman/mason.nvim/compare/v1.4.0...v1.5.0) (2023-06-28)


### Features

* **command:** add completion for option flags for :MasonInstall ([#1379](https://github.com/williamboman/mason.nvim/issues/1379)) ([e507af7](https://github.com/williamboman/mason.nvim/commit/e507af7b996dae90404345abb2bc88540f931589))
* **installer:** write more installation output to stdout ([#1376](https://github.com/williamboman/mason.nvim/issues/1376)) ([758ac5b](https://github.com/williamboman/mason.nvim/commit/758ac5b35e823eee74a90f855b2a66afc51ec92d))


### Bug Fixes

* **installer:** timeout schema download after 5s ([#1374](https://github.com/williamboman/mason.nvim/issues/1374)) ([d114376](https://github.com/williamboman/mason.nvim/commit/d11437645af60449ff252b2c9abda103c5610520))

## [1.4.0](https://github.com/williamboman/mason.nvim/compare/v1.3.0...v1.4.0) (2023-06-21)


### Features

* **fetch:** add explicit default timeout to requests ([#1364](https://github.com/williamboman/mason.nvim/issues/1364)) ([82cae55](https://github.com/williamboman/mason.nvim/commit/82cae550c87466b1163b216bdb9c71cb71dd8f67))
* **fetch:** include mason.nvim version in User-Agent ([#1362](https://github.com/williamboman/mason.nvim/issues/1362)) ([e706d30](https://github.com/williamboman/mason.nvim/commit/e706d305fbcc8701bd30e31dd727aee2853b9db9))

## [1.3.0](https://github.com/williamboman/mason.nvim/compare/v1.2.1...v1.3.0) (2023-06-18)


### Features

* **health:** add advice for Debian/Ubuntu regarding python3 venv ([#1358](https://github.com/williamboman/mason.nvim/issues/1358)) ([6f3853e](https://github.com/williamboman/mason.nvim/commit/6f3853e5ae8c200e29d2e394e479d9c3f8e018f5))

## [1.2.1](https://github.com/williamboman/mason.nvim/compare/v1.2.0...v1.2.1) (2023-06-13)


### Bug Fixes

* **providers:** fix some client providers and add some more ([#1354](https://github.com/williamboman/mason.nvim/issues/1354)) ([6f44955](https://github.com/williamboman/mason.nvim/commit/6f4495590a0f9e121b483c9b1236fbabbd80da7a))

## [1.2.0](https://github.com/williamboman/mason.nvim/compare/v1.1.1...v1.2.0) (2023-06-13)


### Features

* **command:** improve completion for :MasonInstall ([#1353](https://github.com/williamboman/mason.nvim/issues/1353)) ([13e26c8](https://github.com/williamboman/mason.nvim/commit/13e26c81ff5074ee8f095a791cd37fc1cec37377))


### Bug Fixes

* **async:** always check channel state ([#1351](https://github.com/williamboman/mason.nvim/issues/1351)) ([f503346](https://github.com/williamboman/mason.nvim/commit/f5033463bb911a136e577fc6f339328f162e2b4a))
* **command:** run :MasonUpdate synchronously in headless mode ([#1347](https://github.com/williamboman/mason.nvim/issues/1347)) ([0276793](https://github.com/williamboman/mason.nvim/commit/02767937fc2e1b214c854a8fdde26ae1d3529dd6))
* **functional:** strip_prefix and strip_suffix should not use patterns ([#1352](https://github.com/williamboman/mason.nvim/issues/1352)) ([f99b702](https://github.com/williamboman/mason.nvim/commit/f99b70233e49db2229350bb82d9ddc6e2f4131c0))

## [1.1.1](https://github.com/williamboman/mason.nvim/compare/v1.1.0...v1.1.1) (2023-05-29)


### Bug Fixes

* **ui:** improve search mode UI and remove redundant whitespaces ([#1332](https://github.com/williamboman/mason.nvim/issues/1332)) ([a18c031](https://github.com/williamboman/mason.nvim/commit/a18c031c72a3c7576ba5dc60ee30de8290c8757c))

## [1.1.0](https://github.com/williamboman/mason.nvim/compare/v1.0.1...v1.1.0) (2023-05-18)


### Features

* **installer:** lock package installation ([#1290](https://github.com/williamboman/mason.nvim/issues/1290)) ([227f8a9](https://github.com/williamboman/mason.nvim/commit/227f8a9aaae495f481c768f8346edfceaf6d2951))
* **ui:** add keymap setting for toggling package installation log ([#1268](https://github.com/williamboman/mason.nvim/issues/1268)) ([48bb1cc](https://github.com/williamboman/mason.nvim/commit/48bb1cc33a1fefe94f5ce4972446a1c6ad849f15))
* **ui:** add search mode ([#1306](https://github.com/williamboman/mason.nvim/issues/1306)) ([3b59f25](https://github.com/williamboman/mason.nvim/commit/3b59f25d435fb1b8d36c4cc26410c3569f0bd795))
* **ui:** display "update all" hint ([#1296](https://github.com/williamboman/mason.nvim/issues/1296)) ([e634134](https://github.com/williamboman/mason.nvim/commit/e634134312bb936f472468a401c9cae6485ab54b))


### Bug Fixes

* **sources:** don't skip installation if fixed version is not currently installed ([#1297](https://github.com/williamboman/mason.nvim/issues/1297)) ([9c5edf1](https://github.com/williamboman/mason.nvim/commit/9c5edf13c2e6bd5223eebfeb4557ccc841acaa0e))
* **ui:** use vim.cmd("") for nvim-0.7.0 compatibility ([#1307](https://github.com/williamboman/mason.nvim/issues/1307)) ([e60b855](https://github.com/williamboman/mason.nvim/commit/e60b855bfa8c7d34387200daa6e54a5e22d3da05))

## [1.0.1](https://github.com/williamboman/mason.nvim/compare/v1.0.0...v1.0.1) (2023-04-26)


### Bug Fixes

* **pypi:** also provide install_extra_args to pypi.install ([#1263](https://github.com/williamboman/mason.nvim/issues/1263)) ([646ef07](https://github.com/williamboman/mason.nvim/commit/646ef07907e0960987c13c0b13f69eb808cc66ad))
