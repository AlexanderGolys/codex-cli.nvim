--- Defines the CodexCli.Extmark.Coord type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias CodexCli.Extmark.Coord [integer, integer] # 0-based { row, col }, matching nvim_buf_set_extmark().

--- Defines the CodexCli.Extmark type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.Extmark
---@field start_pos CodexCli.Extmark.Coord # Inclusive start position, matching nvim_buf_set_extmark().
---@field end_pos CodexCli.Extmark.Coord # Exclusive end position, matching nvim_buf_set_extmark().
---@field hl_group? string
---@field priority? integer
---@field opts vim.api.keyset.set_extmark
local Extmark = {}
Extmark.__index = Extmark

local DEFAULT_OPTS = {
  strict = false,
}

--- Creates a new ui extmark instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param start_pos CodexCli.Extmark.Coord
---@param end_pos CodexCli.Extmark.Coord
---@param hl_group? string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return CodexCli.Extmark
function Extmark.new(start_pos, end_pos, hl_group, priority, opts)
  local self = setmetatable({}, Extmark)
  self.start_pos = { start_pos[1], start_pos[2] }
  self.end_pos = { end_pos[1], end_pos[2] }
  self.hl_group = hl_group
  self.priority = priority
  self.opts = vim.tbl_extend("force", vim.deepcopy(DEFAULT_OPTS), opts or {})
  return self
end

--- Implements the coord path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param row integer
---@param col integer
---@return CodexCli.Extmark.Coord
function Extmark.coord(row, col)
  return { row, col }
end

--- Implements the inline path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param row integer
---@param start_col integer
---@param end_col integer
---@param hl_group string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return CodexCli.Extmark
function Extmark.inline(row, start_col, end_col, hl_group, priority, opts)
  return Extmark.new(Extmark.coord(row, start_col), Extmark.coord(row, end_col), hl_group, priority, opts)
end

--- Implements the line path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param row integer
---@param hl_group string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return CodexCli.Extmark
function Extmark.line(row, hl_group, priority, opts)
  local line_opts = vim.tbl_extend("force", {
    hl_eol = true,
    line_hl_group = hl_group,
  }, opts or {})
  return Extmark.new(Extmark.coord(row, 0), Extmark.coord(row + 1, 0), nil, priority, line_opts)
end

--- Implements the block path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param start_row integer
---@param end_row integer
---@param hl_group string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return CodexCli.Extmark[]
function Extmark.block(start_row, end_row, hl_group, priority, opts)
  local marks = {} ---@type CodexCli.Extmark[]
  for row = start_row, end_row - 1 do
    marks[#marks + 1] = Extmark.line(row, hl_group, priority, opts)
  end
  return marks
end

--- Implements the shifted path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param row_offset integer
---@return CodexCli.Extmark
function Extmark:shifted(row_offset)
  return Extmark.new(
    Extmark.coord(self.start_pos[1] + row_offset, self.start_pos[2]),
    Extmark.coord(self.end_pos[1] + row_offset, self.end_pos[2]),
    self.hl_group,
    self.priority,
    vim.deepcopy(self.opts)
  )
end

--- Implements the to_opts path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@return vim.api.keyset.set_extmark
function Extmark:to_opts()
  local opts = vim.deepcopy(self.opts)
  opts.end_row = self.end_pos[1]
  opts.end_col = self.end_pos[2]
  if self.hl_group then
    opts.hl_group = self.hl_group
  end
  if self.priority then
    opts.priority = self.priority
  end
  return opts
end

--- Implements the place path for ui extmark.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param buf integer
---@param ns integer
function Extmark:place(buf, ns)
  vim.api.nvim_buf_set_extmark(buf, ns, self.start_pos[1], self.start_pos[2], self:to_opts())
end

return Extmark
