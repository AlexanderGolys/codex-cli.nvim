local Extmark = require("codex-cli.ui.extmark")

--- Defines the CodexCli.TextBlock type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.TextBlock
---@field lines string[]
---@field extmarks CodexCli.Extmark[]
local TextBlock = {}
TextBlock.__index = TextBlock

---@param lines? string[]
---@param extmarks? CodexCli.Extmark[]
---@return CodexCli.TextBlock
function TextBlock.new(lines, extmarks)
  local self = setmetatable({}, TextBlock)
  self.lines = vim.deepcopy(lines or {})
  self.extmarks = {}
  if extmarks then
    self:add_extmarks(extmarks)
  end
  return self
end

---@return integer
function TextBlock:line_count()
  return #self.lines
end

--- Checks a empty condition for ui text block.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function TextBlock:is_empty()
  return #self.lines == 0
end

---@param text string
---@param extmarks? CodexCli.Extmark[]
---@return integer
function TextBlock:append_line(text, extmarks)
  local row_offset = #self.lines
  self.lines[#self.lines + 1] = text
  if extmarks then
    self:add_extmarks(extmarks, row_offset)
  end
  return row_offset
end

--- Adds a new ui text block entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param mark CodexCli.Extmark
---@param row_offset? integer
function TextBlock:add_extmark(mark, row_offset)
  self.extmarks[#self.extmarks + 1] = mark:shifted(row_offset or 0)
end

--- Adds a new ui text block entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param marks CodexCli.Extmark[]
---@param row_offset? integer
function TextBlock:add_extmarks(marks, row_offset)
  for _, mark in ipairs(marks) do
    self:add_extmark(mark, row_offset)
  end
end

---@param other CodexCli.TextBlock
---@return integer
function TextBlock:append_block(other)
  local row_offset = #self.lines
  vim.list_extend(self.lines, other.lines)
  self:add_extmarks(other.extmarks, row_offset)
  return row_offset
end

---@param buf integer
---@param ns integer
function TextBlock:render(buf, ns)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, self.lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(self.extmarks) do
    mark:place(buf, ns)
  end
end

return TextBlock
