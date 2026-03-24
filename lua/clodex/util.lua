local M = {}

local SWAPFILE_ERROR_CODE = "E325"

local random_seeded = false

local function ensure_random_seed()
    if random_seeded then
        return
    end
    random_seeded = true
    math.randomseed(os.time() + math.floor((vim.uv.hrtime() % 1000000) / 1000))
    math.random()
    math.random()
    math.random()
end

---@param count integer
---@return string
local function random_bytes(count)
    local uv = vim.uv or vim.loop
    if uv and uv.random then
        local ok, bytes = pcall(uv.random, count)
        if ok and type(bytes) == "string" and #bytes == count then
            return bytes
        end
    end

    ensure_random_seed()
    local chars = {} ---@type string[]
    for _ = 1, count do
        chars[#chars + 1] = string.char(math.random(0, 255))
    end
    return table.concat(chars)
end

local function compatibility_unpack(values, start_idx, end_idx)
    if table.unpack ~= nil then
        return table.unpack(values, start_idx, end_idx)
    end
    if unpack ~= nil then
        return unpack(values, start_idx, end_idx)
    end

    start_idx = start_idx or 1
    end_idx = end_idx or #values
    if end_idx < start_idx then
        return nil
    end

    local function unpack_recursive(index)
        if index > end_idx then
            return nil
        end
        return values[index], unpack_recursive(index + 1)
    end

    return unpack_recursive(start_idx)
end

--- Generates an opaque RFC 4122 version 4 UUID string.
---@return string
function M.uuid_v4()
    local bytes = { string.byte(random_bytes(16), 1, 16) }
    bytes[7] = (bytes[7] % 16) + 64
    bytes[9] = (bytes[9] % 64) + 128

    return string.format(
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        compatibility_unpack(bytes)
    )
end

---@param values string[]|number[]
---@param start_idx? integer
---@param end_idx? integer
---@return any
function M.unpack_values(values, start_idx, end_idx)
    return compatibility_unpack(values, start_idx, end_idx)
end

---@class Clodex.SafeEditResult
---@field ok boolean
---@field reason? "modified"|"swapfile"|"error"
---@field message? string

---@param path string
---@param opts? { current_buf?: integer }
---@return Clodex.SafeEditResult
function M.safe_edit(path, opts)
    opts = opts or {}
    local current_buf = opts.current_buf or vim.api.nvim_get_current_buf()
    local current_path = vim.api.nvim_buf_get_name(current_buf)
    local same_path = current_path ~= "" and vim.fs.normalize(current_path) == vim.fs.normalize(path)
    if vim.bo[current_buf].modified and not same_path then
        return {
            ok = false,
            reason = "modified",
            message = "Current buffer has unsaved changes; keeping it open instead of replacing it.",
        }
    end

    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if ok then
        return { ok = true }
    end

    local message = tostring(err or "")
    if message:find(SWAPFILE_ERROR_CODE, 1, true) then
        return {
            ok = false,
            reason = "swapfile",
            message = ("Swap file already exists for %s; keeping the current buffer unchanged."):format(path),
        }
    end

    return {
        ok = false,
        reason = "error",
        message = ("Failed to open %s\n%s"):format(path, message),
    }
end

return M
