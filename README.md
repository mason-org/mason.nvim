![Linux](https://img.shields.io/badge/Linux-%23.svg?logo=linux&color=FCC624&logoColor=black)
![macOS](https://img.shields.io/badge/macOS-%23.svg?logo=apple&color=000000&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-%23.svg?logo=windows&color=0078D6&logoColor=white)
[![GitHub CI](https://github.com/mason-org/mason.nvim/workflows/Tests/badge.svg)](https://github.com/mason-org/mason.nvim/actions?query=workflow%3ATests+branch%3Amain+event%3Apush)
[![Sponsors](https://img.shields.io/github/sponsors/williamboman)](https://github.com/sponsors/williamboman)

<h1>
    <img src="https://user-images.githubusercontent.com/6705160/177613416-0c0354d2-f431-40d8-87f0-21310f0bba0e.png" alt="mason.nvim" />
</h1>

<p align="center">
    Portable package manager for Neovim that runs everywhere Neovim runs.<br />
    Easily install and manage LSP servers, DAP servers, linters, and formatters.<br />
</p>
<p align="center">
    <code>:help mason.nvim</code>
</p>
<p align="center">
    <sup>Latest version: v2.0.0</sup> <!-- x-release-please-version -->
</p>

## Table of Contents

-   [Introduction](#introduction)
-   [Installation & Usage](#installation--usage)
    - [Recommended setup for `lazy.nvim`](#recommended-setup-for-lazynvim)
-   [Requirements](#requirements)
-   [Commands](#commands)
-   [Registries](#registries)
-   [Screenshots](#screenshots)
-   [Configuration](#configuration)

## Introduction

> [`:h mason-introduction`][help-mason-introduction]

`mason.nvim` is a Neovim plugin that allows you to easily manage external editor tooling such as LSP servers, DAP servers,
linters, and formatters through a single interface. It runs everywhere Neovim runs (across Linux, macOS, Windows, etc.),
with only a small set of [external requirements](#requirements) needed.

Packages are installed in Neovim's data directory ([`:h standard-path`][help-standard-path]) by default. Executables are
linked to a single `bin/` directory, which `mason.nvim` will add to Neovim's PATH during setup, allowing seamless access
from Neovim builtins (LSP client, shell, terminal, etc.) as well as other 3rd party plugins.

For a list of all available packages, see <https://mason-registry.dev/registry/list>.

## Installation & Usage

> [`:h mason-quickstart`][help-mason-quickstart]

Install using your plugin manager of choice. **Setup is required**:

```lua
require("mason").setup()
```

`mason.nvim` is optimized to load as little as possible during setup. Lazy-loading the plugin, or somehow deferring the
setup, is not recommended.

Refer to the [Configuration](#configuration) section for information about which settings are available.

### Recommended setup for `lazy.nvim`

The following is the recommended setup when using `lazy.nvim`. It will set up the plugin for you, meaning **you don't have
to call `require("mason").setup()` yourself**.

```lua
{
    "mason-org/mason.nvim",
    opts = {}
}
```

## Requirements

> [`:h mason-requirements`][help-mason-requirements]

`mason.nvim` relaxes the minimum requirements by attempting multiple different utilities (for example, `wget`,
`curl`, and `Invoke-WebRequest` are all perfect substitutes).
The _minimum_ recommended requirements are:

-   neovim `>= 0.10.0`
-   For Unix systems:
    -   `git(1)`
    -   `curl(1)` or `GNU wget(1)`
    -   `unzip(1)`
    -   GNU tar (`tar(1)` or `gtar(1)` depending on platform)
    -   `gzip(1)`
-   For Windows systems:
    -   pwsh or powershell
    -   git
    -   GNU tar
    -   One of the following:
        -   [7zip][7zip]
        -   [peazip][peazip]
        -   [archiver][archiver]
        -   [winzip][winzip]
        -   [WinRAR][winrar]

Note that `mason.nvim` will regularly shell out to external package managers, such as `cargo` and `npm`. Depending on
your personal usage, some of these will also need to be installed. Refer to `:checkhealth mason` for a full list.

[7zip]: https://www.7-zip.org/
[archiver]: https://github.com/mholt/archiver
[peazip]: https://peazip.github.io/
[winzip]: https://www.winzip.com/
[winrar]: https://www.win-rar.com/

## Commands

> [`:h mason-commands`][help-mason-commands]

-   `:Mason` - opens a graphical status window
-   `:MasonUpdate` - updates all managed registries
-   `:MasonInstall <package> ...` - installs/re-installs the provided packages
-   `:MasonUninstall <package> ...` - uninstalls the provided packages
-   `:MasonUninstallAll` - uninstalls all packages
-   `:MasonLog` - opens the `mason.nvim` log file in a new tab window

## Registries

Mason's core package registry is located at [mason-org/mason-registry](https://github.com/mason-org/mason-registry).
Before any packages can be used, the registry needs to be downloaded. This is done automatically for you when using the
different Mason commands (e.g. `:MasonInstall`), but can also be done manually by using the `:MasonUpdate` command.

If you're utilizing Mason's Lua APIs to access packages, it's recommended to use the
[`:h mason-registry.refresh()`][help-mason-registry-refresh] or [`:h mason-registry.update()`][help-mason-registry-update]
functions to ensure you have the latest package information before retrieving packages.

## Screenshots

|                                                                                                                                                        |                                                                                                                                                  |                                                                                                                                        |
| :----------------------------------------------------------------------------------------------------------------------------------------------------: | :----------------------------------------------------------------------------------------------------------------------------------------------: | :------------------------------------------------------------------------------------------------------------------------------------: |
|           <img alt="Main window" src="https://github.com/user-attachments/assets/b9a57d21-f551-45ad-a1e5-a9fd66291510">           |                 <img alt="Language search" src="https://github.com/user-attachments/assets/3d24fb7b-2c57-4948-923b-0a42bb627cbe">                 | <img alt="Language filter" src="https://github.com/user-attachments/assets/c0ca5818-3c74-4071-bc41-427a2cd1056d"> |
| <img alt="Package information" src="https://github.com/user-attachments/assets/6f9f6819-ac97-483d-a77c-8f6c6131ac85"> | <img alt="New package versions" src="https://github.com/user-attachments/assets/ff1adc4d-2fcc-46df-ab4c-291c891efa50"> |   <img alt="Help window" src="https://github.com/user-attachments/assets/1fbe75e4-fe69-4417-83e3-82329e1c236e">   |

## Configuration

> [`:h mason-settings`][help-mason-settings]

You may optionally configure certain behavior of `mason.nvim` when calling the `.setup()` function. Refer to the
[default configuration](#default-configuration) for a list of all available settings.

Example:

```lua
require("mason").setup({
    ui = {
        icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗"
        }
    }
})
```

### Configuration using `lazy.nvim`

```lua
{
    "mason-org/mason.nvim",
    opts = {
        ui = {
            icons = {
                package_installed = "✓",
                package_pending = "➜",
                package_uninstalled = "✗"
            }
        }
    }
}
```

### Default configuration

```lua
---@class MasonSettings
local DEFAULT_SETTINGS = {
    ---@since 1.0.0
    -- The directory in which to install packages.
    install_root_dir = path.concat { vim.fn.stdpath "data", "mason" },

    ---@since 1.0.0
    -- Where Mason should put its bin location in your PATH. Can be one of:
    -- - "prepend" (default, Mason's bin location is put first in PATH)
    -- - "append" (Mason's bin location is put at the end of PATH)
    -- - "skip" (doesn't modify PATH)
    ---@type '"prepend"' | '"append"' | '"skip"'
    PATH = "prepend",

    ---@since 1.0.0
    -- Controls to which degree logs are written to the log file. It's useful to set this to vim.log.levels.DEBUG when
    -- debugging issues with package installations.
    log_level = vim.log.levels.INFO,

    ---@since 1.0.0
    -- Limit for the maximum amount of packages to be installed at the same time. Once this limit is reached, any further
    -- packages that are requested to be installed will be put in a queue.
    max_concurrent_installers = 4,

    ---@since 1.0.0
    -- [Advanced setting]
    -- The registries to source packages from. Accepts multiple entries. Should a package with the same name exist in
    -- multiple registries, the registry listed first will be used.
    registries = {
        "github:mason-org/mason-registry",
    },

    ---@since 1.0.0
    -- The provider implementations to use for resolving supplementary package metadata (e.g., all available versions).
    -- Accepts multiple entries, where later entries will be used as fallback should prior providers fail.
    -- Builtin providers are:
    --   - mason.providers.registry-api  - uses the https://api.mason-registry.dev API
    --   - mason.providers.client        - uses only client-side tooling to resolve metadata
    providers = {
        "mason.providers.registry-api",
        "mason.providers.client",
    },

    github = {
        ---@since 1.0.0
        -- The template URL to use when downloading assets from GitHub.
        -- The placeholders are the following (in order):
        -- 1. The repository (e.g. "rust-lang/rust-analyzer")
        -- 2. The release version (e.g. "v0.3.0")
        -- 3. The asset name (e.g. "rust-analyzer-v0.3.0-x86_64-unknown-linux-gnu.tar.gz")
        download_url_template = "https://github.com/%s/releases/download/%s/%s",
    },

    pip = {
        ---@since 1.0.0
        -- Whether to upgrade pip to the latest version in the virtual environment before installing packages.
        upgrade_pip = false,

        ---@since 1.0.0
        -- These args will be added to `pip install` calls. Note that setting extra args might impact intended behavior
        -- and is not recommended.
        --
        -- Example: { "--proxy", "https://proxyserver" }
        install_args = {},
    },

    ui = {
        ---@since 1.0.0
        -- Whether to automatically check for new versions when opening the :Mason window.
        check_outdated_packages_on_open = true,

        ---@since 1.0.0
        -- The border to use for the UI window. Accepts same border values as |nvim_open_win()|.
        -- Defaults to `:h 'winborder'` if nil.
        border = nil,

        ---@since 1.11.0
        -- The backdrop opacity. 0 is fully opaque, 100 is fully transparent.
        backdrop = 60,

        ---@since 1.0.0
        -- Width of the window. Accepts:
        -- - Integer greater than 1 for fixed width.
        -- - Float in the range of 0-1 for a percentage of screen width.
        width = 0.8,

        ---@since 1.0.0
        -- Height of the window. Accepts:
        -- - Integer greater than 1 for fixed height.
        -- - Float in the range of 0-1 for a percentage of screen height.
        height = 0.9,

        icons = {
            ---@since 1.0.0
            -- The list icon to use for installed packages.
            package_installed = "◍",
            ---@since 1.0.0
            -- The list icon to use for packages that are installing, or queued for installation.
            package_pending = "◍",
            ---@since 1.0.0
            -- The list icon to use for packages that are not installed.
            package_uninstalled = "◍",
        },

        keymaps = {
            ---@since 1.0.0
            -- Keymap to expand a package
            toggle_package_expand = "<CR>",
            ---@since 1.0.0
            -- Keymap to install the package under the current cursor position
            install_package = "i",
            ---@since 1.0.0
            -- Keymap to reinstall/update the package under the current cursor position
            update_package = "u",
            ---@since 1.0.0
            -- Keymap to check for new version for the package under the current cursor position
            check_package_version = "c",
            ---@since 1.0.0
            -- Keymap to update all installed packages
            update_all_packages = "U",
            ---@since 1.0.0
            -- Keymap to check which installed packages are outdated
            check_outdated_packages = "C",
            ---@since 1.0.0
            -- Keymap to uninstall a package
            uninstall_package = "X",
            ---@since 1.0.0
            -- Keymap to cancel a package installation
            cancel_installation = "<C-c>",
            ---@since 1.0.0
            -- Keymap to apply language filter
            apply_language_filter = "<C-f>",
            ---@since 1.1.0
            -- Keymap to toggle viewing package installation log
            toggle_package_install_log = "<CR>",
            ---@since 1.8.0
            -- Keymap to toggle the help view
            toggle_help = "g?",
        },
    },
}
```

---

<sup>
👋 didn't find what you were looking for? Try looking in the <a href="./doc/mason.txt">help docs</a> <code>:help mason.nvim</code>!
</sup>

[help-mason-commands]: ./doc/mason.txt#L140
[help-mason-introduction]: ./doc/mason.txt#L11
[help-mason-quickstart]: ./doc/mason.txt#L42
[help-mason-registry-refresh]: ./doc/mason.txt#L520
[help-mason-registry-update]: ./doc/mason.txt#L513
[help-mason-requirements]: ./doc/mason.txt#L25
[help-mason-settings]: ./doc/mason.txt#L200
[help-standard-path]: https://neovim.io/doc/user/starting.html#standard-path
