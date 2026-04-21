return {
    name = "dummy2",
    description = [[This is a dummy2 package.]],
    homepage = "https://example.com",
    licenses = { "MIT" },
    languages = { "Dummy2Lang" },
    categories = { "LSP" },
    source = {
        id = "pkg:mason/dummy2@1.0.0",
        ---@async
        ---@param ctx InstallContext
        install = function(ctx) end,
    },
}
