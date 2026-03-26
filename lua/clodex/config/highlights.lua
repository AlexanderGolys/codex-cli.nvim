--- Highlight color source definition that can map through existing highlight groups.
---@class Clodex.Config.HighlightColorRef
---@field from string|string[]
---@field attr? "fg"|"bg"|"sp"
---@field adjust? number

--- Accepted color type for a highlight field.
---@alias Clodex.Config.HighlightColor string|integer|Clodex.Config.HighlightColorRef

--- Complete description of one Neovim highlight group.
---@class Clodex.Config.HighlightSpec
---@field link? string
---@field fg? Clodex.Config.HighlightColor
---@field bg? Clodex.Config.HighlightColor
---@field sp? Clodex.Config.HighlightColor
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
---@class Clodex.Config.Highlights
---@field groups table<string, Clodex.Config.HighlightSpec>

--- Default highlight definitions bundled with clodex.
---@type Clodex.Config.Highlights
local M = {
  groups = {
    ClodexQueueNormal = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      blend = 0,
    },
    ClodexQueueFocusActive = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = -0.28 },
      blend = 0,
    },
    ClodexQueueFocusInactive = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Normal" }, attr = "bg" },
      blend = 0,
    },
    ClodexPickerProject = {
      fg = { from = { "DiagnosticError", "ErrorMsg" } },
      bold = true,
    },
    ClodexPickerRoot = {
      fg = { from = "Directory" },
      italic = true,
    },
    ClodexPromptImprovementTitle = {
      fg = { from = "@constructor" },
      bold = false,
    },
    ClodexPromptImprovementKindName = {
      fg = { from = "@constructor" },
      bold = true,
    },
    ClodexPromptTodoTitle = {
      link = "ClodexPromptImprovementTitle",
    },
    ClodexPromptTodoKindName = {
      link = "ClodexPromptImprovementKindName",
    },
    ClodexPromptBugTitle = {
      fg = { from = "DiagnosticError" },
      bold = true,
    },
    ClodexPromptNotWorkingTitle = {
      fg = { from = "DiagnosticError", adjust = 0.18 },
      bold = true,
    },
    ClodexPromptFixTitle = {
      fg = { from = { "Normal", "NormalFloat" } },
      bold = true,
    },
    ClodexPromptFreeformTitle = {
      link = "ClodexPromptFixTitle",
    },
    ClodexPromptAdjustmentTitle = {
      link = "ClodexPromptFixTitle",
    },
    ClodexPromptFeatureTitle = {
      fg = { from = "Function" },
      bold = true,
    },
    ClodexPromptRestructureTitle = {
      fg = { from = "String" },
      bold = true,
    },
    ClodexPromptRefactorTitle = {
      link = "ClodexPromptRestructureTitle",
    },
    ClodexPromptVisionTitle = {
      fg = { from = "PreProc" },
      bold = true,
    },
    ClodexPromptIdeaTitle = {
      link = "ClodexPromptVisionTitle",
    },
    ClodexPromptCleanupTitle = {
      fg = { from = "Comment" },
      bold = true,
    },
    ClodexPromptDocsTitle = {
      fg = { from = "Special" },
      bold = true,
    },
    ClodexPromptExplainTitle = {
      fg = { from = "Type" },
      bold = true,
    },
    ClodexPromptImprovementTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptImprovementTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptTodoTitleActive = {
      link = "ClodexPromptImprovementTitleActive",
    },
    ClodexPromptBugTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptBugTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptNotWorkingTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptNotWorkingTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptFixTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptFixTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptFreeformTitleActive = {
      link = "ClodexPromptFixTitleActive",
    },
    ClodexPromptFeatureTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptFeatureTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptRestructureTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptRestructureTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptRefactorTitleActive = {
      link = "ClodexPromptRestructureTitleActive",
    },
    ClodexPromptVisionTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptVisionTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptIdeaTitleActive = {
      link = "ClodexPromptVisionTitleActive",
    },
    ClodexPromptCleanupTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptCleanupTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptDocsTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptDocsTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptExplainTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptExplainTitle", attr = "fg" },
      bold = true,
    },
    ClodexPromptSourceTab = {
      fg = { from = { "Comment", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bold = true,
    },
    ClodexPromptSourceTabActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = { "Comment", "Normal" }, attr = "fg" },
      bold = true,
    },
    ClodexPromptPreviewText = {
      fg = { from = "Directory" },
    },
    ClodexPromptFixPreviewText = {
      fg = { from = { "Comment", "LineNr", "Normal" } },
    },
    ClodexPromptFreeformPreviewText = {
      link = "ClodexPromptFixPreviewText",
    },
    ClodexBookmarkLine = {
      bg = { from = { "CursorLine", "Visual" }, attr = "bg" },
    },
    ClodexBookmarkVirtualText = {
      fg = { from = { "DiagnosticHint", "Comment" } },
      italic = true,
    },
    ClodexQueueProjectActive = {
      fg = { from = "Directory" },
      bold = true,
    },
    ClodexQueueProjectCurrent = {
      fg = { from = { "DiagnosticOk", "Directory" } },
      bold = true,
    },
    ClodexQueueProjectInactive = {
      fg = { from = "Comment" },
      italic = true,
    },
    ClodexQueueCounts = {
      fg = { from = "Identifier" },
    },
    ClodexQueueHeader = {
      fg = { from = "Title" },
      bold = true,
    },
    ClodexQueueItem = {
      fg = { from = "Normal" },
    },
    ClodexQueueItemMuted = {
      fg = { from = { "Comment", "Normal" } },
    },
    ClodexQueueFooter = {
      fg = { from = { "Comment", "Normal" } },
    },
    ClodexProjectRemoteAttached = {
      fg = { from = "GitSignsAdd" },
      bold = true,
    },
    ClodexProjectRemoteDetached = {
      fg = { from = { "Comment", "NonText" } },
      bold = true,
    },
    ClodexQueueSelectionActive = {
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = 0.10 },
      blend = 0,
    },
    ClodexQueueSelectionInactive = {
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = 0.04 },
      blend = 0,
    },
    ClodexQueueActiveBorder = {
      fg = { from = { "Identifier", "FloatBorder" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = -0.28 },
      bold = true,
    },
    ClodexQueueInactiveBorder = {
      fg = { from = { "Comment", "FloatBorder" } },
      bg = { from = { "NormalFloat", "Normal" }, attr = "bg" },
    },
    ClodexPromptEditorNormal = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      blend = 0,
    },
    ClodexPromptEditorBorder = {
      fg = { from = { "Identifier", "FloatBorder" } },
      bold = true,
    },
    ClodexPromptEditorTitle = {
      fg = { from = { "Title", "Identifier" } },
      bold = true,
    },
    ClodexPromptEditorSubtitle = {
      fg = { from = { "Comment", "Normal" } },
      italic = true,
    },
    ClodexPromptEditorFooter = {
      fg = { from = { "Comment", "LineNr" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
    },
    ClodexPromptEditorHint = {
      fg = { from = { "Comment", "LineNr" } },
      bg = { from = { "ColorColumn", "Visual", "Pmenu" }, attr = "bg" },
    },
    ClodexPromptEditorKey = {
      fg = { from = { "Identifier", "Special" } },
      bold = true,
    },
    ClodexPromptEditorContext = {
      fg = "#4aa8d8",
      bold = true,
    },
    ClodexTerminalStatusline = {
      fg = { from = { "Comment", "Normal" } },
      bg = { from = { "Normal", "NormalFloat" }, attr = "bg" },
    },
    ClodexTerminalStatuslineActive = {
      fg = { from = { "Normal", "Title" } },
      bg = { from = { "Normal", "NormalFloat" }, attr = "bg" },
      bold = true,
    },
    ClodexConfirmButton = {
      fg = { from = { "Comment", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bold = true,
    },
    ClodexConfirmButtonActive = {
      fg = { from = { "Title", "Identifier" } },
      bg = { from = { "CursorLine", "PmenuSel", "Visual" }, attr = "bg" },
      bold = true,
    },
    ClodexQueueTodoName = {
      fg = "#d8873a",
      bold = true,
    },
    ClodexQueueTodoBracket = {
      fg = "#eab36f",
    },
    ClodexQueueTodoCount = {
      fg = "#f5c78a",
      bold = true,
    },
    ClodexQueueQueuedName = {
      fg = "#4aa8d8",
      bold = true,
    },
    ClodexQueueQueuedBracket = {
      fg = "#74c2e8",
    },
    ClodexQueueQueuedCount = {
      fg = "#9ad8f2",
      bold = true,
    },
    ClodexQueueImplementedName = {
      fg = "#f5a0d0",
      bold = true,
    },
    ClodexQueueImplementedBracket = {
      fg = "#f8b8dc",
    },
    ClodexQueueImplementedCount = {
      fg = "#fcd0e8",
      bold = true,
    },
    ClodexQueueHistoryName = {
      fg = "#79b98f",
      bold = true,
    },
    ClodexQueueHistoryBracket = {
      fg = "#9ad0ac",
    },
    ClodexQueueHistoryCount = {
      fg = "#b7e1c4",
      bold = true,
    },
    ClodexStateSection = {
      fg = { from = "Directory" },
    },
    ClodexStateFieldLabel = {
      fg = { from = "@constructor" },
    },
    ClodexStateStatusActive = {
      fg = { from = "@diff.plus" },
    },
    ClodexStateStatusStopped = {
      fg = { from = "ErrorMsg" },
    },
    ClodexStateStatusOffline = {
      fg = { from = "@error" },
    },
    ClodexStateBoolean = {
      fg = { from = "@boolean" },
    },
    ClodexStateNil = {
      fg = { from = "@constant" },
    },
    ClodexStateMarker = {
      fg = { from = "SpecialChar" },
    },
    ClodexStateEntryTitle = {
      fg = { from = "Identifier" },
    },
    ClodexStateCommandName = {
      fg = { from = "Identifier" },
    },
    ClodexStateCommandHint = {
      fg = { from = "Comment" },
    },
    ClodexCommitId = {
      fg = "#e0af68",
      bold = true,
    },
  },
}

return M
