local fs = require("clodex.util.fs")
local git = require("clodex.util.git")
local LanguageProfile = require("clodex.project.language")

local language_profile = LanguageProfile.new()

--- Defines the Clodex.ProjectDetails.LanguageStat type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectDetails.LanguageStat
---@field name string
---@field files integer
---@field percent integer

--- Defines the Clodex.ProjectDetails.Snapshot type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectDetails.Snapshot
---@field file_count integer
---@field avg_lines_per_file? number
---@field remote_name? string
---@field last_file_modified_at? integer
---@field project_icon? string
---@field languages Clodex.ProjectDetails.LanguageStat[]

--- Defines the Clodex.ProjectDetails.Metadata type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectDetails.Metadata
---@field version integer
---@field captured_at? integer
---@field snapshot? Clodex.ProjectDetails.Snapshot

--- Defines the Clodex.ProjectDetails type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectDetails
---@field config Clodex.Config.Values
---@field cache table<string, { captured_at: integer, snapshot: Clodex.ProjectDetails.Snapshot }>
local Details = {}
Details.__index = Details

local CACHE_TTL_SECONDS = 300
local METADATA_VERSION = 1
local METADATA_DIRNAME = "project-details"
local MAX_SCANNED_FILES = 5000
local MAX_COUNTED_FILE_BYTES = 1024 * 1024
local EXCLUDED_DIRS = {
  [".git"] = true,
  [".hg"] = true,
  [".svn"] = true,
  [".cache"] = true,
  [".direnv"] = true,
  [".next"] = true,
  [".nuxt"] = true,
  [".pytest_cache"] = true,
  [".state"] = true,
  [".turbo"] = true,
  [".venv"] = true,
  [".yarn"] = true,
  [".idea"] = true,
  [".mypy_cache"] = true,
  [".vscode"] = true,
  ["node_modules"] = true,
  ["dist"] = true,
  ["build"] = true,
  ["coverage"] = true,
  ["target"] = true,
  [".clodex"] = true,
}

local IGNORE_FILES = {
  ".gitignore",
  ".codexignore",
  ".agentignore",
  ".opencodeignore",
}

