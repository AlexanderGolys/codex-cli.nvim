local fs = require("clodex.util.fs")

---@class Clodex.ProjectBookmark
---@field id string
---@field path string
---@field line integer
---@field title string
---@field description string
---@field created_at string
---@field updated_at string

---@class Clodex.ProjectBookmarksData
---@field version integer
---@field bookmarks Clodex.ProjectBookmark[]

---@class Clodex.ProjectBookmarks
---@field ns integer
---@field attached table<number, { project_root: string, marks: table<string, integer> }>
local Bookmarks = {}
Bookmarks.__index = Bookmarks

local DATA_VERSION = 1

local function now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

---@param project Clodex.Project
---@return string
local function storage_path(project)
    return fs.join(project.root, ".clodex", "bookmarks.json")
end

---@param project Clodex.Project
---@param path string
---@return string
local function relative_path(project, path)
    path = fs.normalize(path)
    if path == project.root then
        return "."
    end
    return path:sub(#project.root + 2)
end

---@param project Clodex.Project
---@param path string
---@return string
local function absolute_path(project, path)
    if path == "." then
        return project.root
    end
    return fs.join(project.root, path)
end

---@param project Clodex.Project
---@return Clodex.ProjectBookmarksData
function Bookmarks:load(project)
    local data = fs.read_json(storage_path(project), nil)
    if type(data) ~= "table" then
        data = {
            version = DATA_VERSION,
            bookmarks = {},
        }
    end
    data.version = data.version or DATA_VERSION
    data.bookmarks = data.bookmarks or {}
    return data
end

---@param project Clodex.Project
---@param data Clodex.ProjectBookmarksData
function Bookmarks:save(project, data)
    fs.write_json(storage_path(project), data)
end

---@return Clodex.ProjectBookmarks
function Bookmarks.new()
    local self = setmetatable({}, Bookmarks)
    self.ns = vim.api.nvim_create_namespace("clodex-project-bookmarks")
    self.attached = {}
    return self
end

---@param project Clodex.Project
---@return Clodex.ProjectBookmark[]
function Bookmarks:list(project)
    local items = vim.deepcopy(self:load(project).bookmarks)
    table.sort(items, function(left, right)
        if left.path ~= right.path then
            return left.path < right.path
        end
        if left.line ~= right.line then
            return left.line < right.line
        end
        return left.title < right.title
    end)
    return items
end

---@param project Clodex.Project
---@param path string
---@return Clodex.ProjectBookmark[]
function Bookmarks:list_for_path(project, path)
    local target = relative_path(project, path)
    local matches = {} ---@type Clodex.ProjectBookmark[]
    for _, bookmark in ipairs(self:list(project)) do
        if bookmark.path == target then
            matches[#matches + 1] = bookmark
        end
    end
    return matches
end

---@param project Clodex.Project
---@param spec { path: string, line: integer, title: string, description: string }
---@return Clodex.ProjectBookmark
function Bookmarks:add(project, spec)
    local data = self:load(project)
    local timestamp = now()
    local bookmark = {
        id = vim.fn.sha256(table.concat({
            project.root,
            spec.path,
            tostring(spec.line),
            spec.title,
            timestamp,
        }, "\n")):sub(1, 16),
        path = relative_path(project, spec.path),
        line = math.max(spec.line, 1),
        title = vim.trim(spec.title),
        description = vim.trim(spec.description),
        created_at = timestamp,
        updated_at = timestamp,
    }
    data.bookmarks[#data.bookmarks + 1] = bookmark
    self:save(project, data)
    return bookmark
end

---@param project Clodex.Project
---@param bookmark_id string
---@param line integer
function Bookmarks:update_line(project, bookmark_id, line)
    local data = self:load(project)
    local changed = false
    for _, bookmark in ipairs(data.bookmarks) do
        if bookmark.id == bookmark_id and bookmark.line ~= line then
            bookmark.line = math.max(line, 1)
            bookmark.updated_at = now()
            changed = true
            break
        end
    end
    if changed then
        self:save(project, data)
    end
end

---@param project Clodex.Project
---@return integer
function Bookmarks:count(project)
    return #self:load(project).bookmarks
end

---@param project Clodex.Project
---@param bookmark Clodex.ProjectBookmark
---@return string[]
function Bookmarks:preview_lines(project, bookmark)
    local path = absolute_path(project, bookmark.path)
    local lines = {
        ("# %s"):format(bookmark.title),
        "",
        bookmark.description,
        "",
        ("- File: `%s`"):format(bookmark.path),
        ("- Line: `%d`"):format(bookmark.line),
        "",
        "```",
    }
    if fs.is_file(path) then
        local file_lines = vim.fn.readfile(path)
        local start_line = math.max(bookmark.line - 2, 1)
        local end_line = math.min(bookmark.line + 2, #file_lines)
        for idx = start_line, end_line do
            local prefix = idx == bookmark.line and ">" or " "
            lines[#lines + 1] = ("%s %4d %s"):format(prefix, idx, file_lines[idx] or "")
        end
    else
        lines[#lines + 1] = "(file missing)"
    end
    lines[#lines + 1] = "```"
    return lines
end

---@param project Clodex.Project
---@param bookmark Clodex.ProjectBookmark
function Bookmarks:jump(project, bookmark)
    local path = absolute_path(project, bookmark.path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local line = math.max(bookmark.line, 1)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd.normal({ args = { "zz" }, bang = true })
end

---@param project Clodex.Project
---@param buf integer
function Bookmarks:decorate_buffer(project, buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local path = fs.normalize(vim.api.nvim_buf_get_name(buf))
    if path == "" or not fs.is_relative_to(path, project.root) then
        vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
        self.attached[buf] = nil
        return
    end

    local marks = {} ---@type table<string, integer>
    vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
    for _, bookmark in ipairs(self:list_for_path(project, path)) do
        local line = math.max(bookmark.line - 1, 0)
        if line < vim.api.nvim_buf_line_count(buf) then
            marks[bookmark.id] = vim.api.nvim_buf_set_extmark(buf, self.ns, line, 0, {
                line_hl_group = "ClodexBookmarkLine",
                virt_text = {
                    { (" %s"):format(bookmark.title), "ClodexBookmarkVirtualText" },
                },
                virt_text_pos = "eol",
                hl_mode = "combine",
            })
        end
    end
    self.attached[buf] = {
        project_root = project.root,
        marks = marks,
    }
end

---@param registry Clodex.ProjectRegistry
---@param buf integer
function Bookmarks:sync_buffer(registry, buf)
    local attached = self.attached[buf]
    if not attached or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local project = registry:get(attached.project_root)
    if not project then
        self.attached[buf] = nil
        return
    end

    for bookmark_id, extmark_id in pairs(attached.marks) do
        local position = vim.api.nvim_buf_get_extmark_by_id(buf, self.ns, extmark_id, {})
        if position and position[1] ~= nil then
            self:update_line(project, bookmark_id, position[1] + 1)
        end
    end
end

return Bookmarks
