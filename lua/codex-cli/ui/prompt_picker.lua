local Category = require("codex-cli.prompt.category")
local PromptHighlight = require("codex-cli.prompt.highlight")
local ui = require("codex-cli.ui.select")
local ui_win = require("codex-cli.ui.win")

local HIGHLIGHT_NS = vim.api.nvim_create_namespace("codex_cli_prompt_picker")

--- Stateful helper for the dual-pane prompt picker UI.
--- It manages project and category selection state and then returns the chosen pair.
---@class CodexCli.PromptPicker
---@field app CodexCli.App
---@field projects CodexCli.Project[]
---@field categories CodexCli.PromptCategoryDef[]
---@field focus "projects"|"categories"
---@field project_index integer
---@field category_index integer
local Picker = {}
Picker.__index = Picker

--- Constrains an index into a valid one-based range.
--- The UI uses this for cursor-safe project/category movement.
---@param index integer
---@param max_value integer
---@return integer
local function clamp(index, max_value)
  if max_value <= 0 then
    return 1
  end
  return math.min(math.max(index, 1), max_value)
end

---@param line integer
---@param count integer
---@return integer?
--- Maps a visible row number to a list index when count is nonzero.
--- Mouse handling and render navigation both rely on this translation.
---@param line integer
---@param count integer
---@return integer?
local function line_index(line, count)
  if count <= 0 then
    return nil
  end
  return clamp(line, count)
end

--- Creates a new ui prompt picker instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
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

--- Opens a picker path for ui prompt picker and handles the chosen result.
--- It is used by user-driven selection flows to continue the action pipeline with valid input.
---@param opts { project?: CodexCli.Project, require_project: boolean }
---@param on_choice fun(project: CodexCli.Project?, category: CodexCli.PromptCategoryDef?)
function Picker:pick(opts, on_choice)
  opts = opts or { require_project = false }
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
--- Implements the format_item path for ui prompt picker.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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
  --- Closes picker windows, protects against double close, then returns the chosen pair.
  --- This is the single exit point for confirming or cancelling the picker flow.
  local function close(project, category)
    if done then
      return
    end
    done = true
    ui_win.close(left_win)
    ui_win.close(right_win)
    on_choice(project, category)
  end

  --- Rebuilds both list panes, applies highlights, and refreshes cursor/focus state.
  --- Called on selection changes and whenever picker state is updated.
  local function render()
    local left_lines = {} ---@type string[]
    for _, project in ipairs(self.projects) do
      left_lines[#left_lines + 1] = project.name
    end
    vim.api.nvim_buf_clear_namespace(buf_left, HIGHLIGHT_NS, 0, -1)
    vim.bo[buf_left].modifiable = true
    vim.api.nvim_buf_set_lines(buf_left, 0, -1, false, #left_lines > 0 and left_lines or { "No projects configured" })
    vim.bo[buf_left].modifiable = false

    local right_lines = {} ---@type string[]
    local right_highlights = {} ---@type { row: integer, start_col: integer, end_col: integer, group: string }[]
    for index, category in ipairs(self.categories) do
      local line = ("%s  %s"):format(category.label, category.default_title)
      right_lines[#right_lines + 1] = line
      right_highlights[#right_highlights + 1] = {
        row = index - 1,
        start_col = 0,
        end_col = #category.label,
        group = PromptHighlight.title_group(category.id, "picker"),
      }
      right_highlights[#right_highlights + 1] = {
        row = index - 1,
        start_col = #category.label + 2,
        end_col = #line,
        group = PromptHighlight.preview_group(),
      }
    end
    vim.api.nvim_buf_clear_namespace(buf_right, HIGHLIGHT_NS, 0, -1)
    vim.bo[buf_right].modifiable = true
    vim.api.nvim_buf_set_lines(buf_right, 0, -1, false, right_lines)
    vim.bo[buf_right].modifiable = false
    for _, highlight in ipairs(right_highlights) do
      vim.api.nvim_buf_set_extmark(buf_right, HIGHLIGHT_NS, highlight.row, highlight.start_col, {
        end_row = highlight.row,
        end_col = highlight.end_col,
        hl_group = highlight.group,
      })
    end

    if vim.api.nvim_win_is_valid(left_win) then
      vim.api.nvim_win_set_cursor(left_win, { clamp(self.project_index, math.max(#self.projects, 1)), 0 })
      vim.wo[left_win].cursorline = self.focus == "projects"
      ui_win.set_focus_border(left_win, self.focus == "projects")
    end
    if vim.api.nvim_win_is_valid(right_win) then
      vim.api.nvim_win_set_cursor(right_win, { clamp(self.category_index, #self.categories), 0 })
      vim.wo[right_win].cursorline = self.focus == "categories"
      ui_win.set_focus_border(right_win, self.focus == "categories")
    end
  end

  --- Returns the currently highlighted project from in-memory picker state.
  --- Downstream prompt flows use this to auto-fill project context.
  local function selected_project()
    return self.projects[self.project_index]
  end

  --- Returns the currently highlighted prompt category from in-memory picker state.
  --- This value is passed through to completion handlers and queue creation.
  local function selected_category()
    return self.categories[self.category_index]
  end

  --- Moves the active selection by delta in the current pane.
  --- It keeps the selection bound to valid row indices and triggers rerender.
  local function move(delta)
    if self.focus == "projects" then
      self.project_index = clamp(self.project_index + delta, #self.projects)
    else
      self.category_index = clamp(self.category_index + delta, #self.categories)
    end
    render()
  end

  --- Registers a picker keymap on the given buffer using silent/nowsait defaults.
  --- Key mappings here keep behavior consistent across both left and right panes.
  local function map(buf, lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true })
  end

  --- Resolves a mouse click position to pane and row index.
  --- The returned tuple controls which pane gains focus and which selection updates.
  local function click_target()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == left_win then
      return "projects", line_index(mouse.line, #self.projects)
    end
    if mouse.winid == right_win then
      return "categories", line_index(mouse.line, #self.categories)
    end
    return nil, nil
  end

  --- Handles click selection for mouse interactions with optional confirmation.
  --- It supports single-click focus move and double-click immediate activation.
  local function select_from_click(confirm)
    local target, index = click_target()
    if not target or not index then
      return
    end

    self.focus = target
    if target == "projects" then
      self.project_index = index
      render()
      vim.api.nvim_set_current_win(left_win)
      if confirm then
        close(selected_project(), selected_category())
        return
      end
      self.focus = "categories"
      render()
      vim.api.nvim_set_current_win(right_win)
      return
    end

    self.category_index = index
    render()
    vim.api.nvim_set_current_win(right_win)
    if confirm or selected_project() then
      close(selected_project(), selected_category())
    end
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
    map(buf, "<LeftMouse>", function()
      select_from_click(false)
    end)
    map(buf, "<2-LeftMouse>", function()
      select_from_click(true)
    end)
  end

  render()
end

return Picker
