local fs = require("clodex.util.fs")
local git = require("clodex.util.git")

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
---@field last_codex_activity_at? integer
---@field last_file_modified_at? integer
---@field languages Clodex.ProjectDetails.LanguageStat[]

--- Defines the Clodex.ProjectDetails.Metadata type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.ProjectDetails.Metadata
---@field version integer
---@field last_codex_activity_at? integer

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
local DOMINANT_LANGUAGE_COVERAGE_PERCENT = 85
local DOMINANT_LANGUAGE_MIN_PERCENT = 10
local OTHER_LANGUAGE_NAME = "other"
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
local PROJECT_LANGUAGE_FILETYPES = {
  c = "c",
  cpp = "cpp",
  css = "css",
  dockerfile = "docker",
  go = "go",
  html = "html",
  java = "java",
  javascript = "js",
  javascriptreact = "jsx",
  json = "json",
  jsonc = "jsonc",
  lua = "lua",
  make = "make",
  python = "py",
  ruby = "rb",
  rust = "rs",
  sh = "sh",
  sql = "sql",
  toml = "toml",
  typescript = "ts",
  typescriptreact = "tsx",
  vim = "vim",
  xml = "xml",
  yaml = "yaml",
}

---@param filetype? string
---@return string?
local function project_language(filetype)
  if not filetype or filetype == "" then
    return nil
  end
  return PROJECT_LANGUAGE_FILETYPES[filetype]
end

---@param language_totals table<string, integer>
---@param language_file_count integer
---@return Clodex.ProjectDetails.LanguageStat[]
local function dominant_languages(language_totals, language_file_count)
  local languages = {} ---@type Clodex.ProjectDetails.LanguageStat[]
  for name, count in pairs(language_totals) do
    languages[#languages + 1] = {
      name = name,
      files = count,
      percent = language_file_count > 0 and math.floor((count * 100 / language_file_count) + 0.5) or 0,
    }
  end

  table.sort(languages, function(left, right)
    if left.files ~= right.files then
      return left.files > right.files
    end
    return left.name < right.name
  end)

  if #languages <= 1 then
    return languages
  end

  local dominant = {} ---@type Clodex.ProjectDetails.LanguageStat[]
  local omitted_files = 0
  local omitted_percent = 0
  local coverage = 0
  for index, language in ipairs(languages) do
    if index > 1
      and language.percent < DOMINANT_LANGUAGE_MIN_PERCENT
      and coverage >= DOMINANT_LANGUAGE_COVERAGE_PERCENT
    then
      omitted_files = omitted_files + language.files
      omitted_percent = omitted_percent + language.percent
    else
      dominant[#dominant + 1] = language
      coverage = coverage + language.percent
    end
  end

  if omitted_files > 0 and omitted_percent > 0 then
    dominant[#dominant + 1] = {
      name = OTHER_LANGUAGE_NAME,
      files = omitted_files,
      percent = omitted_percent,
    }
  end

  return dominant
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
  if not cached then
    return nil
  end
  return vim.deepcopy(cached.snapshot)
end

--- Records the latest Codex interaction timestamp for a project.
---@param project Clodex.Project
---@param timestamp? integer
function Details:touch_activity(project, timestamp)
  local project_root = project.root
  local metadata = read_metadata(self.config, project_root)
  metadata.last_codex_activity_at = timestamp or os.time()
  write_metadata(self.config, project_root, metadata)

  local cached = self.cache[project_root]
  if cached then
    cached.snapshot.last_codex_activity_at = metadata.last_codex_activity_at
  end
end

--- Removes a project details item and normalizes dependent state.
--- This cleanup keeps persistence and session state consistent with user actions.
---@param project_root string
function Details:delete(project_root)
  project_root = fs.normalize(project_root)
  self.cache[project_root] = nil
  fs.remove(metadata_path(self.config, project_root))
end

--- Walks the project tree while skipping known heavy/generated directories.
---@param root string
---@param max_files integer
---@return string[]
local function list_files(root, max_files)
  local files = {} ---@type string[]
  local stack = { root }
  while #stack > 0 do
    local dir = table.remove(stack)
    for name, entry_type in vim.fs.dir(dir) do
      local path = fs.join(dir, name)
      if entry_type == "directory" then
        if not EXCLUDED_DIRS[name] then
          stack[#stack + 1] = path
        end
      elseif entry_type == "file" then
        files[#files + 1] = path
        if #files >= max_files then
          return files
        end
      end
    end
  end
  return files
end

---@param path string
---@param stat uv.aliases.fs_stat_table?
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
  local language_file_count = 0
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

      local filetype = vim.filetype.match({ filename = path })
      local language = project_language(filetype)
      if language then
        language_totals[language] = (language_totals[language] or 0) + 1
        language_file_count = language_file_count + 1
      end

      local line_count, is_text = line_count_for_file(path, stat)
      if is_text and line_count ~= nil and language then
        line_total = line_total + line_count
        line_file_count = line_file_count + 1
      end
    end
  end

  local languages = dominant_languages(language_totals, language_file_count)

  local metadata = read_metadata(self.config, project.root)
  return {
    file_count = file_count,
    avg_lines_per_file = line_file_count > 0 and (line_total / line_file_count) or nil,
    remote_name = git.remote_name(project.root),
    last_codex_activity_at = metadata.last_codex_activity_at,
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

  local snapshot = self:compute(project)
  self.cache[project.root] = {
    captured_at = now,
    snapshot = snapshot,
  }
  return vim.deepcopy(snapshot)
end

return Details
