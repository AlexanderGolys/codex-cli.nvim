local clipboard = require("clodex.util.clipboard")
local fs = require("clodex.util.fs")
local notify = require("clodex.util.notify")

local M = {}

local function is_absolute_path(path)
    path = fs.normalize(path)
    return vim.startswith(path, "/") or path:match("^%a:[/\\]") ~= nil
end

---@param workspaces_dir string
---@param project_root string
---@return string
local function storage_root(workspaces_dir, project_root)
    local root = fs.normalize(workspaces_dir)
    if is_absolute_path(root) then
        return root
    end
    return fs.join(project_root, root)
end

---@param workspaces_dir string
---@param project_root string
---@param category Clodex.PromptCategory
---@return string
function M.asset_dir(workspaces_dir, project_root, category)
    return fs.join(storage_root(workspaces_dir, project_root), "prompt-assets", category)
end

---@param workspaces_dir string
---@param project_root string
---@param category Clodex.PromptCategory
---@param ext string
---@return string
function M.asset_path(workspaces_dir, project_root, category, ext)
    local timestamp = os.date("!%Y%m%dT%H%M%SZ")
    local name = vim.fn.sha256(category .. "\n" .. timestamp):sub(1, 16)
    return fs.join(M.asset_dir(workspaces_dir, project_root, category), ("%s.%s"):format(name, ext))
end

---@param workspaces_dir string
---@param project_root string
---@param category Clodex.PromptCategory
---@return string?
function M.save_clipboard_image(workspaces_dir, project_root, category)
    local image_path = M.asset_path(workspaces_dir, project_root, category, "png")
    if not clipboard.save_image(image_path) then
        notify.warn("No PNG image found in the clipboard")
        return nil
    end
    return image_path
end

return M
