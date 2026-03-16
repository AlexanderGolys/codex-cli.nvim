--- Defines the Clodex.Extmark.Coord type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.Extmark.Coord [integer, integer] # 0-based { row, col }, matching nvim_buf_set_extmark().

--- Defines the Clodex.Extmark type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.Extmark
---@field start_pos Clodex.Extmark.Coord # Inclusive start position, matching nvim_buf_set_extmark().
---@field end_pos Clodex.Extmark.Coord # Exclusive end position, matching nvim_buf_set_extmark().
---@field hl_group? string
---@field priority? integer
---@field opts vim.api.keyset.set_extmark
local Extmark = {}
Extmark.__index = Extmark

local DEFAULT_OPTS = {
  strict = false,
}

---@param start_pos Clodex.Extmark.Coord
---@param end_pos Clodex.Extmark.Coord
---@param hl_group? string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return Clodex.Extmark
function Extmark.new(start_pos, end_pos, hl_group, priority, opts)
  local self = setmetatable({}, Extmark)
  self.start_pos = { start_pos[1], start_pos[2] }
  self.end_pos = { end_pos[1], end_pos[2] }
  self.hl_group = hl_group
  self.priority = priority
  self.opts = vim.tbl_extend("force", vim.deepcopy(DEFAULT_OPTS), opts or {})
  return self
end

---@param row integer
---@param col integer
---@return Clodex.Extmark.Coord
function Extmark.coord(row, col)
  return { row, col }
end

---@param row integer
---@param start_col integer
---@param end_col integer
---@param hl_group string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return Clodex.Extmark
function Extmark.inline(row, start_col, end_col, hl_group, priority, opts)
  return Extmark.new(Extmark.coord(row, start_col), Extmark.coord(row, end_col), hl_group, priority, opts)
end

---@param row integer
---@param hl_group string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return Clodex.Extmark
function Extmark.line(row, hl_group, priority, opts)
  local line_opts = vim.tbl_extend("force", {
    hl_eol = true,
    line_hl_group = hl_group,
  }, opts or {})
  return Extmark.new(Extmark.coord(row, 0), Extmark.coord(row, 0), nil, priority, line_opts)
end

---@param start_row integer
---@param end_row integer
---@param hl_group string
---@param priority? integer
---@param opts? vim.api.keyset.set_extmark
---@return Clodex.Extmark[]
function Extmark.block(start_row, end_row, hl_group, priority, opts)
  local marks = {} ---@type Clodex.Extmark[]
  for row = start_row, end_row - 1 do
    marks[#marks + 1] = Extmark.line(row, hl_group, priority, opts)
  end
  return marks
end

---@param row_offset integer
---@return Clodex.Extmark
function Extmark:shifted(row_offset)
  return Extmark.new(
    Extmark.coord(self.start_pos[1] + row_offset, self.start_pos[2]),
    Extmark.coord(self.end_pos[1] + row_offset, self.end_pos[2]),
    self.hl_group,
    self.priority,
    vim.deepcopy(self.opts)
  )
end

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

---@param buf integer
---@param ns integer
function Extmark:place(buf, ns)
  vim.api.nvim_buf_set_extmark(buf, ns, self.start_pos[1], self.start_pos[2], self:to_opts())
end

return Extmark
