local fs = require("clodex.util.fs")

---@class Clodex.ProjectCheatsheet
local Cheatsheet = {}
Cheatsheet.__index = Cheatsheet

local DEFAULT_LINES = {
    "# Project Cheatsheet",
    "",
    "- One-line reminder",
}

local function storage_path(project)
    return fs.join(project.root, ".clodex", "CHEATSHEET.md")
end

---@return Clodex.ProjectCheatsheet
function Cheatsheet.new()
    return setmetatable({}, Cheatsheet)
end

---@param project Clodex.Project
---@return string
function Cheatsheet:path(project)
    return storage_path(project)
end

---@param project Clodex.Project
---@return string[]
function Cheatsheet:read_lines(project)
    local path = self:path(project)
    if not fs.is_file(path) then
        return vim.deepcopy(DEFAULT_LINES)
    end
    return vim.fn.readfile(path)
end

---@param project Clodex.Project
---@return string[]
function Cheatsheet:items(project)
    local items = {} ---@type string[]
    for _, line in ipairs(self:read_lines(project)) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not vim.startswith(trimmed, "#") then
            trimmed = trimmed:gsub("^[-*]%s*", "")
            if trimmed ~= "" then
                items[#items + 1] = trimmed
            end
        end
    end
    return items
end

---@param project Clodex.Project
---@return integer
function Cheatsheet:count(project)
    return #self:items(project)
end

return Cheatsheet
