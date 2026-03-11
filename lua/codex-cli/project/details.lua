local fs = require("codex-cli.util.fs")
local git = require("codex-cli.util.git")

--- Defines the CodexCli.ProjectDetails.LanguageStat type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.ProjectDetails.LanguageStat
---@field name string
---@field files integer
---@field percent integer

--- Defines the CodexCli.ProjectDetails.Snapshot type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.ProjectDetails.Snapshot
---@field file_count integer
---@field avg_lines_per_file? number
---@field remote_name? string
---@field last_codex_activity_at? integer
---@field last_file_modified_at? integer
---@field languages CodexCli.ProjectDetails.LanguageStat[]

--- Defines the CodexCli.ProjectDetails.Metadata type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.ProjectDetails.Metadata
---@field version integer
---@field last_codex_activity_at? integer

--- Defines the CodexCli.ProjectDetails type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.ProjectDetails
---@field config CodexCli.Config.Values
---@field cache table<string, { captured_at: integer, snapshot: CodexCli.ProjectDetails.Snapshot }>
local Details = {}
Details.__index = Details

local CACHE_TTL_SECONDS = 30
local METADATA_VERSION = 1
local METADATA_DIRNAME = "project-details"
local EXCLUDED_DIRS = {
  [".git"] = true,
  [".hg"] = true,
  [".svn"] = true,
  [".next"] = true,
  [".nuxt"] = true,
  [".turbo"] = true,
  [".yarn"] = true,
  [".idea"] = true,
  [".vscode"] = true,
  ["node_modules"] = true,
  ["dist"] = true,
  ["build"] = true,
  ["coverage"] = true,
  ["target"] = true,
  [".codex-cli"] = true,
}

local function metadata_path(config, project_root)
  local id = vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
  return fs.join(config.storage.workspaces_dir, METADATA_DIRNAME, id .. ".json")
end

local function read_metadata(config, project_root)
  local metadata = fs.read_json(metadata_path(config, project_root), { version = METADATA_VERSION })
  metadata.version = metadata.version or METADATA_VERSION
  return metadata
end

local function write_metadata(config, project_root, metadata)
  metadata.version = METADATA_VERSION
  fs.write_json(metadata_path(config, project_root), metadata)
end
local LANGUAGE_LABELS = {
  c = "c",
  cpp = "cpp",
  css = "css",
  dockerfile = "docker",
  gitcommit = "gitcommit",
  go = "go",
  html = "html",
  java = "java",
  javascript = "js",
  javascriptreact = "jsx",
  json = "json",
  jsonc = "jsonc",
  lua = "lua",
  make = "make",
  markdown = "md",
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

---@param config CodexCli.Config.Values
---@return CodexCli.ProjectDetails
function Details.new(config)
  local self = setmetatable({}, Details)
  self.config = config
  self.cache = {}
  return self
end

---@param config CodexCli.Config.Values
function Details:update_config(config)
  self.config = config
end

--- Records the latest Codex interaction timestamp for a project.
---@param project CodexCli.Project
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
---@return string[]
local function list_files(root)
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
      end
    end
  end
  return files
end

---@param path string
---@return integer?, boolean
local function line_count_for_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, false
  end

  local content = file:read("*a")
  file:close()
  if not content or content == "" then
    return 0, true
  end
  if content:find("\0", 1, true) then
    return nil, false
  end

  local line_count = 0
  for _ in (content .. "\n"):gmatch("([^\n]*)\n") do
    line_count = line_count + 1
  end
  return line_count, true
end

---@param project CodexCli.Project
---@return CodexCli.ProjectDetails.Snapshot
function Details:compute(project)
  local files = list_files(project.root)
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
      local language = filetype and filetype ~= "" and (LANGUAGE_LABELS[filetype] or filetype) or nil
      if language then
        language_totals[language] = (language_totals[language] or 0) + 1
        language_file_count = language_file_count + 1
      end

      local line_count, is_text = line_count_for_file(path)
      if is_text and line_count ~= nil and language then
        line_total = line_total + line_count
        line_file_count = line_file_count + 1
      end
    end
  end

  local languages = {} ---@type CodexCli.ProjectDetails.LanguageStat[]
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

---@param project CodexCli.Project
---@return CodexCli.ProjectDetails.Snapshot
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