---@param root string
---@return string[]
local function load_ignore_patterns(root)
  local patterns = {}
  for _, filename in ipairs(IGNORE_FILES) do
    local path = fs.join(root, filename)
    local file = io.open(path, "r")
    if file then
      for line in file:lines() do
        line = vim.trim(line)
        if line ~= "" and not line:match("^#") then
          patterns[#patterns + 1] = line
        end
      end
      file:close()
    end
  end
  return patterns
end

---@param path string
---@param root string
---@param patterns string[]
---@return boolean
local function is_ignored(path, root, patterns)
  if #patterns == 0 then
    return false
  end
  local rel_path = path:sub(#root + 2)
  for _, pattern in ipairs(patterns) do
    if pattern:match("/$") then
      if rel_path:match("^" .. pattern:sub(1, -2)) or rel_path:match("/" .. pattern:sub(1, -2) .. "/") then
        return true
      end
    elseif pattern:match("^%*") then
      if rel_path:match(pattern:sub(2) .. "$") or rel_path:match("/" .. pattern:sub(2) .. "$") then
        return true
      end
    elseif pattern:match("^%*%.") then
      if rel_path:match("%." .. pattern:sub(3) .. "$") then
        return true
      end
    else
      if rel_path == pattern or rel_path:match("^" .. pattern .. "/") or rel_path:match("/" .. pattern .. "$") or rel_path:match("/" .. pattern .. "/") then
        return true
      end
    end
  end
  return false
end

local function metadata_dir()
  return fs.join(vim.fn.stdpath("data"), "clodex", METADATA_DIRNAME)
end

local function metadata_path(config, project_root)
  local id = vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
  return fs.join(metadata_dir(), id .. ".json")
end

local function read_metadata(config, project_root)
  local path = metadata_path(config, project_root)
  local metadata = fs.read_json(path, nil)
  if type(metadata) ~= "table" then
    local legacy_path = fs.join(vim.fn.stdpath("data"), "clodex", "workspaces", METADATA_DIRNAME, vim.fn.sha256(fs.normalize(project_root)):sub(1, 16) .. ".json")
    metadata = fs.read_json(legacy_path, { version = METADATA_VERSION })
    if fs.is_file(legacy_path) then
      fs.write_json(path, metadata)
      fs.remove(legacy_path)
    end
  end
  metadata.version = metadata.version or METADATA_VERSION
  return metadata
end

local function write_metadata(config, project_root, metadata)
  metadata.version = METADATA_VERSION
  fs.write_json(metadata_path(config, project_root), metadata)
end

---@param snapshot Clodex.ProjectDetails.Snapshot?
---@return Clodex.ProjectDetails.Snapshot?
local function normalize_snapshot(snapshot)
  if type(snapshot) ~= "table" then
    return nil
  end

    return {
      file_count = tonumber(snapshot.file_count) or 0,
      avg_lines_per_file = tonumber(snapshot.avg_lines_per_file) or nil,
      remote_name = type(snapshot.remote_name) == "string" and snapshot.remote_name or nil,
      last_file_modified_at = tonumber(snapshot.last_file_modified_at) or nil,
      project_icon = type(snapshot.project_icon) == "string" and vim.trim(snapshot.project_icon) ~= ""
        and snapshot.project_icon or nil,
      languages = type(snapshot.languages) == "table" and vim.deepcopy(snapshot.languages) or {},
    }
end

---@param self Clodex.ProjectDetails
---@param project Clodex.Project
---@return Clodex.ProjectDetails.Metadata, Clodex.ProjectDetails.Snapshot?
local function load_metadata_snapshot(self, project)
  local metadata = read_metadata(self.config, project.root)
  return metadata, normalize_snapshot(metadata.snapshot)
end

---@param self Clodex.ProjectDetails
---@param project_root string
---@param snapshot Clodex.ProjectDetails.Snapshot
---@param captured_at? integer
local function cache_snapshot(self, project_root, snapshot, captured_at)
  self.cache[project_root] = {
    captured_at = captured_at or os.time(),
    snapshot = normalize_snapshot(snapshot) or snapshot,
  }
end
---@param config Clodex.Config.Values
---@return Clodex.ProjectDetails
function Details.new(config)
  local self = setmetatable({}, Details)
  self.config = config
  self.cache = {}
  return self
end

---@param config Clodex.Config.Values
function Details:update_config(config)
  self.config = config
end

---@param project Clodex.Project
---@return Clodex.ProjectDetails.Snapshot?
function Details:get_cached(project)
  local cached = self.cache[project.root]
  if cached then
    return vim.deepcopy(cached.snapshot)
  end

  local metadata = read_metadata(self.config, project.root)
  local snapshot = normalize_snapshot(metadata.snapshot)
  if not snapshot then
    return nil
  end

  cache_snapshot(self, project.root, snapshot, metadata.captured_at)
  return vim.deepcopy(snapshot)
end

---@param project Clodex.Project
---@param timestamp? integer
function Details:touch_activity(project, timestamp)
  return project, timestamp
end

---@param project Clodex.Project
---@return string?
function Details:get_icon(project)
  local snapshot = self:get_cached(project)
  return snapshot and snapshot.project_icon or nil
end

---@param project Clodex.Project
---@param icon? string
function Details:set_icon(project, icon)
  local metadata, snapshot = load_metadata_snapshot(self, project)
  snapshot = snapshot or self:compute(project)
  icon = type(icon) == "string" and vim.trim(icon) or ""
  snapshot.project_icon = icon ~= "" and icon or nil
  metadata.captured_at = os.time()
  metadata.snapshot = vim.deepcopy(snapshot)
  write_metadata(self.config, project.root, metadata)
  cache_snapshot(self, project.root, snapshot, metadata.captured_at)
end

--- Removes a project details item and normalizes dependent state.
--- This cleanup keeps persistence and session state consistent with user actions.
---@param project_root string
function Details:delete(project_root)
  project_root = fs.normalize(project_root)
  self.cache[project_root] = nil
  fs.remove(metadata_path(self.config, project_root))
end

--- Walks the project tree while skipping known heavy/generated directories and ignored files.
---@param root string
---@param max_files integer
---@return string[]
local function list_files(root, max_files)
  local files = {} ---@type string[]
  local stack = { root }
  local ignore_patterns = load_ignore_patterns(root)
  while #stack > 0 do
    local dir = table.remove(stack)
    for name, entry_type in vim.fs.dir(dir) do
      local path = fs.join(dir, name)
      if entry_type == "directory" then
        if not EXCLUDED_DIRS[name] and not is_ignored(path, root, ignore_patterns) then
          stack[#stack + 1] = path
        end
      elseif entry_type == "file" then
        if not is_ignored(path, root, ignore_patterns) then
          files[#files + 1] = path
          if #files >= max_files then
            return files
          end
        end
      end
    end
  end
  return files
end

---@param path string
---@param stat Clodex.FsStat?
---@return integer?, boolean
local function line_count_for_file(path, stat)
  if stat and stat.size and stat.size > MAX_COUNTED_FILE_BYTES then
    return nil, false
  end

  local file = io.open(path, "r")
  if not file then
    return nil, false
  end

  local first_chunk = file:read(4096)
  if first_chunk == nil then
    file:close()
    return 0, true
  end
  if first_chunk:find("\0", 1, true) then
    file:close()
    return nil, false
  end

  file:seek("set", 0)

  local line_count = 0
  for line in file:lines() do
    if line:find("\0", 1, true) then
      file:close()
      return nil, false
    end
    line_count = line_count + 1
  end
  file:close()
  return line_count, true
end

---@param project Clodex.Project
---@return Clodex.ProjectDetails.Snapshot
function Details:compute(project)
  local files = list_files(project.root, MAX_SCANNED_FILES)
  local file_count = 0
  local language_totals = {} ---@type table<string, integer>
  local line_total = 0
  local line_file_count = 0
  local last_file_modified_at ---@type integer?

  for _, path in ipairs(files) do
    local stat = fs.stat(path)
    if stat and stat.type == "file" then
      file_count = file_count + 1
      if stat.mtime and stat.mtime.sec then
        local mtime = stat.mtime.sec
        if not last_file_modified_at or mtime > last_file_modified_at then
          last_file_modified_at = mtime
        end
      end

      local language = language_profile:language_for_path(path)
      if language then
        language_totals[language] = (language_totals[language] or 0) + 1
      end

      local line_count, is_text = line_count_for_file(path, stat)
      if is_text and line_count ~= nil then
        line_total = line_total + line_count
        line_file_count = line_file_count + 1
      end
    end
  end

  local languages = language_profile:dominant_languages(language_totals)

  return {
    file_count = file_count,
    avg_lines_per_file = line_file_count > 0 and (line_total / line_file_count) or nil,
    remote_name = git.remote_name(project.root),
    last_file_modified_at = last_file_modified_at,
    languages = languages,
  }
end

---@param project Clodex.Project
---@return Clodex.ProjectDetails.Snapshot
function Details:get(project)
  local cached = self.cache[project.root]
  local now = os.time()
  if cached and (now - cached.captured_at) < CACHE_TTL_SECONDS then
    return vim.deepcopy(cached.snapshot)
  end

  local metadata, existing = load_metadata_snapshot(self, project)
  local snapshot = self:compute(project)
  snapshot.project_icon = existing and existing.project_icon or nil
  metadata.captured_at = now
  metadata.snapshot = vim.deepcopy(snapshot)
  write_metadata(self.config, project.root, metadata)
  cache_snapshot(self, project.root, snapshot, now)
  return vim.deepcopy(snapshot)
end

return Details
