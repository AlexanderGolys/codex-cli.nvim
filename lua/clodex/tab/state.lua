---@class Clodex.TabState
---@field tabpage number
---@field active_project_root? string
---@field prompted_project? boolean
---@field window? snacks.win
---@field session_key? string
local State = {}
State.__index = State

---@class Clodex.TabState.Snapshot
---@field tabpage number
---@field active_project_root? string
---@field prompted_project? boolean
---@field has_visible_window boolean
---@field session_key? string
---@field window_id? integer

local ACTIVE_PROJECT_VAR = "clodex_active_project_root"

---@param tabpage integer
---@return string?
local function tab_project_root(tabpage)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then
    return nil
  end

  local ok, root = pcall(vim.api.nvim_tabpage_get_var, tabpage, ACTIVE_PROJECT_VAR)
  if ok and type(root) == "string" and root ~= "" then
    return root
  end
end

---@param tabpage integer
---@param root? string
local function set_tab_project_root(tabpage, root)
  if not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end

  root = type(root) == "string" and root ~= "" and root or nil
  if root then
    vim.api.nvim_tabpage_set_var(tabpage, ACTIVE_PROJECT_VAR, root)
    return
  end
  pcall(vim.api.nvim_tabpage_del_var, tabpage, ACTIVE_PROJECT_VAR)
end

---@param tabpage number
---@return Clodex.TabState
function State.new(tabpage)
  local self = setmetatable({}, State)
  self.tabpage = tabpage
  self.active_project_root = tab_project_root(tabpage)
  self.prompted_project = false
  return self
end

--- Checks a valid condition for tab state.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function State:is_valid()
  return vim.api.nvim_tabpage_is_valid(self.tabpage)
end

---@return boolean
function State:has_visible_window()
  return self.window ~= nil
    and self.window:win_valid()
    and vim.api.nvim_win_get_tabpage(self.window.win) == self.tabpage
end

---@param root? string
function State:set_active_project(root)
  self.active_project_root = root
  set_tab_project_root(self.tabpage, root)
end

--- Clears the active project assignment for this tab.
--- Used when users exit project-scoped context and return to free mode.
function State:clear_active_project()
  self.active_project_root = nil
  set_tab_project_root(self.tabpage, nil)
end

---@return boolean
function State:has_prompted_project()
  return self.prompted_project == true
end

--- Marks this tab as having prompted for project selection.
--- Prevents repeatedly asking the same question during buffer activity.
function State:mark_prompted_project()
  self.prompted_project = true
end

--- Restores tab state from serialized snapshot while dropping runtime window handles.
--- Window/buffer bindings are rebuilt by terminal manager when needed.
---@param snapshot { active_project_root?: string, prompted_project?: boolean, session_key?: string, has_visible_window?: boolean }
function State:restore(snapshot)
  self:set_active_project(snapshot.active_project_root)
  self.prompted_project = snapshot.prompted_project == true
  self.session_key = snapshot.has_visible_window and snapshot.session_key or nil
  self.window = nil
end

---@param window? snacks.win
---@param session_key? string
function State:set_window(window, session_key)
  self.window = window
  self.session_key = session_key
end

--- Clears tracked window and session key for this tab state.
--- This is used when hiding or destroying associated terminal windows.
function State:clear_window()
  self.window = nil
  self.session_key = nil
end

--- Hides the tracked window and then clears cached window/session references.
--- This keeps state consistent when tab windows are closed by user or redraw.
function State:hide_window()
  if self:has_visible_window() then
    self.window:hide()
  end
  self:clear_window()
end

--- Checks a showing condition for tab state.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@param session_key string
---@return boolean
function State:is_showing(session_key)
  return self:has_visible_window() and self.session_key == session_key
end

---@return Clodex.TabState.Snapshot
--- Captures a serializable snapshot for session persistence.
--- Persisted snapshots are used on reload to rebuild tab state and reopen active sessions.
function State:snapshot()
  local active_project_root = tab_project_root(self.tabpage) or self.active_project_root
  return {
    tabpage = self.tabpage,
    active_project_root = active_project_root,
    prompted_project = self.prompted_project == true,
    has_visible_window = self:has_visible_window(),
    session_key = self.session_key,
    window_id = self:has_visible_window() and self.window.win or nil,
  }
end

return State
