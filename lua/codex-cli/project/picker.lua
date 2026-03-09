local ui = require("codex-cli.ui.select")
local notify = require("codex-cli.util.notify")

---@class CodexCli.ProjectPicker.Item
---@field project? CodexCli.Project
---@field label string
---@field spacer? string
---@field preview? { text: string, ft?: string, loc?: boolean }
---@field preview_title? string

---@class CodexCli.ProjectPicker
---@field registry CodexCli.ProjectRegistry
local Picker = {}
Picker.__index = Picker

local highlights_ready = false

local function hl_fg(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl and hl.fg or nil
end

local function ensure_highlights()
  if highlights_ready then
    return
  end
  highlights_ready = true
  vim.api.nvim_set_hl(0, "CodexCliPickerProject", {
    fg = hl_fg("DiagnosticError") or hl_fg("ErrorMsg"),
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliPickerRoot", {
    fg = hl_fg("Directory"),
    italic = true,
    default = true,
  })
end

---@param registry CodexCli.ProjectRegistry
---@return CodexCli.ProjectPicker
function Picker.new(registry)
  local self = setmetatable({}, Picker)
  self.registry = registry
  return self
end

---@param project CodexCli.Project
---@param active_root? string
---@return string
function Picker:preview_text(project, active_root)
  local exists = vim.uv.fs_stat(project.root) ~= nil and "yes" or "no"
  local active = active_root and active_root == project.root and "yes" or "no"
  return table.concat({
    "# Codex Project",
    "",
    ("- Name: `%s`"):format(project.name),
    ("- Root: `%s`"):format(project.root),
    ("- Exists on disk: `%s`"):format(exists),
    ("- Active in this tab: `%s`"):format(active),
  }, "\n")
end

---@param item CodexCli.ProjectPicker.Item
---@param supports_chunks? boolean
---@return string|snacks.picker.Highlight[]
function Picker:format_item(item, supports_chunks)
  if not item.project then
    return item.label
  end
  if not supports_chunks then
    return item.label
  end
  ensure_highlights()
  return {
    { item.project.name, "CodexCliPickerProject" },
    { item.spacer or "  " },
    { item.project.root, "CodexCliPickerRoot" },
  }
end

---@param opts? {
---  include_none?: boolean,
---  prompt?: string,
---  active_root?: string,
---  on_delete?: fun(project: CodexCli.Project),
---  on_rename?: fun(project: CodexCli.Project),
---}
---@param on_choice fun(project?: CodexCli.Project)
function Picker:pick(opts, on_choice)
  opts = opts or {}
  local projects = self.registry:list()
  local items = {} ---@type CodexCli.ProjectPicker.Item[]
  local name_width = 0
  local snacks_opts = vim.tbl_deep_extend("force", {
    preview = "preview",
    layout = {
      preset = "select",
      hidden = {},
    },
  }, vim.deepcopy(opts.snacks or {}))
  local action_hints = {} ---@type string[]

  if opts.include_none then
    items[#items + 1] = {
      label = "No active project",
      preview = {
        text = "# Codex Project\n\n- Active project override is disabled for this tab.",
        ft = "markdown",
        loc = false,
      },
      preview_title = "No active project",
    }
  end

  for _, project in ipairs(projects) do
    name_width = math.max(name_width, vim.fn.strdisplaywidth(project.name))
  end

  for _, project in ipairs(projects) do
    local spacer = (" "):rep(math.max(name_width - vim.fn.strdisplaywidth(project.name), 0) + 2)
    items[#items + 1] = {
      project = project,
      label = project.name .. spacer .. project.root,
      spacer = spacer,
      preview = {
        text = self:preview_text(project, opts.active_root),
        ft = "markdown",
        loc = false,
      },
      preview_title = project.name,
    }
  end

  if #items == 0 then
    notify.warn("No Codex projects configured")
    return
  end

  if opts.on_delete then
    snacks_opts.actions = snacks_opts.actions or {}
    snacks_opts.actions.codex_project_delete = {
      desc = "Delete project",
      action = function(_, item)
        item = item and item.item or item
        if not item or not item.project then
          notify.warn("No project selected")
          return
        end
        opts.on_delete(item.project)
      end,
    }
    action_hints[#action_hints + 1] = "d: Delete project"

    snacks_opts.win = snacks_opts.win or {}
    snacks_opts.win.input = snacks_opts.win.input or {}
    snacks_opts.win.input.keys = snacks_opts.win.input.keys or {}
    snacks_opts.win.input.keys["d"] = { "codex_project_delete", mode = { "n", "i" } }

    snacks_opts.win.list = snacks_opts.win.list or {}
    snacks_opts.win.list.keys = snacks_opts.win.list.keys or {}
    snacks_opts.win.list.keys["d"] = { "codex_project_delete", mode = { "n", "i" } }
  end

  if opts.on_rename then
    snacks_opts.actions = snacks_opts.actions or {}
    snacks_opts.actions.codex_project_rename = {
      desc = "Rename project",
      action = function(_, item)
        item = item and item.item or item
        if not item or not item.project then
          notify.warn("No project selected")
          return
        end
        opts.on_rename(item.project)
      end,
    }
    action_hints[#action_hints + 1] = "r: Rename project"

    snacks_opts.win = snacks_opts.win or {}
    snacks_opts.win.input = snacks_opts.win.input or {}
    snacks_opts.win.input.keys = snacks_opts.win.input.keys or {}
    snacks_opts.win.input.keys["r"] = { "codex_project_rename", mode = { "n", "i" } }

    snacks_opts.win.list = snacks_opts.win.list or {}
    snacks_opts.win.list.keys = snacks_opts.win.list.keys or {}
    snacks_opts.win.list.keys["r"] = { "codex_project_rename", mode = { "n", "i" } }
  end

  if #action_hints > 0 then
    snacks_opts.help = snacks_opts.help or true
    notify.notify(("Project actions: %s"):format(table.concat(action_hints, ", ")))
  end

  ui.select(items, {
    prompt = opts.prompt or "Select Codex project",
    format_item = function(item, supports_chunks)
      return self:format_item(item, supports_chunks)
    end,
    snacks = snacks_opts,
  }, function(item)
    on_choice(item and item.project or nil)
  end)
end

---@param on_choice fun(project?: CodexCli.Project)
function Picker:pick_for_removal(on_choice)
  return self:pick({ prompt = "Remove Codex project" }, on_choice)
end

return Picker
