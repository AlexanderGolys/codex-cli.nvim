local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")

local M = {}

---@param path string
---@param primary boolean
---@return string
local function image_reference(path, primary)
    return (primary and "Use the attached clipboard image at `%s` as the primary context."
        or "Use the attached clipboard image at `%s` as additional context."):format(path)
end

---@param text string?
---@param context Clodex.PromptContext.Capture?
---@return string?
local function expand_field(text, context)
    text = text and vim.trim(text) or ""
    if text == "" then
        return nil
    end
    return PromptContext.expand_text(text, context)
end

---@param state table
---@return Clodex.AppPromptActions.AddTodoSpec?
function M.build_spec(state)
    local title = expand_field(state.title, state.context)
    local details = expand_field(state.details, state.context)
    local image_path = state.image_path

    if state.kind == "bug" and state.variant == "clipboard_error" then
        local parts = {}
        local preview = state.preview_text and vim.trim(state.preview_text) or ""
        if preview ~= "" then
            parts[#parts + 1] = ("Bug message:\n```\n%s\n```"):format(preview)
        end
        if details then
            parts[#parts + 1] = details
        end
        parts[#parts + 1] = "Explain the cause, implement a fix if needed, and mention any follow-up validation that should be run."
        return {
            title = title or "Investigate runtime error",
            details = table.concat(parts, "\n\n"),
            kind = "bug",
            completion_target = "history",
        }
    end

    local detail_parts = {} ---@type string[]
    if image_path then
        detail_parts[#detail_parts + 1] = image_reference(image_path, state.kind == "bug" and state.variant == "clipboard_screenshot")
    end
    if details then
        detail_parts[#detail_parts + 1] = details
    end

    if not title then
        return nil
    end
    return {
        title = title,
        details = #detail_parts > 0 and table.concat(detail_parts, "\n\n") or nil,
        kind = state.kind,
        image_path = image_path,
        completion_target = state.kind == "bug" and state.variant == "clipboard_screenshot" and "history" or nil,
    }
end

return M
