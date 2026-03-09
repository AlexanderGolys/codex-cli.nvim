local M = {}

---@generic T
---@param items T[]
---@param opts? vim.ui.select.Opts
---@param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
  local ok, picker = pcall(require, "snacks.picker.select")
  if ok then
    return picker.select(items, opts, on_choice)
  end
  return vim.ui.select(items, opts, on_choice)
end

---@param opts vim.ui.input.Opts
---@param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
  local ok, input = pcall(require, "snacks.input")
  if ok then
    return input(opts, on_confirm)
  end
  return vim.ui.input(opts, on_confirm)
end

---@param prompt string
---@param on_choice fun(confirmed: boolean)
function M.confirm(prompt, on_choice)
  local items = {
    { label = "Yes", value = true },
    { label = "No", value = false },
  }

  return M.select(items, {
    prompt = prompt,
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    on_choice(item and item.value or false)
  end)
end

return M
