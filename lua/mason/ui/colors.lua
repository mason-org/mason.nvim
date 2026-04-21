local hl_groups = {
    MasonBackdrop = { bg = "#000000", default = true },
    MasonNormal = { link = "NormalFloat", default = true },
    MasonHeader = { bold = true, fg = "#222222", bg = "#DCA561", default = true },
    MasonHeaderSecondary = { bold = true, fg = "#222222", bg = "#56B6C2", default = true },

    MasonHighlight = { fg = "#56B6C2", default = true },
    MasonHighlightBlock = { bg = "#56B6C2", fg = "#222222", default = true },
    MasonHighlightBlockBold = { bg = "#56B6C2", fg = "#222222", bold = true, default = true },

    MasonHighlightSecondary = { fg = "#DCA561", default = true },
    MasonHighlightBlockSecondary = { bg = "#DCA561", fg = "#222222", default = true },
    MasonHighlightBlockBoldSecondary = { bg = "#DCA561", fg = "#222222", bold = true, default = true },

    MasonLink = { link = "MasonHighlight", default = true },

    MasonMuted = { fg = "#888888", default = true },
    MasonMutedBlock = { bg = "#888888", fg = "#222222", default = true },
    MasonMutedBlockBold = { bg = "#888888", fg = "#222222", bold = true, default = true },

    MasonError = { link = "ErrorMsg", default = true },
    MasonWarning = { link = "WarningMsg", default = true },

    MasonHeading = { bold = true, default = true },
}

for name, hl in pairs(hl_groups) do
    vim.api.nvim_set_hl(0, name, hl)
end
