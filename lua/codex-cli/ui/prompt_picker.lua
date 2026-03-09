local Category = require("codex-cli.prompt.category")
local ui = require("codex-cli.ui.select")
local ui_win = require("codex-cli.ui.win")

---@class CodexCli.PromptPicker
---@field app CodexCli.App
---@field projects CodexCli.Project[]
---@field categories CodexCli.PromptCategoryDef[]
---@field focus "projects"|"categories"
---@field project_index integer
---@field category_index integer
local Picker = {}
Picker.__index = Picker

local function clamp(index, max_value)
  if max_value <= 0 then
    return 1
  end
  return math.min(math.max(index, 1), max_value)
end

---@param name string
---@return integer?
local function hl_fg(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl and hl.fg or nil
end

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "CodexCliQueueActiveBorder", {
    fg = hl_fg("Identifier") or hl_fg("FloatBorder"),
    bold = true,
    default = true,
  })
  vim.api.nvim_set_hl(0, "CodexCliQueueInactiveBorder", {
    fg = hl_fg("Comment") or hl_fg("FloatBorder"),
    default = true,
  })
end

---@param app CodexCli.App
---@return CodexCli.PromptPicker
function Picker.new(app)
  local self = setmetatable({}, Picker)
  self.app = app
  self.projects = {}
  self.categories = Category.list()
  self.focus = "projects"
  self.project_index = 1
  self.category_index = 1
  return self
end

---@param opts { project?: CodexCli.Project, require_project: boolean }
---@param on_choice fun(project: CodexCli.Project?, category: CodexCli.PromptCategoryDef?)
function Picker:pick(opts, on_choice)
  opts = opts or { require_project = false }
  ensure_highlights()
  self.projects = self.app:projects_for_queue_workspace()
  self.categories = Category.list()
  self.focus = opts.require_project and "projects" or "categories"

  if opts.project then
    for index, project in ipairs(self.projects) do
      if project.root == opts.project.root then
        self.project_index = index
        break
      end
    end
  else
    self.project_index = 1
  end
  self.category_index = 1

  if not opts.require_project then
    local items = {} ---@type { label: string, category: CodexCli.PromptCategoryDef }[]
    for _, category in ipairs(self.categories) do
      items[#items + 1] = {
        label = category.label,
        category = category,
      }
    end
    ui.select(items, {
      prompt = "Prompt category",
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      on_choice(opts.project, item and item.category or nil)
    end)
    return
  end

  local buf_left = vim.api.nvim_create_buf(false, true)
  local buf_right = vim.api.nvim_create_buf(false, true)
  local ui = vim.api.nvim_list_uis()[1]
  local columns = ui and ui.width or vim.o.columns
  local lines = ui and ui.height or vim.o.lines
  local width = math.max(math.floor(columns * 0.7), 70)
  local height = math.max(math.floor(lines * 0.55), 12)
  local left_width = math.max(math.floor(width * 0.45), 28)
  local right_width = width - left_width - 1
  local row = math.max(math.floor((lines - height) / 2), 1)
  local col = math.max(math.floor((columns - width) / 2), 1)

  local left = ui_win.open({
    buf = buf_left,
    enter = true,
    row = row,
    col = col,
    width = left_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Projects ",
  })
  local right = ui_win.open({
    buf = buf_right,
    enter = false,
    row = row,
    col = col + left_width + 1,
    width = right_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Categories ",
  })
  local left_win = left.win
  local right_win = right.win

  local done = false
  local function close(project, category)
    if done then
      return
    end
    done = true
    if vim.api.nvim_win_is_valid(left_win) then
      pcall(vim.api.nvim_win_close, left_win, true)
    end
    if vim.api.nvim_win_is_valid(right_win) then
      pcall(vim.api.nvim_win_close, right_win, true)
    end
    on_choice(project, category)
  end

  local function render()
    local left_lines = {} ---@type string[]
    for _, project in ipairs(self.projects) do
      left_lines[#left_lines + 1] = project.name
    end
    vim.bo[buf_left].modifiable = true
    vim.api.nvim_buf_set_lines(buf_left, 0, -1, false, #left_lines > 0 and left_lines or { "No projects configured" })
    vim.bo[buf_left].modifiable = false

    local right_lines = {} ---@type string[]
    for _, category in ipairs(self.categories) do
      right_lines[#right_lines + 1] = ("%s  %s"):format(category.label, category.default_title)
    end
    vim.bo[buf_right].modifiable = true
    vim.api.nvim_buf_set_lines(buf_right, 0, -1, false, right_lines)
    vim.bo[buf_right].modifiable = false

    if vim.api.nvim_win_is_valid(left_win) then
      vim.api.nvim_win_set_cursor(left_win, { clamp(self.project_index, math.max(#self.projects, 1)), 0 })
      vim.wo[left_win].cursorline = self.focus == "projects"
      vim.wo[left_win].winhl = ("NormalFloat:NormalFloat,FloatBorder:%s"):format(
        self.focus == "projects" and "CodexCliQueueActiveBorder" or "CodexCliQueueInactiveBorder"
      )
    end
    if vim.api.nvim_win_is_valid(right_win) then
      vim.api.nvim_win_set_cursor(right_win, { clamp(self.category_index, #self.categories), 0 })
      vim.wo[right_win].cursorline = self.focus == "categories"
      vim.wo[right_win].winhl = ("NormalFloat:NormalFloat,FloatBorder:%s"):format(
        self.focus == "categories" and "CodexCliQueueActiveBorder" or "CodexCliQueueInactiveBorder"
      )
    end
  end

  local function selected_project()
    return self.projects[self.project_index]
  end

  local function selected_category()
    return self.categories[self.category_index]
  end

  local function move(delta)
    if self.focus == "projects" then
      self.project_index = clamp(self.project_index + delta, #self.projects)
    else
      self.category_index = clamp(self.category_index + delta, #self.categories)
    end
    render()
  end

  local function map(buf, lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true })
  end

  for _, buf in ipairs({ buf_left, buf_right }) do
    map(buf, "q", function() close(nil, nil) end)
    map(buf, "<Esc>", function() close(nil, nil) end)
    map(buf, "h", function() self.focus = "projects"; render(); vim.api.nvim_set_current_win(left_win) end)
    map(buf, "<Left>", function() self.focus = "projects"; render(); vim.api.nvim_set_current_win(left_win) end)
    map(buf, "l", function() self.focus = "categories"; render(); vim.api.nvim_set_current_win(right_win) end)
    map(buf, "<Right>", function() self.focus = "categories"; render(); vim.api.nvim_set_current_win(right_win) end)
    map(buf, "j", function() move(1) end)
    map(buf, "<Down>", function() move(1) end)
    map(buf, "k", function() move(-1) end)
    map(buf, "<Up>", function() move(-1) end)
    map(buf, "<CR>", function()
      close(selected_project(), selected_category())
    end)
  end

  render()
end

return Picker
