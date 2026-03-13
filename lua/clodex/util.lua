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

--- Generates an opaque RFC 4122 version 4 UUID string.
---@return string
function M.uuid_v4()
    local bytes = { string.byte(random_bytes(16), 1, 16) }
    bytes[7] = (bytes[7] % 16) + 64
    bytes[9] = (bytes[9] % 64) + 128

    return string.format(
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        table.unpack(bytes)
    )
end

return M
