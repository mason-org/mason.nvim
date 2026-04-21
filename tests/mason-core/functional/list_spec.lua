local Optional = require "mason-core.optional"
local _ = require "mason-core.functional"
local spy = require "luassert.spy"

describe("functional: list", function()
    it("should produce list without nils", function()
        assert.same({ 1, 2, 3, 4 }, _.list_not_nil(nil, 1, 2, nil, 3, nil, 4, nil))
    end)

    it("makes a shallow copy of a list", function()
        local list = { "BLUE", { nested = "TABLE" }, "RED" }
        local list_copy = _.list_copy(list)
        assert.same({ "BLUE", { nested = "TABLE" }, "RED" }, list_copy)
        assert.is_false(list == list_copy)
        assert.is_true(list[2] == list_copy[2])
    end)

    it("reverses lists", function()
        local colors = { "BLUE", "YELLOW", "RED" }
        assert.same({
            "RED",
            "YELLOW",
            "BLUE",
        }, _.reverse(colors))
        -- should not modify in-place
        assert.same({ "BLUE", "YELLOW", "RED" }, colors)
    end)

    it("maps over list", function()
        local colors = { "BLUE", "YELLOW", "RED" }
        assert.same(
            {
                "LIGHT_BLUE",
                "LIGHT_YELLOW",
                "LIGHT_RED",
            },
            _.map(function(color)
                return "LIGHT_" .. color
            end, colors)
        )
        -- should not modify in-place
        assert.same({ "BLUE", "YELLOW", "RED" }, colors)
    end)

    it("filter_map over list", function()
        local colors = { "BROWN", "BLUE", "YELLOW", "GREEN", "CYAN" }
        assert.same(
            {
                "BROWN EYES",
                "BLUE EYES",
                "GREEN EYES",
            },
            _.filter_map(function(color)
                if _.any_pass({ _.equals "BROWN", _.equals "BLUE", _.equals "GREEN" }, color) then
                    return Optional.of(("%s EYES"):format(color))
                else
                    return Optional.empty()
                end
            end, colors)
        )
    end)

    it("finds first item that fulfills predicate", function()
        local predicate = spy.new(function(item)
            return item == "Waldo"
        end)

        assert.equals(
            "Waldo",
            _.find_first(predicate, {
                "Where",
                "On Earth",
                "Is",
                "Waldo",
                "?",
            })
        )
        assert.spy(predicate).was.called(4)
    end)

    it("determines whether any item in the list fulfills predicate", function()
        local predicate = spy.new(function(item)
            return item == "On Earth"
        end)

        assert.is_true(_.any(predicate, {
            "Where",
            "On Earth",
            "Is",
            "Waldo",
            "?",
        }))

        assert.spy(predicate).was.called(2)
    end)

    it("should check that all items in list fulfills predicate", function()
        assert.is_true(_.all(_.is "string", {
            "Where",
            "On Earth",
            "Is",
            "Waldo",
            "?",
        }))

        local predicate = spy.new(_.is "string")

        assert.is_false(_.all(predicate, {
            "Five",
            "Plus",
            42,
            "Equals",
            47,
        }))
        assert.spy(predicate).was_called(3)
    end)

    it("should iterate list in .each", function()
        local list = { "BLUE", "YELLOW", "RED" }
        local iterate_fn = spy.new()
        _.each(iterate_fn, list)
        assert.spy(iterate_fn).was_called(3)
        assert.spy(iterate_fn).was_called_with("BLUE", 1)
        assert.spy(iterate_fn).was_called_with("YELLOW", 2)
        assert.spy(iterate_fn).was_called_with("RED", 3)
    end)

    it("should concat list tables", function()
        local list = { "monstera", "tulipa", "carnation" }
        assert.same({ "monstera", "tulipa", "carnation", "rose", "daisy" }, _.concat(list, { "rose", "daisy" }))
        assert.same({ "monstera", "tulipa", "carnation" }, list) -- does not mutate list
    end)

    it("should concat strings", function()
        assert.equals("FooBar", _.concat("Foo", "Bar"))
    end)

    it("should zip list into table", function()
        local fnkey = function() end
        assert.same({
            a = "a",
            [fnkey] = 1,
        }, _.zip_table({ "a", fnkey }, { "a", 1 }))
    end)

    it("should get nth item", function()
        assert.equals("first", _.nth(1, { "first", "middle", "last" }))
        assert.equals("last", _.nth(-1, { "first", "middle", "last" }))
        assert.equals("middle", _.nth(-2, { "first", "middle", "last" }))
        assert.equals("a", _.nth(1, "abc"))
        assert.equals("c", _.nth(-1, "abc"))
        assert.equals("b", _.nth(-2, "abc"))
        assert.is_nil(_.nth(0, { "value" }))
        assert.equals("", _.nth(0, "abc"))
    end)

    it("should get length", function()
        assert.equals(0, _.length {})
        assert.equals(0, _.length { nil })
        assert.equals(0, _.length { obj = "doesnt count" })
        assert.equals(0, _.length "")
        assert.equals(1, _.length { "" })
        assert.equals(4, _.length "fire")
    end)

    it("should sort by comparator", function()
        local list = {
            {
                name = "William",
            },
            {
                name = "Boman",
            },
        }
        assert.same({
            {
                name = "Boman",
            },
            {
                name = "William",
            },
        }, _.sort_by(_.prop "name", list))

        -- Should not mutate original list
        assert.same({
            {
                name = "William",
            },
            {
                name = "Boman",
            },
        }, list)
    end)

    it("should append to list", function()
        local list = { "Earth", "Wind" }
        assert.same({ "Earth", "Wind", { "Fire" } }, _.append({ "Fire" }, list))

        -- Does not mutate original list
        assert.same({ "Earth", "Wind" }, list)
    end)

    it("should prepend to list", function()
        local list = { "Fire" }
        assert.same({ { "Earth", "Wind" }, "Fire" }, _.prepend({ "Earth", "Wind" }, list))

        -- Does not mutate original list
        assert.same({ "Fire" }, list)
    end)

    it("joins lists", function()
        assert.equals("Hello, John", _.join(", ", { "Hello", "John" }))
    end)

    it("should uniq_by lists", function()
        local list = { "Person.", "Woman.", "Man.", "Person.", "Woman.", "Camera.", "TV." }
        assert.same({ "Person.", "Woman.", "Man.", "Camera.", "TV." }, _.uniq_by(_.identity, list))
    end)

    it("should partition lists", function()
        local words = { "person", "Woman", "Man", "camera", "TV" }
        assert.same({
            { "Woman", "Man", "TV" },
            { "person", "camera" },
        }, _.partition(_.matches "%u", words))
    end)

    it("should return head", function()
        assert.equals("Head", _.head { "Head", "Tail", "Tail" })
    end)

    it("should return last", function()
        assert.equals("Last", _.last { "Head", "List", "Last" })
    end)

    it("should take n items", function()
        local list = { "First", "Second", "Third", "I", "Have", "Poor", "Imagination" }
        assert.same({ "First", "Second", "Third" }, _.take(3, list))
        assert.same({}, _.take(0, list))
        assert.same({ "First", "Second", "Third", "I", "Have", "Poor", "Imagination" }, _.take(10000, list))
    end)

    it("should drop n items", function()
        local list = { "First", "Second", "Third", "I", "Have", "Poor", "Imagination" }
        assert.same({ "I", "Have", "Poor", "Imagination" }, _.drop(3, list))
        assert.same({ "First", "Second", "Third", "I", "Have", "Poor", "Imagination" }, _.drop(0, list))
        assert.same({}, _.drop(10000, list))
    end)

    it("should drop last n items", function()
        local list = { "First", "Second", "Third", "I", "Have", "Poor", "Imagination" }
        assert.same({ "First", "Second", "Third" }, _.drop_last(4, list))
        assert.same({ "First", "Second", "Third", "I", "Have", "Poor", "Imagination" }, _.drop_last(0, list))
        assert.same({}, _.drop_last(10000, list))
    end)

    it("should reduce lists", function()
        local add = spy.new(_.add)
        assert.equals(15, _.reduce(add, 0, { 1, 2, 3, 4, 5 }))
        assert.spy(add).was_called(5)
        assert.spy(add).was_called_with(0, 1)
        assert.spy(add).was_called_with(1, 2)
        assert.spy(add).was_called_with(3, 3)
        assert.spy(add).was_called_with(6, 4)
        assert.spy(add).was_called_with(10, 5)
    end)

    it("should split lists", function()
        assert.same({
            { 1, 2, 3 },
            { 4, 5, 6 },
            { 7 },
        }, _.split_every(3, { 1, 2, 3, 4, 5, 6, 7 }))

        assert.same({ { 1, 2, 3 } }, _.split_every(5, { 1, 2, 3 }))
        assert.same({ { 1 }, { 2 }, { 3 } }, _.split_every(1, { 1, 2, 3 }))

        assert.has_error(function()
            _.split_every(0, {})
        end)
    end)

    it("should index_by lists", function()
        assert.same(
            {
                apple = { fruit = "apple", color = "red" },
                banana = { fruit = "banana", color = "yellow" },
            },
            _.index_by(_.prop "fruit", {
                { fruit = "apple", color = "red" },
                { fruit = "banana", color = "yellow" },
            })
        )
    end)

    it("should flatten tables", function()
        assert.same({ 1, 2, 3 }, _.flatten { 1, 2, 3 })
        assert.same({ 1, 2, 3, "a" }, _.flatten { 1, { 2 }, { 3 }, "a" })
        assert.same({ 1, 2, 3, 4, 5 }, _.flatten { 1, { { 2, 3 }, { 4 } }, { 5 } })
    end)

    -- Note: this is not necessarily a requirement, but it is expected to behave this way as of writing.
    it("should flatten keyed tables", function()
        assert.same(
            {
                "-xvf",
                "file",
            },
            _.flatten {
                { "-xvf", { "file" } },
                cmd = "tar",
                env = {
                    LC_ALL = "latin",
                },
            }
        )
    end)
end)

describe("list immutability", function()
    it("should not mutate lists", function()
        local og_list = setmetatable({ "a", "b", "c" }, {
            __newindex = function()
                error "Tried to newindex"
            end,
        })

        _.reverse(og_list)
        _.list_copy(og_list)
        _.filter(_.F, og_list)
        _.map(_.to_upper, og_list)
        _.filter_map(_.always(Optional.empty()), og_list)
        _.each(_.length, og_list)
        _.concat(og_list, { "d", "e" })
        _.append("d", og_list)
        _.prepend("0", og_list)
        _.zip_table({ "first", "second", "third" }, og_list)
        _.nth(1, og_list)
        _.head(og_list)
        _.last(og_list)
        _.length(og_list)
        _.flatten(og_list)
        _.sort_by(_.identity, og_list)
        _.uniq_by(_.identity, og_list)
        _.join(".", og_list)
        _.partition(_.equals "a", og_list)
        _.take(2, og_list)
        _.drop(2, og_list)
        _.drop_last(2, og_list)
        _.reduce(_.concat, "", og_list)

        assert.same({ "a", "b", "c" }, og_list)
    end)
end)
