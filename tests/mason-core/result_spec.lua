local Optional = require "mason-core.optional"
local Result = require "mason-core.result"
local a = require "mason-core.async"
local match = require "luassert.match"
local spy = require "luassert.spy"

describe("Result ::", function()
    it("should create success", function()
        local result = Result.success "Hello!"
        assert.is_true(result:is_success())
        assert.is_false(result:is_failure())
        assert.equals("Hello!", result:get_or_nil())
    end)

    it("should create failure", function()
        local result = Result.failure "Hello!"
        assert.is_true(result:is_failure())
        assert.is_false(result:is_success())
        assert.equals("Hello!", result:err_or_nil())
    end)

    it("should return value on get_or_throw()", function()
        local result = Result.success "Hello!"
        local val = result:get_or_throw()
        assert.equals("Hello!", val)
    end)

    it("should throw failure on get_or_throw()", function()
        local result = Result.failure "Hello!"
        local err = assert.has_error(function()
            result:get_or_throw()
        end)
        assert.equals("Hello!", err)
    end)

    it("should map() success", function()
        local result = Result.success "Hello"
        local mapped = result:map(function(x)
            return x .. " World!"
        end)
        assert.equals("Hello World!", mapped:get_or_nil())
        assert.is_nil(mapped:err_or_nil())
    end)

    it("should not map() failure", function()
        local result = Result.failure "Hello"
        local mapped = result:map(function(x)
            return x .. " World!"
        end)
        assert.equals("Hello", mapped:err_or_nil())
        assert.is_nil(mapped:get_or_nil())
    end)

    it("should raise exceptions in map()", function()
        local result = Result.success "failure"
        local err = assert.has_error(function()
            result:map(function()
                error "error"
            end)
        end)
        assert.equals("error", err)
    end)

    it("should map_catching() success", function()
        local result = Result.success "Hello"
        local mapped = result:map_catching(function(x)
            return x .. " World!"
        end)
        assert.equals("Hello World!", mapped:get_or_nil())
        assert.is_nil(mapped:err_or_nil())
    end)

    it("should not map_catching() failure", function()
        local result = Result.failure "Hello"
        local mapped = result:map_catching(function(x)
            return x .. " World!"
        end)
        assert.equals("Hello", mapped:err_or_nil())
        assert.is_nil(mapped:get_or_nil())
    end)

    it("should catch errors in map_catching()", function()
        local result = Result.success "value"
        local mapped = result:map_catching(function()
            error "This is an error"
        end)
        assert.is_false(mapped:is_success())
        assert.is_true(mapped:is_failure())
        assert.is_true(match.has_match "This is an error$"(mapped:err_or_nil()))
    end)

    it("should recover errors", function()
        local result = Result.failure("call an ambulance"):recover(function(err)
            return err .. ". but not for me!"
        end)
        assert.is_true(result:is_success())
        assert.equals("call an ambulance. but not for me!", result:get_or_nil())
    end)

    it("should catch errors in recover", function()
        local result = Result.failure("call an ambulance"):recover_catching(function(err)
            error("Oh no... " .. err, 2)
        end)
        assert.is_true(result:is_failure())
        assert.equals("Oh no... call an ambulance", result:err_or_nil())
    end)

    it("should return results in run_catching", function()
        local result = Result.run_catching(function()
            return "Hello world!"
        end)
        assert.is_true(result:is_success())
        assert.equals("Hello world!", result:get_or_nil())
    end)

    it("should return failures in run_catching", function()
        local result = Result.run_catching(function()
            error("Oh noes", 2)
        end)
        assert.is_true(result:is_failure())
        assert.equals("Oh noes", result:err_or_nil())
    end)

    it("should run on_failure if failure", function()
        local on_success = spy.new()
        local on_failure = spy.new()
        local result = Result.failure("Oh noes"):on_failure(on_failure):on_success(on_success)
        assert.is_true(result:is_failure())
        assert.equals("Oh noes", result:err_or_nil())
        assert.spy(on_failure).was_called(1)
        assert.spy(on_success).was_called(0)
        assert.spy(on_failure).was_called_with "Oh noes"
    end)

    it("should run on_success if success", function()
        local on_success = spy.new()
        local on_failure = spy.new()
        local result = Result.success("Oh noes"):on_failure(on_failure):on_success(on_success)
        assert.is_true(result:is_success())
        assert.equals("Oh noes", result:get_or_nil())
        assert.spy(on_failure).was_called(0)
        assert.spy(on_success).was_called(1)
        assert.spy(on_success).was_called_with "Oh noes"
    end)

    it("should convert success variants to non-empty optionals", function()
        local opt = Result.success("Hello world!"):ok()
        assert.is_true(getmetatable(opt) == Optional)
        assert.equals("Hello world!", opt:get())
    end)

    it("should convert failure variants to empty optionals", function()
        local opt = Result.failure("Hello world!"):ok()
        assert.is_true(getmetatable(opt) == Optional)
        assert.is_false(opt:is_present())
    end)

    it("should chain successful results", function()
        local success = Result.success("First"):and_then(function(value)
            return Result.success(value .. " Second")
        end)
        local failure = Result.success("Error"):and_then(Result.failure)

        assert.is_true(success:is_success())
        assert.equals("First Second", success:get_or_nil())
        assert.is_true(failure:is_failure())
        assert.equals("Error", failure:err_or_nil())
    end)

    it("should not chain failed results", function()
        local chain = spy.new()
        local failure = Result.failure("Error"):and_then(chain)

        assert.is_true(failure:is_failure())
        assert.equals("Error", failure:err_or_nil())
        assert.spy(chain).was_not_called()
    end)

    it("should chain failed results", function()
        local failure = Result.failure("First"):or_else(function(value)
            return Result.failure(value .. " Second")
        end)
        local success = Result.failure("Error"):or_else(Result.success)

        assert.is_true(success:is_success())
        assert.equals("Error", success:get_or_nil())
        assert.is_true(failure:is_failure())
        assert.equals("First Second", failure:err_or_nil())
    end)

    it("should not chain successful results", function()
        local chain = spy.new()
        local failure = Result.success("Error"):or_else(chain)

        assert.is_true(failure:is_success())
        assert.equals("Error", failure:get_or_nil())
        assert.spy(chain).was_not_called()
    end)

    it("should pcall", function()
        assert.same(
            Result.success "Great success!",
            Result.pcall(function()
                return "Great success!"
            end)
        )

        assert.same(
            Result.failure "Task failed successfully!",
            Result.pcall(function()
                error("Task failed successfully!", 0)
            end)
        )
    end)
end)

