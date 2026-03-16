local M = {}

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

return M
