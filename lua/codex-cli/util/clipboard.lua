local fs = require("codex-cli.util.fs")

local M = {}

--- Writes captured image bytes into a file when image content exists.
---@param path string
---@param data string
local function write_image(path, data)
  if not data or data == "" then
    return false
  end
  fs.write_file(path, data)
  return true
end

--- Runs a command with raw binary output and returns the completed result.
---@param cmd string[]
---@return vim.SystemCompleted
local function run(cmd)
  return vim.system(cmd, { text = false }):wait()
end

--- Reads image data from a supported clipboard command and returns bytes plus mime.
---@return string?, string?
function M.read_image()
  if vim.fn.executable("wl-paste") == 1 then
    local types = vim.system({ "wl-paste", "--list-types" }, { text = true }):wait()
    local output = types.stdout or ""
    if output:find("image/png", 1, true) then
      local result = run({ "wl-paste", "--no-newline", "--type", "image/png" })
      if result.code == 0 and result.stdout and result.stdout ~= "" then
        return result.stdout, "png"
      end
    end
  end

  if vim.fn.executable("xclip") == 1 then
    local targets = vim.system({ "xclip", "-selection", "clipboard", "-t", "TARGETS", "-o" }, { text = true }):wait()
    local output = targets.stdout or ""
    if output:find("image/png", 1, true) then
      local result = run({ "xclip", "-selection", "clipboard", "-t", "image/png", "-o" })
      if result.code == 0 and result.stdout and result.stdout ~= "" then
        return result.stdout, "png"
      end
    end
  end

  if vim.fn.executable("pngpaste") == 1 then
    local temp_path = fs.join(vim.fn.stdpath("cache"), "codex-cli", "clipboard.png")
    fs.ensure_dir(fs.dirname(temp_path))
    local result = vim.system({ "pngpaste", temp_path }, { text = true }):wait()
    if result.code == 0 and fs.is_file(temp_path) then
      local file = io.open(temp_path, "rb")
      if file then
        local data = file:read("*a")
        file:close()
        fs.remove(temp_path)
        if data and data ~= "" then
          return data, "png"
        end
      end
    end
  end
end

--- Saves the current clipboard image to `path` when available and returns success.
---@param path string
---@return boolean
function M.save_image(path)
  local data = M.read_image()
  return data ~= nil and write_image(path, data)
end

return M
