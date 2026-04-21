local Result = require "mason-core.result"
local _ = require "mason-core.functional"
local expr = require "mason-core.installer.compiler.expr"
local match = require "luassert.match"

describe("registry expressions", function()
    it("should eval simple expressions", function()
        assert.same(Result.success "Hello, world!", expr.interpolate("Hello, world!", {}))

        assert.same(
            Result.success "Hello, John Doe!",
            expr.interpolate("Hello, {{firstname}} {{ lastname   }}!", {
                firstname = "John",
                lastname = "Doe",
            })
        )
    end)

    it("should eval nested access", function()
        assert.same(
            Result.success "Hello, world!",
            expr.interpolate("Hello, {{greeting.name}}!", { greeting = { name = "world" } })
        )
    end)

    it("should eval benign expressions", function()
        assert.same(
            Result.success "Hello, JOHNDOE JR.!",
            expr.interpolate("Hello, {{greeting.firstname .. greeting.lastname .. tostring(tbl) | to_upper}}!", {
                greeting = { firstname = "John", lastname = "Doe" },
                tostring = tostring,
                tbl = setmetatable({}, {
                    __tostring = function()
                        return " Jr."
                    end,
                }),
            })
        )

        assert.same(
            Result.success "Gloves",
            expr.interpolate("G{{ 'Cloves' | strip_prefix(trim) }}", {
                trim = "C",
            })
        )
    end)

    it("should eval expressions with filters", function()
        assert.same(
            Result.success "Hello, MR. John!",
            expr.interpolate("Hello, {{prefix|to_upper}} {{  name | trim   }}!", {
                prefix = "Mr.",
                trim = _.trim,
                name = " John   ",
            })
        )

        assert.same(
            Result.success "Hello, Sir MR. John!",
            expr.interpolate("Hello, {{prefix|to_upper | format 'Sir %s'}} {{  name | trim   }}!", {
                format = _.format,
                trim = _.trim,
                prefix = "Mr.",
                name = " John   ",
            })
        )
    end)

    it("should not interpolate nil values", function()
        assert.same(Result.success "Hello, ", expr.interpolate("Hello, {{non_existent}}", {}))
        assert.same(Result.success "", expr.interpolate("{{non_existent}}", {}))
    end)

    it("should error if piping nil values to functions that require non-nil values", function()
        local err = assert.has_error(function()
            expr.interpolate("Hello, {{ non_existent | to_upper }}", {}):get_or_throw()
        end)
        assert.is_true(match.matches "attempt to index local 'str' %(a nil value%)$"(err))
    end)

    it("should reject invalid filters", function()
        assert.is_true(
            match.matches [[^.*Invalid filter expression: "whut"]](
                expr.interpolate("Hello, {{ value | whut }}", { value = "value" }):err_or_nil()
            )
        )
        assert.is_true(
            match.matches [[^.*Failed to parse expression: "wh%-!uut"]](
                expr.interpolate("Hello, {{ value | wh-!uut }}", { value = "value" }):err_or_nil()
            )
        )
    end)
end)

describe("expr filters :: equals/not_equals", function()
    it("should equals", function()
        assert.same(
            Result.success "true",
            expr.interpolate("{{equals('Hello, world!', value)}}", {
                value = "Hello, world!",
            })
        )

        assert.same(
            Result.success "true",
            expr.interpolate("{{ value | equals('Hello, world!') }}", {
                value = "Hello, world!",
            })
        )

        assert.same(
            Result.success "false",
            expr.interpolate("{{ value | equals('Hello, John!') }}", {
                value = "Hello, world!",
            })
        )
    end)

    it("should not equals", function()
        assert.same(
            Result.success "true",
            expr.interpolate("{{not_equals('Hello, John!', value)}}", {
                value = "Hello, world!",
            })
        )

        assert.same(
            Result.success "true",
            expr.interpolate("{{ value | not_equals('Hello, John!') }}", {
                value = "Hello, world!",
            })
        )

        assert.same(
            Result.success "false",
            expr.interpolate("{{ value | not_equals('Hello, world!') }}", {
                value = "Hello, world!",
            })
        )
    end)
end)

describe("expr filters :: take_if{_not}", function()
    it("should take if value matches", function()
        assert.same(
            Result.success "Hello, world!",
            expr.interpolate("Hello, {{ take_if(equals('world!'), value) }}", {
                value = "world!",
            })
        )

        assert.same(
            Result.success "Hello, world!",
            expr.interpolate("Hello, {{ value | take_if(equals('world!')) }}", {
                value = "world!",
            })
        )

        assert.same(
            Result.success "",
            expr.interpolate("{{ take_if(equals('Hello John!'), greeting) }}", {
                greeting = "Hello World!",
            })
        )

        assert.same(
            Result.success "",
            expr.interpolate("{{ take_if(false, greeting) }}", {
                greeting = "Hello World!",
            })
        )

        assert.same(
            Result.success "Hello World!",
            expr.interpolate("{{ take_if(true, greeting) }}", {
                greeting = "Hello World!",
            })
        )
    end)

    it("should not take if value matches", function()
        assert.same(
            Result.success "Hello, world!",
            expr.interpolate("Hello, {{ take_if_not(equals('John!'), value) }}", {
                value = "world!",
            })
        )

        assert.same(
            Result.success "Hello, world!",
            expr.interpolate("Hello, {{ value | take_if_not(equals('john!')) }}", {
                value = "world!",
            })
        )

        assert.same(
            Result.success "",
            expr.interpolate("{{ take_if_not(equals('Hello World!'), greeting) }}", {
                greeting = "Hello World!",
            })
        )

        assert.same(
            Result.success "Hello World!",
            expr.interpolate("{{ take_if_not(false, greeting) }}", {
                greeting = "Hello World!",
            })
        )

        assert.same(
            Result.success "",
            expr.interpolate("{{ take_if_not(true, greeting) }}", {
                greeting = "Hello World!",
            })
        )
    end)
end)

describe("expr filters :: strip_{suffix,prefix}", function()
    it("should strip prefix", function()
        assert.same(
            Result.success "1.0.0",
            expr.interpolate([[{{value | strip_prefix("v") }}]], {
                value = "v1.0.0",
            })
        )
    end)

    it("should strip suffix", function()
        assert.same(
            Result.success "bin/file",
            expr.interpolate([[{{value | strip_suffix(".tar.gz") }}]], {
                value = "bin/file.tar.gz",
            })
        )
    end)
end)

describe("table interpolation", function()
    it("should interpolate nested values", function()
        assert.same(
            Result.success {
                some = {
                    nested = {
                        value = "here",
                    },
                },
            },
            expr.tbl_interpolate({
                some = {
                    nested = {
                        value = "{{value}}",
                    },
                },
            }, { value = "here" })
        )
    end)

    it("should only only interpolate string values", function()
        assert.same(
            Result.success {
                a = 1,
                b = { c = 2 },
                d = "Hello!",
            },
            expr.tbl_interpolate({
                a = 1,
                b = { c = 2 },
                d = "Hello!",
            }, {})
        )
    end)

    it("should interpolate string keys", function()
        assert.same(
            Result.success {
                ["a-1.2.3"] = "1.2.3",
                [12] = "12",
            },
            expr.tbl_interpolate({
                ["a-{{version}}"] = "{{version}}",
                [12] = "12",
            }, { version = "1.2.3" })
        )
    end)
end)
