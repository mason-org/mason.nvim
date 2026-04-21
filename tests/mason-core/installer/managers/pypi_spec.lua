local Result = require "mason-core.result"
local match = require "luassert.match"
local path = require "mason-core.path"
local providers = require "mason-core.providers"
local pypi = require "mason-core.installer.managers.pypi"
local spawn = require "mason-core.spawn"
local spy = require "luassert.spy"
local stub = require "luassert.stub"
local test_helpers = require "mason-test.helpers"

---@param ctx InstallContext
local function venv_py(ctx)
    return path.concat {
        ctx.cwd:get(),
        "venv",
        "bin",
        "python",
    }
end

describe("pypi manager", function()
    local snapshot

    before_each(function()
        snapshot = assert.snapshot()
        stub(spawn, "python3", mockx.returns(Result.success()))
        spawn.python3.on_call_with({ "--version" }).returns(Result.success { stdout = "Python 3.11.0" })
    end)

    after_each(function()
        snapshot:revert()
    end)

    it("should init venv without upgrading pip", function()
        local ctx = test_helpers.create_context()
        stub(ctx, "promote_cwd")
        stub(providers.pypi, "get_supported_python_versions", mockx.returns(Result.failure()))

        ctx:execute(function()
            pypi.init { package = { name = "cmake-language-server", version = "0.1.10" }, upgrade_pip = false }
        end)

        assert.spy(ctx.promote_cwd).was_called(1)
        assert.spy(ctx.spawn.python3).was_called(1)
        assert.spy(ctx.spawn.python3).was_called_with {
            "-m",
            "venv",
            "--system-site-packages",
            "venv",
        }
    end)

    it("should init venv and upgrade pip", function()
        local ctx = test_helpers.create_context()
        stub(ctx, "promote_cwd")
        stub(ctx.fs, "file_exists")
        stub(providers.pypi, "get_supported_python_versions", mockx.returns(Result.failure()))
        ctx.fs.file_exists.on_call_with(match.ref(ctx.fs), "venv/bin/python").returns(true)

        ctx:execute(function()
            pypi.init {
                package = { name = "cmake-language-server", version = "0.1.10" },
                upgrade_pip = true,
                install_extra_args = { "--proxy", "http://localhost" },
            }
        end)

        assert.spy(ctx.promote_cwd).was_called(1)
        assert.spy(ctx.spawn.python3).was_called(1)
        assert.spy(ctx.spawn.python3).was_called_with {
            "-m",
            "venv",
            "--system-site-packages",
            "venv",
        }
        assert.spy(ctx.spawn[venv_py(ctx)]).was_called(1)
        assert.spy(ctx.spawn[venv_py(ctx)]).was_called_with {
            "-m",
            "pip",
            "--disable-pip-version-check",
            "install",
            "--no-user",
            "--ignore-installed",
            { "--proxy", "http://localhost" },
            { "pip" },
        }
    end)

    it("should find versioned candidates during init", function()
        local ctx = test_helpers.create_context()
        stub(ctx, "promote_cwd")
        stub(ctx.fs, "file_exists")
        stub(providers.pypi, "get_supported_python_versions", mockx.returns(Result.success ">=3.12"))
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("python3.12").returns(1)
        stub(spawn, "python3.12")
        spawn["python3.12"].on_call_with({ "--version" }).returns(Result.success { stdout = "Python 3.12.0" })
        ctx.fs.file_exists.on_call_with(match.ref(ctx.fs), "venv/bin/python").returns(true)

        ctx:execute(function()
            pypi.init {
                package = { name = "cmake-language-server", version = "0.1.10" },
                upgrade_pip = false,
                install_extra_args = {},
            }
        end)

        assert.spy(ctx.promote_cwd).was_called(1)
        assert.spy(ctx.spawn["python3.12"]).was_called(1)
        assert.spy(ctx.spawn["python3.12"]).was_called_with {
            "-m",
            "venv",
            "--system-site-packages",
            "venv",
        }
    end)

    it("should error if unable to find a suitable python3 version", function()
        local ctx = test_helpers.create_context()
        spy.on(ctx.stdio_sink, "stderr")
        stub(ctx, "promote_cwd")
        stub(ctx.fs, "file_exists")
        stub(providers.pypi, "get_supported_python_versions", mockx.returns(Result.success ">=3.8"))
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("python3.12").returns(0)
        vim.fn.executable.on_call_with("python3.11").returns(0)
        vim.fn.executable.on_call_with("python3.10").returns(0)
        vim.fn.executable.on_call_with("python3.9").returns(0)
        vim.fn.executable.on_call_with("python3.8").returns(0)
        stub(spawn, "python3", mockx.returns(Result.success()))
        spawn.python3.on_call_with({ "--version" }).returns(Result.success { stdout = "Python 3.5.0" })

        local result = ctx:execute(function()
            return pypi.init {
                package = { name = "cmake-language-server", version = "0.1.10" },
                upgrade_pip = false,
                install_extra_args = {},
            }
        end)

        assert.same(
            Result.failure "Failed to find a python3 installation in PATH that meets the required versions (>=3.8). Found version: 3.5.0.",
            result
        )
        assert
            .spy(ctx.stdio_sink.stderr)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Run with :MasonInstall --force to bypass this version validation.\n")
    end)

    it(
        "should default to stock version if unable to find suitable versioned candidate during init and when force=true",
        function()
            local ctx = test_helpers.create_context { install_opts = { force = true } }
            spy.on(ctx.stdio_sink, "stderr")
            stub(ctx, "promote_cwd")
            stub(ctx.fs, "file_exists")
            stub(providers.pypi, "get_supported_python_versions", mockx.returns(Result.success ">=3.8"))
            stub(vim.fn, "executable")
            vim.fn.executable.on_call_with("python3.12").returns(0)
            vim.fn.executable.on_call_with("python3.11").returns(0)
            vim.fn.executable.on_call_with("python3.10").returns(0)
            vim.fn.executable.on_call_with("python3.9").returns(0)
            vim.fn.executable.on_call_with("python3.8").returns(0)
            stub(spawn, "python3", mockx.returns(Result.success()))
            spawn.python3.on_call_with({ "--version" }).returns(Result.success { stdout = "Python 3.5.0" })

            ctx:execute(function()
                pypi.init {
                    package = { name = "cmake-language-server", version = "0.1.10" },
                    upgrade_pip = true,
                    install_extra_args = { "--proxy", "http://localhost" },
                }
            end)

            assert.spy(ctx.promote_cwd).was_called(1)
            assert.spy(ctx.spawn.python3).was_called(1)
            assert.spy(ctx.spawn.python3).was_called_with {
                "-m",
                "venv",
                "--system-site-packages",
                "venv",
            }
            assert.spy(ctx.stdio_sink.stderr).was_called_with(
                match.is_ref(ctx.stdio_sink),
                "Warning: The resolved python3 version 3.5.0 is not compatible with the required Python versions: >=3.8.\n"
            )
        end
    )

    it("should prioritize stock python", function()
        local ctx = test_helpers.create_context { install_opts = { force = true } }
        spy.on(ctx.stdio_sink, "stderr")
        stub(ctx, "promote_cwd")
        stub(ctx.fs, "file_exists")
        stub(providers.pypi, "get_supported_python_versions", mockx.returns(Result.success ">=3.8"))
        stub(vim.fn, "executable")
        vim.fn.executable.on_call_with("python3.12").returns(1)
        stub(spawn, "python3", mockx.returns(Result.success()))
        spawn.python3.on_call_with({ "--version" }).returns(Result.success { stdout = "Python 3.8.0" })

        ctx:execute(function()
            pypi.init {
                package = { name = "cmake-language-server", version = "0.1.10" },
                upgrade_pip = true,
                install_extra_args = { "--proxy", "http://localhost" },
            }
        end)

        assert.spy(ctx.promote_cwd).was_called(1)
        assert.spy(ctx.spawn.python3).was_called(1)
        assert.spy(ctx.spawn["python3.12"]).was_called(0)
        assert.spy(ctx.spawn.python3).was_called_with {
            "-m",
            "venv",
            "--system-site-packages",
            "venv",
        }
    end)

    it("should install", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        ctx.fs.file_exists.on_call_with(match.ref(ctx.fs), "venv/bin/python").returns(true)

        ctx:execute(function()
            pypi.install("pypi-package", "1.0.0")
        end)

        assert.spy(ctx.spawn[venv_py(ctx)]).was_called(1)
        assert.spy(ctx.spawn[venv_py(ctx)]).was_called_with {
            "-m",
            "pip",
            "--disable-pip-version-check",
            "install",
            "--no-user",
            "--ignore-installed",
            vim.NIL, -- install_extra_args
            {
                "pypi-package==1.0.0",
                vim.NIL, -- extra_packages
            },
        }
    end)

    it("should write output", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        ctx.fs.file_exists.on_call_with(match.ref(ctx.fs), "venv/bin/python").returns(true)
        spy.on(ctx.stdio_sink, "stdout")

        ctx:execute(function()
            pypi.install("pypi-package", "1.0.0")
        end)

        assert
            .spy(ctx.stdio_sink.stdout)
            .was_called_with(match.is_ref(ctx.stdio_sink), "Installing pip package pypi-package@1.0.0…\n")
    end)

    it("should install extra specifier", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        ctx.fs.file_exists.on_call_with(match.ref(ctx.fs), "venv/bin/python").returns(true)

        ctx:execute(function()
            pypi.install("pypi-package", "1.0.0", {
                extra = "lsp",
            })
        end)

        assert.spy(ctx.spawn[venv_py(ctx)]).was_called(1)
        assert.spy(ctx.spawn[venv_py(ctx)]).was_called_with {
            "-m",
            "pip",
            "--disable-pip-version-check",
            "install",
            "--no-user",
            "--ignore-installed",
            vim.NIL, -- install_extra_args
            {
                "pypi-package[lsp]==1.0.0",
                vim.NIL, -- extra_packages
            },
        }
    end)

    it("should install extra packages", function()
        local ctx = test_helpers.create_context()
        stub(ctx.fs, "file_exists")
        ctx.fs.file_exists.on_call_with(match.ref(ctx.fs), "venv/bin/python").returns(true)
        ctx:execute(function()
            pypi.install("pypi-package", "1.0.0", {
                extra_packages = { "extra-package" },
                install_extra_args = { "--proxy", "http://localhost:9000" },
            })
        end)

        assert.spy(ctx.spawn[venv_py(ctx)]).was_called(1)
        assert.spy(ctx.spawn[venv_py(ctx)]).was_called_with {
            "-m",
            "pip",
            "--disable-pip-version-check",
            "install",
            "--no-user",
            "--ignore-installed",
            { "--proxy", "http://localhost:9000" },
            {
                "pypi-package==1.0.0",
                { "extra-package" },
            },
        }
    end)
end)
