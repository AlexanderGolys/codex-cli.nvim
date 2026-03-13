local fs = require("clodex.util.fs")

---@class Clodex.History
---@field path string
local M = {
    path = fs.join(vim.fn.stdpath("data"), "clodex", "history.md"),
}

---@param path string
function M.configure(path)
    M.path = fs.normalize(path)
end

---@return string
local function timestamp()
    return os.date("!%Y-%m-%d %H:%M:%S UTC")
end

---@param text string?
---@return string
local function trim_block(text)
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

---@param project_label string
---@param lines string[]
local function append_block(project_label, lines)
    local body = table.concat(lines, "\n")
    if body == "" then
        return
    end

    fs.append_file(M.path, body .. "\n\n")
end

---@param project_name string
---@param title string
---@param details? string
---@param kind? string
function M.append_prompt_added(project_name, title, details, kind)
    title = vim.trim(title or "")
    if title == "" then
        return
    end

    local lines = {
        ("--- Added new%s prompt: %s ---"):format(kind and (" " .. kind) or "", title),
        ("Project: %s"):format(project_name),
    }
    append_block(project_name, lines)
end

---@param project_name string
---@param title string
---@param summary? string
function M.append_prompt_resolved(project_name, title, summary)
    title = vim.trim(title or "")
    if title == "" then
        return
    end

    local lines = {
        ("--- Prompt %s Resolved ---"):format(title),
        ("Project: %s"):format(project_name),
    }
    local body = trim_block(summary)
    if body ~= "" then
        lines[#lines + 1] = body
    end
    append_block(project_name, lines)
end

---@param project_label string
---@param lines string[]
---@param kind? string
function M.append_conversation(project_label, lines, kind)
    local chunks = {} ---@type string[]
    for _, line in ipairs(lines or {}) do
        local trimmed = trim_block(line)
        if trimmed ~= "" then
            chunks[#chunks + 1] = trimmed
        end
    end
    if #chunks == 0 then
        return
    end

    local header
    if kind and kind ~= "" then
        header = ("----- [%s, project %s] [%s] -----"):format(kind, project_label, timestamp())
    else
        header = ("----- [project %s] [%s] -----"):format(project_label, timestamp())
    end
    local body = { header, "" }
    vim.list_extend(body, chunks)
    append_block(project_label, body)
end

function M.open()
    fs.ensure_dir(fs.dirname(M.path))
    if not fs.is_file(M.path) then
        fs.write_file(M.path, "")
    end
    vim.cmd.edit(vim.fn.fnameescape(M.path))
end

return M
