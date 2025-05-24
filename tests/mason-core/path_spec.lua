local path = require "mason-core.path"

describe("path", function()
    it("concatenates paths", function()
        assert.equals("foo/bar/baz", path.concat { "foo", "bar", "baz" })
        assert.equals("foo/bar/baz", path.concat { "foo/", "bar/", "baz/" })
    end)

    it("identifies subdirectories", function()
        assert.is_true(path.is_subdirectory("/foo/bar", "/foo/bar/baz"))
        assert.is_true(path.is_subdirectory("/foo/bar", "/foo/bar"))
        assert.is_false(path.is_subdirectory("/foo/bar", "/foo/bas/baz"))
        assert.is_false(path.is_subdirectory("/foo/bar", "/foo/bars/baz"))
    end)

    describe("relative ::", function()
        local matrix = {
            {
                from = "/home/user/dir1/fileA",
                to = "/home/user/dir1/fileB",
                expected = "fileB",
            },
            {
                from = "/home/user/dir1/fileA",
                to = "/home/user/dir2/fileC",
                expected = "../dir2/fileC",
            },
            {
                from = "/home/user/dir1/subdir/fileD",
                to = "/home/user/dir1/fileE",
                expected = "../fileE",
            },
            {
                from = "/home/user/dir1/subdir/fileD",
                to = "/home/user/dir1/subdir/fileF",
                expected = "fileF",
            },
            {
                from = "/home/user/dir1/fileG",
                to = "/home/user/dir2/subdir/fileH",
                expected = "../dir2/subdir/fileH",
            },
            {
                from = "/home/user/dir1/subdir1/subdir2/fileI",
                to = "/home/user/dir1/fileJ",
                expected = "../../fileJ",
            },
            {
                from = "/fileK",
                to = "/home/fileL",
                expected = "home/fileL",
            },
            {
                from = "/home/user/fileM",
                to = "/home/user/dir1/dir2/fileL",
                expected = "dir1/dir2/fileL",
            },
        }

        for _, test_case in ipairs(matrix) do
            it(("should resolve from %s to %s: %s"):format(test_case.from, test_case.to, test_case.expected), function()
                assert.equals(test_case.expected, path.relative(test_case.from, test_case.to))
            end)
        end
    end)
end)