describe("Result.try", function()
    it("should try functions", function()
        assert.same(
            Result.success "Hello, world!",
            Result.try(function(try)
                local hello = try(Result.success "Hello, ")
                local world = try(Result.success "world!")
                return hello .. world
            end)
        )

        assert.same(
            Result.success(),
            Result.try(function(try)
                try(Result.success "Hello, ")
                try(Result.success "world!")
            end)
        )

        assert.same(
            Result.failure "Trouble, world!",
            Result.try(function(try)
                local trouble = try(Result.success "Trouble, ")
                local world = try(Result.success "world!")
                return try(Result.failure(trouble .. world))
            end)
        )

        local failure = Result.try(function(try)
            local err = try(Result.success "42")
            error(err, 0)
        end)
        assert.is_true(failure:is_failure())
        assert.equals("42", failure:err_or_nil())
    end)

    it("should allow calling async functions inside try blocks", function()
        assert.same(
            Result.success "Hello, world!",
            a.run_blocking(function()
                return Result.try(function(try)
                    a.sleep(10)
                    local hello = try(Result.success "Hello, ")
                    local world = try(Result.success "world!")
                    return hello .. world
                end)
            end)
        )
        local failure = a.run_blocking(function()
            return Result.try(function(try)
                a.sleep(10)
                local err = try(Result.success "42")
                error(err)
            end)
        end)
        assert.is_true(failure:is_failure())
        assert.is_true(match.matches ": 42$"(failure:err_or_nil()))
    end)

    it("should not unwrap result values in try blocks", function()
        assert.same(
            Result.failure "Error!",
            Result.try(function()
                return Result.failure "Error!"
            end)
        )

        assert.same(
            Result.success "Success!",
            Result.try(function()
                return Result.success "Success!"
            end)
        )
    end)

    it("should allow nesting try blocks", function()
        assert.same(
            Result.success "Hello from the underworld!",
            Result.try(function(try)
                local greeting = try(Result.success "Hello from the %s!")
                return greeting:format(try(Result.try(function(try)
                    return try(Result.success "underworld")
                end)))
            end)
        )
    end)

    it("should allow nesting try blocks in async scope", function()
        assert.same(
            Result.success "Hello from the underworld!",
            a.run_blocking(function()
                return Result.try(function(try)
                    a.sleep(10)
                    local greeting = try(Result.success "Hello from the %s!")
                    a.sleep(10)
                    return greeting:format(try(Result.try(function(try)
                        a.sleep(10)
                        local value = try(Result.success "underworld")
                        a.sleep(10)
                        return value
                    end)))
                end)
            end)
        )
    end)
end)
