local InstallReceipt = require("mason-core.receipt").InstallReceipt
local fs = require "mason-core.fs"

local function fixture(file)
    return vim.json.decode(fs.sync.read_file(("./tests/fixtures/receipts/%s"):format(file)))
end

describe("receipt ::", function()
    it("should parse 1.0 structures", function()
        local receipt = InstallReceipt:new(fixture "1.0.json")

        assert.equals("angular-language-server", receipt:get_name())
        assert.equals("1.0", receipt:get_schema_version())
        assert.same({ type = "npm", package = "@angular/language-server" }, receipt:get_source())
        assert.same({
            bin = {
                ngserver = "node_modules/.bin/ngserver",
            },
        }, receipt:get_links())
        assert.is_true(receipt:is_schema_min "1.0")
    end)

    it("should parse 1.1 structures", function()
        local receipt = InstallReceipt:new(fixture "1.1.json")

        assert.equals("angular-language-server", receipt:get_name())
        assert.equals("1.1", receipt:get_schema_version())
        assert.same({
            type = "registry+v1",
            id = "pkg:npm/%40angular/language-server@16.1.8",

            source = {
                extra_packages = { "typescript@5.1.3" },
                version = "16.1.8",
                package = "@angular/language-server",
            },
        }, receipt:get_source())
        assert.same({
            bin = {
                ngserver = "node_modules/.bin/ngserver",
            },
            opt = {},
            share = {},
        }, receipt:get_links())
        assert.is_true(receipt:is_schema_min "1.1")
    end)

    it("should parse 2.0 structures", function()
        local receipt = InstallReceipt:new(fixture "2.0.json")

        assert.equals("angular-language-server", receipt:get_name())
        assert.equals("2.0", receipt:get_schema_version())
        assert.same({
            type = "registry+v1",
            id = "pkg:npm/%40angular/language-server@19.1.0",
            raw = {
                id = "pkg:npm/%40angular/language-server@19.1.0",
                extra_packages = {
                    "typescript@5.4.5",
                },
            },
        }, receipt:get_source())
        assert.same({
            bin = {
                ngserver = "node_modules/.bin/ngserver",
            },
            opt = {},
            share = {},
        }, receipt:get_links())
        assert.same({
            name = "mason-registry",
            version = "2025-05-03-lawful-clave",
            checksums = {
                ["registry.json"] = "4ae083fe8e50d0bea5382be05c7ede8d2def55ff2b6b89dc129b153039d9f2a2",
                ["registry.json.zip"] = "2116d5db7676afe7052de329db4dfbf656054d8c35ce12414eb9d58561b2fde9",
            },
            proto = "github",
            namespace = "mason-org",
        }, receipt:get_registry())
        assert.is_true(receipt:is_schema_min "2.0")
    end)

    it("should retrieve purl information", function()
        local receipt_1_0 = InstallReceipt:new(fixture "1.0.json")
        local receipt_1_1 = InstallReceipt:new(fixture "1.1.json")
        local receipt_2_0 = InstallReceipt:new(fixture "2.0.json")

        assert.is_nil(receipt_1_0:get_installed_purl())
        assert.equals("pkg:npm/%40angular/language-server@16.1.8", receipt_1_1:get_installed_purl())
        assert.equals("pkg:npm/%40angular/language-server@19.1.0", receipt_2_0:get_installed_purl())
    end)

    describe("schema versions ::", function()
        it("should check minimum compatibility", function()
            local receipt_1_0 = InstallReceipt:new { schema_version = "1.0" }
            local receipt_1_1 = InstallReceipt:new { schema_version = "1.1" }
            local receipt_2_0 = InstallReceipt:new { schema_version = "2.0" }

            assert.is_true(receipt_1_0:is_schema_min "1.0")
            assert.is_true(receipt_1_1:is_schema_min "1.0")
            assert.is_true(receipt_2_0:is_schema_min "1.0")

            assert.is_false(receipt_1_0:is_schema_min "1.1")
            assert.is_true(receipt_1_1:is_schema_min "1.1")
            assert.is_true(receipt_2_0:is_schema_min "1.1")

            assert.is_false(receipt_1_0:is_schema_min "1.2")
            assert.is_false(receipt_1_1:is_schema_min "1.2")
            assert.is_true(receipt_2_0:is_schema_min "2.0")
        end)
    end)
end)
