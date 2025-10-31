local pep440 = require "mason-core.pep440"

describe("pep440 version checking", function()
    it("should check single version specifier", function()
        assert.is_false(pep440.check_version("3.5.0", ">=3.6"))
        assert.is_true(pep440.check_version("3.6.0", ">=3.6"))
        assert.is_false(pep440.check_version("3.6.0", ">=3.6.1"))
    end)

    it("should check version specifier with lower and upper bound", function()
        assert.is_true(pep440.check_version("3.8.0", ">=3.8,<3.12"))
        assert.is_false(pep440.check_version("3.12.0", ">=3.8,<3.12"))
        assert.is_true(pep440.check_version("3.12.0", ">=3.8,<4.0.0"))
    end)

    it("should check multiple specifiers with different constraints", function()
        assert.is_false(pep440.check_version("3.5.0", "!=4.0,<=4.0,>=3.8"))
        assert.is_false(pep440.check_version("4.0.0", "!=4.0,<=4.0,>=3.8"))
        assert.is_true(pep440.check_version("3.8.1", "!=4.0,<=4.0,>=3.8"))
        assert.is_true(pep440.check_version("3.12.0", "!=4.0,<=4.0,>=3.8"))
    end)

    it("should support ~= operators", function()
        assert.is_true(pep440.check_version("3.12.0", "~=3.10"))
        assert.is_true(pep440.check_version("3.10.4", "~=3.10.0"))
        assert.is_true(pep440.check_version("3.12.4", "~=3.0"))
        assert.is_true(pep440.check_version("3.12.4", "~=3.12.4"))

        assert.is_false(pep440.check_version("4.0.0", "~=3.10"))
        assert.is_false(pep440.check_version("3.11.0", "~=3.10.0"))
        assert.is_false(pep440.check_version("3.10.0", "~=3.10.5"))
        assert.is_false(pep440.check_version("3.11.0", "~=4.0"))
    end)
end)
