# Mason API reference

This document contains the API reference for `mason.nvim`'s' public APIs and is a more in-depth complementary to the
documentation available in `:h mason`.
The intended audience of this document are plugin developers and people who want to further customize their own Neovim
configuration.

_Note that APIs not listed in this document (or `:h mason`) are not considered public, and are subject to unannounced,
breaking, changes. Use at own risk._

Please [reach out](https://github.com/williamboman/mason.nvim/discussions/new?category=api-suggestions) if you think
something is missing or if something could be improved!

---

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [BCP 14][bcp14],
[RFC2119][rfc2119], and [RFC8174][rfc8174] when, and only when, they appear in all capitals, as shown here.

---

[bcp14]: https://tools.ietf.org/html/bcp14
[rfc2119]: https://tools.ietf.org/html/rfc2119
[rfc8174]: https://tools.ietf.org/html/rfc8174

<!--toc:start-->

-   [Architecture diagram](#architecture-diagram)
-   [Registry events](#registry-events)
-   [`RegistryPackageSpec`](#registrypackagespec)
-   [`Package`](#package)
    -   [`Package.Parse({package_identifier})`](#packageparsepackage_identifier)
    -   [`Package.Lang`](#packagelang)
    -   [`Package.Cat`](#packagecat)
    -   [`Package.License`](#packagelicense)
    -   [`Package.new({spec})`](#packagenewspec)
    -   [`Package.spec`](#packagespec)
    -   [`Package:is_installing()`](#packageis_installing)
    -   [`Package:install({opts?}, {callback?})`](#packageinstallopts-callback)
    -   [`Package:uninstall()`](#packageuninstall)
    -   [`Package:is_installed()`](#packageis_installed)
    -   [`Package:get_install_path()`](#packageget_install_path)
    -   [`Package:get_installed_version()`](#packageget_installed_version)
    -   [`Package:get_latest_version()`](#packageget_latest_version)
-   [`PackageInstallOpts`](#packageinstallopts-1)
-   [`InstallContext`](#installcontext)
    -   [`InstallContext.package`](#installcontextpackage)
    -   [`InstallContext.handle`](#installcontexthandle)
    -   [`InstallContext.spawn`](#installcontextspawn)
    -   [`InstallContext.fs`](#installcontextfs)
    -   [`InstallContext.opts`](#installcontextopts)
    -   [`InstallContext.stdio_sink`](#installcontextstdiosink)
-   [`ContextualFs`](#contextualfs)
    -   [`ContextualFs:append_file(rel_path, contents)`](#contextualfsappendfilerelpath-contents)
    -   [`ContextualFs:write_file(rel_path, contents)`](#contextualfswritefilerelpath-contents)
    -   [`ContextualFs:read_file(rel_path)`](#contextualfsreadfilerelpath)
    -   [`ContextualFs:file_exists(rel_path)`](#contextualfsfileexistsrelpath)
    -   [`ContextualFs:dir_exists(rel_path)`](#contextualfsdirexistsrelpath)
    -   [`ContextualFs:rmrf(rel_path)`](#contextualfsrmrfrelpath)
    -   [`ContextualFs:unlink(rel_path)`](#contextualfsunlinkrelpath)
    -   [`ContextualFs:rename(old_rel_path, new_rel_path)`](#contextualfsrenameoldrelpath-newrelpath)
    -   [`ContextualFs:mkdir(dir_rel_path)`](#contextualfsmkdirdirrelpath)
    -   [`ContextualFs:mkdirp(dir_rel_path)`](#contextualfsmkdirpdirrelpath)
    -   [`ContextualFs:chmod(dir_rel_path, mode)`](#contextualfschmoddirrelpath-mode)
-   [`ContextualSpawn`](#contextualspawn)
-   [`InstallHandleState`](#installhandlestate)
-   [`InstallHandle`](#installhandle)
    -   [`InstallHandle.package`](#installhandlepackage)
    -   [`InstallHandle.state`](#installhandlestate-1)
    -   [`InstallHandle.is_terminated`](#installhandleis_terminated)
    -   [`InstallHandle:is_idle()`](#installhandleis_idle)
    -   [`InstallHandle:is_queued()`](#installhandleis_queued)
    -   [`InstallHandle:is_active()`](#installhandleis_active)
    -   [`InstallHandle:is_closed()`](#installhandleis_closed)
    -   [`InstallHandle:kill({signal})`](#installhandlekillsignal)
    -   [`InstallHandle:terminate()`](#installhandleterminate)
-   [`EventEmitter`](#eventemitter)
    -   [`EventEmitter:on({event}, {handler})`](#eventemitteronevent-handler)
    -   [`EventEmitter:once({event, handler})`](#eventemitteronceevent-handler)
    -   [`EventEmitter:off({event}, {handler})`](#eventemitteroffevent-handler)
<!--toc:end-->

## Architecture diagram

<!-- https://excalidraw.com/#json=vbTmp7nM8H5odJDiaw7Ue,TghucvHHAw8bl7sgX1VuvA -->

![architecture](https://user-images.githubusercontent.com/6705160/224515490-de6381f4-d0c0-40e6-82a0-89f95d08e865.png)

## Registry events

The `mason-registry` Lua module extends the [EventEmitter](#eventemitter) interface and emits the following events:

| Event                       | Handler signature                            |
| --------------------------- | -------------------------------------------- |
| `package:handle`            | `fun(pkg: Package, handle: InstallHandle)`   |
| `package:install:success`   | `fun(pkg: Package, receipt: InstallReceipt)` |
| `package:install:failed`    | `fun(pkg: Package, error: any)`              |
| `package:uninstall:success` | `fun(pkg: Package, receipt: InstallReceipt)` |

The following is an example for how to register handlers for events:

```lua
local registry = require "mason-registry"

registry:on(
    "package:handle",
    vim.schedule_wrap(function(pkg, handle)
        print(string.format("Installing %s", pkg.name))
    end)
)

registry:on(
    "package:install:success",
    vim.schedule_wrap(function(pkg, receipt)
        print(string.format("Successfully installed %s", pkg.name))
    end)
)
```

## `RegistryPackageSpec`

| Key         | Value                                 |
| ----------- | ------------------------------------- |
| schema      | `"registry+v1"`                       |
| name        | `string`                              |
| description | `string`                              |
| homepage    | `string`                              |
| licenses    | [`PackageLicense[]`](#packagelicense) |
| categories  | [`PackageCategory[]`](#packagecat)    |
| languages   | [`PackageLanguage[]`](#packagelang)   |
| source      | `table`                               |
| bin         | `table<string, string>?`              |
| share       | `table<string, string>?`              |
| opt         | `table<string, string>?`              |

## `Package`

Module: [`"mason-core.package"`](../lua/mason-core/package/init.lua)

The `Package` class encapsulates the installation instructions and metadata about a Mason package.

**Events**

This class extends the [EventEmitter](#eventemitter) interface and emits the following events:

| Event               | Handler signature               |
| ------------------- | ------------------------------- |
| `install:success`   | `fun(receipt: InstallReceipt)`  |
| `install:failed`    | `fun(pkg: Package, error: any)` |
| `uninstall:success` | `fun(receipt: InstallReceipt)`  |

### `Package.Parse({package_identifier})`

**Parameters:**

-   `package_identifier`: `string` For example, `"rust-analyzer@nightly"`

**Returns:** `(string, string|nil)` Tuple where the first value is the name and the second value is the specified
version (or `nil`).

### `Package.Lang`

**Type:** `table<string, string>`

Metatable used to declare language identifiers. Any key is valid and will be automatically indexed on first access, for
example:

```lua
print(vim.inspect(Package.Lang)) -- prints {}
local lang = Package.Lang.SomeMadeUpLanguage
print(lang) -- prints "SomeMadeUpLanguage"
print(vim.inspect(Package.Lang)) -- prints { SomeMadeUpLanguage = "SomeMadeUpLanguage" }
```

### `Package.Cat`

**Type:**

```lua
Package.Cat = {
    Compiler = "Compiler",
    Runtime = "Runtime",
    DAP = "DAP",
    LSP = "LSP",
    Linter = "Linter",
    Formatter = "Formatter",
}
```

### `Package.License`

Similar as [`Package.Lang`](#packagelang) but for SPDX license identifiers.

### `Package.new({spec})`

**Parameters:**

-   `spec`: [`RegistryPackageSpec`](#registrypackagespec)

### `Package.spec`

**Type**: [`RegistryPackageSpec`](#registrypackagespec)

### `Package:is_installing()`

**Returns:** `boolean`

### `Package:install({opts?}, {callback?})`

**Parameters:**

-   `opts?`: [`PackageInstallOpts`](#packageinstallopts-1) (optional)
-   `callback?`: `fun(success: boolean, result: any)` (optional) - Callback to be called when package installation completes. _Note: this is called before events (["package:install:success"](#registry-events), ["install:success"](#package)) are emitted._

**Returns:** [`InstallHandle`](#installhandle)

Installs the package instance this method is being called on. Accepts an optional `{opts}` argument which can be used to
for example specify which version to install (see [`PackageInstallOpts`](#packageinstallopts-1)), and an optional
`{callback}` argument which is called when the installation finishes.

The returned [`InstallHandle`](#installhandle) can be used to observe progress and control the installation process
(e.g., cancelling).

_Note that if the package is already being installed this method will error. See
[`Package:is_installing()`](#packageis_installing)._

### `Package:uninstall()`

Uninstalls the package instance this method is being called on.

### `Package:is_installed()`

**Returns:** `boolean`

### `Package:get_install_path()`

**Returns:** `string` The full path where this package is installed. _Note that this will always return a string,
regardless of whether the package is actually installed or not._

### `Package:get_installed_version()`

**Returns:** `string?` The currently installed version of the package. Returns `nil` if the package is not installed.

### `Package:get_latest_version()`

**Returns:** `string` The latest package version as provided by the currently installed version of the registry.

_Note that this method will not check if one or more registries are outdated. If it's desired to retrieve the latest
upstream version, refresh/update registries first (`:h mason-registry.refresh()`, `:h mason-registry.update()`), for
example:_

```lua
local registry = require "mason-registry"
registry.refresh(function()
    local pkg = registry.get_package "rust-analyzer"
    local latest_version = pkg:get_latest_version()
end)
```

## `PackageInstallOpts`

**Type:**

| Key     | Value      | Description                                                                                              |
| ------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| version | `string?`  | The desired version of the package.                                                                      |
| target  | `string?`  | The desired target of the package to install (e.g. `darwin_arm64`, `linux_x64`).                         |
| debug   | `boolean?` | If debug logs should be written.                                                                         |
| force   | `boolean?` | If installation should continue if there are conditions that would normally cause installation to fail.  |
| strict  | `boolean?` | If installation should NOT continue if there are errors that are not necessary for package to be usable. |

## `InstallContext`

The `InstallContext` class will be instantiated by Mason every time a package installer is executed. The `install`
function of a package will receive an instance of `InstallContext` as its first argument.

As the name suggests, this class provides contextual information to be used when installing a package. This includes
which package is being installed, a `spawn` method that allow you to spawn processes that (i) use the correct working
directory of the installation, and (ii) automatically registers stdout and stderr with the `InstallHandle`.

### `InstallContext.package`

**Type:** [`Package`](#package)

### `InstallContext.handle`

**Type:** [`InstallHandle`](#installhandle)

### `InstallContext.spawn`

**Type:** [`ContextualSpawn`](#contextualspawn)

### `InstallContext.fs`

**Type:** [`ContextualFs`](#contextualfs)

### `InstallContext.opts`

**Type:** [`PackageInstallOpts`](#packageinstallopts-1)

### `InstallContext.stdio_sink`

**Type:** `{ stdout: fun(chunk: string), stderr: fun(chunk: string) }`

The `stdio_sink` property can be used to send stdout or stderr output. This gets presented to users during installation
and is also retained in installation logs. Line breaks are not automatically handled and must be manually included via
the escape sequence `\n`.

Example:

```lua
Pkg.new {
    --- ...
    ---@async
    ---@param ctx InstallContext
    install = function(ctx)
        ctx.stdio_sink.stdout "I am doing stuff\n"
        ctx.stdio_sink.stderr "Something went wrong!\n"
    end,
}
```

## `ContextualFs`

`ContextualFs` is a class that provides file system operations using paths relative from the current working directory
of its associated `InstallContext`[#installcontext].

### `ContextualFs:append_file(rel_path, contents)`

**Parameters:**

-   `rel_path`: `string`
-   `contents`: `string`

Appends `contents` to file located at `rel_path`.

### `ContextualFs:write_file(rel_path, contents)`

**Parameters:**

-   `rel_path`: `string`
-   `contents`: `string`

Writes `contents` to file located at `rel_path`.

### `ContextualFs:read_file(rel_path)`

**Parameters:**

-   `rel_path`: `string`

**Returns:** `string`

### `ContextualFs:file_exists(rel_path)`

**Parameters:**

-   `rel_path`: `string`

**Returns:** `boolean`

### `ContextualFs:dir_exists(rel_path)`

**Parameters:**

-   `rel_path`: `string`

**Returns:** `boolean`

### `ContextualFs:rmrf(rel_path)`

**Parameters:**

-   `rel_path`: `string`

### `ContextualFs:unlink(rel_path)`

**Parameters:**

-   `rel_path`: `string`

### `ContextualFs:rename(old_rel_path, new_rel_path)`

**Parameters:**

-   `old_rel_path`: `string`
-   `new_rel_path`: `string`

### `ContextualFs:mkdir(dir_rel_path)`

**Parameters:**

-   `dir_rel_path`: `string`

### `ContextualFs:mkdirp(dir_rel_path)`

**Parameters:**

-   `dir_rel_path`: `string`

### `ContextualFs:chmod(dir_rel_path, mode)`

**Parameters:**

-   `dir_rel_path`: `string`
-   `mode`: `integer`

## `ContextualSpawn`

**Type:** `table<string, async fun(opts: SpawnOpts)>`

Provides an interface to spawn processes (via libuv). Each process will be spawned with the current working directory of
the `InstallContext` it belongs to. stdout & stderr will automatically be captured and displayed to the user and
retained in installation logs.

Example usage:

```lua
Pkg.new {
    --- ...
    ---@async
    ---@param ctx InstallContext
    install = function(ctx)
        ctx.spawn.npm { "install", "some-package" }
        -- Calls to spawn will raise an error if it exits with a non-OK exit code or signal.
        pcall(function()
            ctx.spawn.commandoesntexist {}
        end)
    end,
}
```

## `InstallHandleState`

**Type:** `"IDLE" | "QUEUED" | "ACTIVE" | "CLOSED"`

## `InstallHandle`

An `InstallHandle` is a handle for observing and controlling the installation of a package.
Every package installed via Mason will be managed via a `InstallHandle` instance.

It has a finite set of states, with an initial (`IDLE`) and terminal (`CLOSED`) one. This state can be accessed via the
`InstallHandle.state` field, or through one of the `:is_idle()`, `:is_queued()`, `:is_active()`, `:is_closed()` methods.
In most cases a handler's state will transition like so:

```mermaid
stateDiagram-v2
    IDLE: IDLE
    QUEUED: QUEUED
    note right of QUEUED
        The installation has been queued and will be ran when the next permit is available (according to the user's
        settings.)
        It can now be aborted via the :terminate() method.
    end note
    ACTIVE: ACTIVE
    note right of ACTIVE
        The installation has now started. The handler will emit `stdout` and `stderr` events.
        The installation can also be cancelled via the :terminate() method, and you can send signals
        to running processes via :kill({signal}).
    end note
    CLOSED: CLOSED
    note right of CLOSED
        The installation is now finished, and all associated resources have been closed.
        This is the final state and the handler will not emit any more events.
    end note
    [*] --> IDLE
    IDLE --> QUEUED
    QUEUED --> ACTIVE
    ACTIVE --> CLOSED
    CLOSED --> [*]
```

**Events**

This class extends the [EventEmitter](#eventemitter) interface and emits the following events:

| Event          | Handler signature                                                   |
| -------------- | ------------------------------------------------------------------- |
| `stdout`       | `fun(chunk: string)`                                                |
| `stderr`       | `fun(chunk: string)`                                                |
| `state:change` | `fun(new_state: InstallHandleState, old_state: InstallHandleState)` |
| `kill`         | `fun(signal: integer)`                                              |
| `terminate`    | `fun()`                                                             |
| `closed`       | `fun()`                                                             |

### `InstallHandle.package`

**Type:** [`Package`](#package)

### `InstallHandle.state`

**Type:** [`InstallHandleState`](#installhandlestate)

### `InstallHandle.is_terminated`

**Type:** `boolean`

### `InstallHandle:is_idle()`

**Returns:** `boolean`

### `InstallHandle:is_queued()`

**Returns:** `boolean`

### `InstallHandle:is_active()`

**Returns:** `boolean`

### `InstallHandle:is_closed()`

**Returns:** `boolean`

### `InstallHandle:kill({signal})`

**Parameters:**

-   `signal`: `integer` The `signal(3)` to send.

### `InstallHandle:terminate()`

Instructs the handle to terminate itself. On Windows, this will issue a
`taskkill.exe` treekill on all attached libuv handles. On Unix, this will
issue a SIGTERM signal to all attached libuv handles.

## `EventEmitter`

The `EventEmitter` interface includes methods to subscribe (and unsubscribe)
to events on the associated object.

### `EventEmitter:on({event}, {handler})`

**Parameters:**

-   `event`: `string`
-   `handler`: `fun(...)`

Registers the provided `{handler}`, to be called every time the provided
`{event}` is dispatched.

_Note that the provided `{handler}` may be executed outside the main Neovim loop (`:h vim.in_fast_event()`), where most
of the Neovim API is disabled._

### `EventEmitter:once({event, handler})`

**Parameters:**

-   `event`: `string`
-   `handler`: `fun(...)`

Registers the provided `{handler}`, to be called only once - the next time the
provided `{event}` is dispatched.

_Note that the provided `{handler}` may be executed outside the main Neovim loop (`:h vim.in_fast_event()`), where most
of the Neovim API is disabled._

### `EventEmitter:off({event}, {handler})`

**Parameters:**

-   `event`: `string`
-   `handler`: `fun(...)`

Deregisters the provided `{handler}` for the provided `{event}`.
