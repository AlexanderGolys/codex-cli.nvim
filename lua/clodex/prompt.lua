--- Shared prompt definitions and formatting helpers used across prompt actions and UI.
local KindRegistry = require("clodex.prompt.kind_registry")

---@class Clodex.PromptComposer.Spec
---@field title string
---@field details? string

---@class Clodex.Prompt.NormalizeResult
---@field title string
---@field details? string
---@field broken boolean

---@class Clodex.Prompt
---@field categories { list: fun(): Clodex.PromptCategoryDef[], get: fun(id?: string): Clodex.PromptCategoryDef, is_valid: fun(id?: string): boolean, requires_commit: fun(id?: string): boolean, commit_policy: fun(id?: string): "required"|"skip"|"optional" }
local M = {}

local WHITESPACE_SUFFIX = " [...]"
local MIDWORD_SUFFIX = "-[...]"
local TITLE_GROUP_SUFFIX = {
    todo = "ImprovementTitle",
    bug = "BugTitle",
    freeform = "FixTitle",
    adjustment = "FixTitle",
    feature = "FeatureTitle",
    refactor = "RestructureTitle",
    idea = "VisionTitle",
    cleanup = "CleanupTitle",
    docs = "DocsTitle",
    ask = "ExplainTitle",
    explain = "ExplainTitle",
    notworking = "NotWorkingTitle",
}

local function prepend_details(title, details)
    local parts = {} ---@type string[]
    local head = vim.trim(title or "")
    local tail = vim.trim(details or "")
    if head ~= "" then
        parts[#parts + 1] = head
    end
    if tail ~= "" then
        parts[#parts + 1] = tail
    end
    return #parts > 0 and table.concat(parts, "\n\n") or nil
end

M.categories = {}

---@return Clodex.PromptCategoryDef[]
function M.categories.list()
    return KindRegistry.list()
end

---@param id? string
---@return Clodex.PromptCategoryDef
function M.categories.get(id)
    return KindRegistry.get(id)
end

---@param id? string
---@return boolean
function M.categories.is_valid(id)
    return KindRegistry.is_valid(id)
end

---@param id? string
---@return boolean
function M.categories.requires_commit(id)
    return KindRegistry.requires_commit(id)
end

---@param id? string
---@return "required"|"skip"|"optional"
function M.categories.commit_policy(id)
    return KindRegistry.commit_policy(id)
end

---@param title string
---@param details? string
---@return string
function M.render(title, details)
    local lines = { vim.trim(title or "") }
    local body = details and vim.trim(details) or ""
    if body ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = body
    end
    return table.concat(lines, "\n")
end

---@param body string
---@return Clodex.PromptComposer.Spec?
function M.parse(body)
    local trimmed = vim.trim(body or "")
    if trimmed == "" then
        return nil
    end

    local lines = vim.split(trimmed, "\n", { plain = true })
    local title_index ---@type integer?
    for index, line in ipairs(lines) do
        if vim.trim(line) ~= "" then
            title_index = index
            break
        end
    end
    if not title_index then
        return nil
    end

    local title = vim.trim(lines[title_index])
    if title == "" then
        return nil
    end

    local detail_lines = {}
    for index = title_index + 1, #lines do
        detail_lines[#detail_lines + 1] = lines[index]
    end

    local details = vim.trim(table.concat(detail_lines, "\n"))
    return {
        title = title,
        details = details ~= "" and details or nil,
    }
end

---@param kind? Clodex.PromptCategory|string
---@return string
function M.title_group(kind)
    local suffix = TITLE_GROUP_SUFFIX[M.categories.get(kind).id] or TITLE_GROUP_SUFFIX.todo
    return "ClodexPrompt" .. suffix
end

---@return string
function M.preview_group()
    return "ClodexPromptPreviewText"
end

---@param kind? Clodex.PromptCategory|string
---@return string
function M.preview_group_for(kind)
    if M.categories.get(kind).id == "freeform" then
        return "ClodexPromptFixPreviewText"
    end
    return M.preview_group()
end

---@param opts { title: string, details?: string, max_width?: integer }
---@return Clodex.Prompt.NormalizeResult
function M.normalize_title(opts)
    local title = vim.trim(opts.title or "")
    local details = vim.trim(opts.details or "")
    local max_width = math.max(tonumber(opts.max_width) or 0, 1)
    if title == "" or vim.fn.strdisplaywidth(title) <= max_width then
        return {
            title = title,
            details = details ~= "" and details or nil,
            broken = false,
        }
    end

    for idx = 1, #title do
        local ch = title:sub(idx, idx)
        local next_text = title:sub(idx + 1)
        if ch:match("[%.!?]") and next_text:match("^%s+%S") then
            local prev = idx > 1 and title:sub(idx - 1, idx - 1) or ""
            if prev:match("[%w%]%)\"']") and vim.fn.strdisplaywidth(title:sub(1, idx)) <= max_width then
                return {
                    title = vim.trim(title:sub(1, idx)),
                    details = prepend_details(next_text, details),
                    broken = true,
                }
            end
        end
    end

    for idx = 1, #title do
        if title:sub(idx, idx) == "," then
            local prev = idx > 1 and title:sub(idx - 1, idx - 1) or ""
            local next_text = title:sub(idx + 1)
            if prev ~= "" and not prev:match("%s") and next_text:match("^%s+%S") then
                if vim.fn.strdisplaywidth(title:sub(1, idx)) <= max_width then
                    local tail = vim.trim(next_text)
                    if tail:sub(1, 1):match("%l") then
                        tail = tail:sub(1, 1):upper() .. tail:sub(2)
                    end
                    return {
                        title = vim.trim(title:sub(1, idx)),
                        details = prepend_details(tail, details),
                        broken = true,
                    }
                end
            end
        end
    end

    local whitespace_idx ---@type integer?
    for idx = 1, #title do
        if title:sub(idx, idx):match("%s") then
            local head = title:sub(1, idx - 1):gsub("%s+$", "")
            if head ~= "" and vim.fn.strdisplaywidth(head .. WHITESPACE_SUFFIX) <= max_width then
                whitespace_idx = idx
            end
        end
    end
    if whitespace_idx then
        return {
            title = title:sub(1, whitespace_idx - 1):gsub("%s+$", "") .. WHITESPACE_SUFFIX,
            details = prepend_details(title:sub(whitespace_idx + 1), details),
            broken = true,
        }
    end

    local best = ""
    for idx = 1, #title do
        local head = title:sub(1, idx)
        if vim.fn.strdisplaywidth(head .. MIDWORD_SUFFIX) > max_width then
            break
        end
        best = head
    end

    if best == "" then
        return {
            title = MIDWORD_SUFFIX:sub(1, math.max(max_width, 1)),
            details = prepend_details(title, details),
            broken = true,
        }
    end

    return {
        title = best .. MIDWORD_SUFFIX,
        details = prepend_details(title:sub(#best + 1), details),
        broken = true,
    }
end

return M
