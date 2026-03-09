local ui = require("codex-cli.ui.select")
local notify = require("codex-cli.util.notify")

---@class CodexCli.ProjectPicker
---@field registry CodexCli.ProjectRegistry
local Picker = {}
Picker.__index = Picker

---@param registry CodexCli.ProjectRegistry
---@return CodexCli.ProjectPicker
function Picker.new(registry)
  local self = setmetatable({}, Picker)
  self.registry = registry
  return self
end

---@param opts? { include_none?: boolean, prompt?: string }
---@param on_choice fun(project?: CodexCli.Project)
function Picker:pick(opts, on_choice)
  opts = opts or {}
  local items = {} ---@type {project?: CodexCli.Project, label: string}[]

  if opts.include_none then
    items[#items + 1] = {
      label = "No active project",
    }
  end

  for _, project in ipairs(self.registry:list()) do
    items[#items + 1] = {
      project = project,
      label = string.format("%s [%s]", project.name, project.root),
    }
  end

  if #items == 0 then
    notify.warn("No Codex projects configured")
    return
  end

  ui.select(items, {
    prompt = opts.prompt or "Select Codex project",
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    on_choice(item and item.project or nil)
  end)
end

---@param on_choice fun(project?: CodexCli.Project)
function Picker:pick_for_removal(on_choice)
  return self:pick({ prompt = "Remove Codex project" }, on_choice)
end

return Picker
