--- Highlight color source definition that can map through existing highlight groups.
---@class CodexCli.Config.HighlightColorRef
---@field from string|string[]
---@field attr? "fg"|"bg"|"sp"

--- Accepted color type for a highlight field.
---@alias CodexCli.Config.HighlightColor string|integer|CodexCli.Config.HighlightColorRef

--- Complete description of one Neovim highlight group.
---@class CodexCli.Config.HighlightSpec
---@field link? string
---@field fg? CodexCli.Config.HighlightColor
---@field bg? CodexCli.Config.HighlightColor
---@field sp? CodexCli.Config.HighlightColor
---@field blend? integer
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field undercurl? boolean
---@field reverse? boolean
---@field strikethrough? boolean
---@field default? boolean
---@field force? boolean
---@field ctermfg? integer|string
---@field ctermbg? integer|string
---@field cterm? table|integer|string

--- Container for named highlight group specifications.
---@class CodexCli.Config.Highlights
---@field groups table<string, CodexCli.Config.HighlightSpec>

--- Default highlight definitions bundled with codex-cli.
---@type CodexCli.Config.Highlights
local M = {
  groups = {
    CodexCliPickerProject = {
      fg = { from = { "DiagnosticError", "ErrorMsg" } },
      bold = true,
    },
    CodexCliPickerRoot = {
      fg = { from = "Directory" },
      italic = true,
    },
    CodexCliPromptTodoTitle = {
      fg = { from = "@constructor" },
      bold = true,
    },
    CodexCliPromptErrorTitle = {
      fg = { from = "DiagnosticError" },
      bold = true,
    },
    CodexCliPromptVisualTitle = {
      fg = { from = "Special" },
      bold = true,
    },
    CodexCliPromptAdjustmentTitle = {
      fg = { from = "Constant" },
      bold = true,
    },
    CodexCliPromptRefactorTitle = {
      fg = { from = "String" },
      bold = true,
    },
    CodexCliPromptIdeaTitle = {
      fg = { from = "PreProc" },
      bold = true,
    },
    CodexCliPromptExplainTitle = {
      fg = { from = "Type" },
      bold = true,
    },
    CodexCliPromptPreviewText = {
      fg = { from = "Directory" },
    },
    CodexCliPromptPickerTodoTitle = {
      link = "CodexCliPromptTodoTitle",
    },
    CodexCliPromptPickerErrorTitle = {
      link = "CodexCliPromptErrorTitle",
    },
    CodexCliPromptPickerVisualTitle = {
      link = "CodexCliPromptVisualTitle",
    },
    CodexCliPromptPickerAdjustmentTitle = {
      link = "CodexCliPromptAdjustmentTitle",
    },
    CodexCliPromptPickerRefactorTitle = {
      link = "CodexCliPromptRefactorTitle",
    },
    CodexCliPromptPickerIdeaTitle = {
      link = "CodexCliPromptIdeaTitle",
    },
    CodexCliPromptPickerExplainTitle = {
      link = "CodexCliPromptExplainTitle",
    },
    CodexCliPromptPickerPromptText = {
      link = "CodexCliPromptPreviewText",
    },
    CodexCliQueueProjectActive = {
      fg = { from = "Directory" },
      bold = true,
    },
    CodexCliQueueProjectInactive = {
      fg = { from = "Comment" },
      italic = true,
    },
    CodexCliQueueCounts = {
      fg = { from = "Identifier" },
    },
    CodexCliQueueHeader = {
      fg = { from = "Title" },
      bold = true,
    },
    CodexCliQueueItem = {
      fg = { from = "Normal" },
    },
    CodexCliQueueItemMuted = {
      fg = { from = "Comment" },
    },
    CodexCliQueueFooter = {
      fg = { from = "Comment" },
    },
    CodexCliQueueSelection = {
      bg = { from = { "CursorLine", "PmenuSel", "Visual" }, attr = "bg" },
    },
    CodexCliQueueActiveBorder = {
      fg = { from = { "Identifier", "FloatBorder" } },
      bold = true,
    },
    CodexCliQueueInactiveBorder = {
      fg = { from = { "Comment", "FloatBorder" } },
    },
    CodexCliQueueTodoName = {
      fg = "#d8873a",
      bold = true,
    },
    CodexCliQueueTodoBracket = {
      fg = "#eab36f",
    },
    CodexCliQueueTodoCount = {
      fg = "#f5c78a",
      bold = true,
    },
    CodexCliQueueQueuedName = {
      fg = "#d86ba9",
      bold = true,
    },
    CodexCliQueueQueuedBracket = {
      fg = "#ec96c3",
    },
    CodexCliQueueQueuedCount = {
      fg = "#f7b3d7",
      bold = true,
    },
    CodexCliQueueHistoryName = {
      fg = "#79b98f",
      bold = true,
    },
    CodexCliQueueHistoryBracket = {
      fg = "#9ad0ac",
    },
    CodexCliQueueHistoryCount = {
      fg = "#b7e1c4",
      bold = true,
    },
    CodexCliStateSection = {
      fg = { from = "Directory" },
    },
    CodexCliStateFieldLabel = {
      fg = { from = "@constructor" },
    },
    CodexCliStateStatusActive = {
      fg = { from = "@diff.plus" },
    },
    CodexCliStateStatusStopped = {
      fg = { from = "ErrorMsg" },
    },
    CodexCliStateStatusOffline = {
      fg = { from = "@error" },
    },
    CodexCliStateBoolean = {
      fg = { from = "@boolean" },
    },
    CodexCliStateNil = {
      fg = { from = "@constant" },
    },
    CodexCliStateMarker = {
      fg = { from = "SpecialChar" },
    },
    CodexCliStateEntryTitle = {
      fg = { from = "Identifier" },
    },
    CodexCliStateCommandName = {
      fg = { from = "Identifier" },
    },
    CodexCliStateCommandHint = {
      fg = { from = "Comment" },
    },
  },
}

return M
