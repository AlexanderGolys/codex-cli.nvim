local fs = require("clodex.util.fs")

---@class Clodex.ProjectNote
---@field title string
---@field path string
---@field summary string[]
---@field updated_at integer

---@class Clodex.ProjectNotes
local Notes = {}
Notes.__index = Notes

local function notes_dir(project)
    return fs.join(project.root, ".clodex", "project-notes")
end

local function slug(value)
    local normalized = vim.trim(value):lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
    return normalized ~= "" and normalized or "note"
end

local function note_title(lines, fallback)
    local first = vim.trim(lines[1] or "")
    if vim.startswith(first, "#") then
        first = vim.trim(first:gsub("^#+", ""))
    end
    return first ~= "" and first or fallback
end

local function summary_lines(lines)
    local summary = {} ---@type string[]
    for _, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "#") then
            summary[#summary + 1] = trimmed
        end
        if #summary >= 3 then
            break
        end
    end
    return summary
end

---@return Clodex.ProjectNotes
function Notes.new()
    return setmetatable({}, Notes)
end

---@param project Clodex.Project
---@return Clodex.ProjectNote[]
function Notes:list(project)
    local dir = notes_dir(project)
    if not fs.is_dir(dir) then
        return {}
    end

    local items = {} ---@type Clodex.ProjectNote[]
    for _, name in ipairs(vim.fn.readdir(dir)) do
        if name:sub(-3) == ".md" then
            local path = fs.join(dir, name)
            local lines = vim.fn.readfile(path)
            local stat = fs.stat(path)
            items[#items + 1] = {
                title = note_title(lines, name:gsub("%.md$", "")),
                path = path,
                summary = summary_lines(lines),
                updated_at = stat and stat.mtime and stat.mtime.sec or 0,
            }
        end
    end

    table.sort(items, function(left, right)
        if left.updated_at ~= right.updated_at then
            return left.updated_at > right.updated_at
        end
        return left.title < right.title
    end)
    return items
end

---@param project Clodex.Project
---@return integer
function Notes:count(project)
    return #self:list(project)
end

---@param project Clodex.Project
---@param title string
---@return string
function Notes:create(project, title)
    local filename = slug(title) .. ".md"
    local path = fs.join(notes_dir(project), filename)
    local suffix = 1
    while fs.exists(path) do
        suffix = suffix + 1
        path = fs.join(notes_dir(project), ("%s-%d.md"):format(slug(title), suffix))
    end
    fs.write_file(path, ("# %s\n\nSummary line 1\nSummary line 2\nSummary line 3\n\n## Details\n\n"):format(vim.trim(title)))
    return path
end

return Notes
