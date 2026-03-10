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

--- Creates a new project details instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param config CodexCli.Config.Values
---@return CodexCli.ProjectDetails
function Details.new(config)
  local self = setmetatable({}, Details)
  self.config = config
  self.cache = {}
  return self
end

--- Implements the update_config path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param config CodexCli.Config.Values
function Details:update_config(config)
  self.config = config
end

--- Implements the project_id path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project_root string
---@return string
function Details:project_id(project_root)
  return vim.fn.sha256(fs.normalize(project_root)):sub(1, 16)
end

--- Implements the metadata_path path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project_root string
---@return string
function Details:metadata_path(project_root)
  return fs.join(self.config.storage.workspaces_dir, "project-details", self:project_id(project_root) .. ".json")
end

--- Implements the read_metadata path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project_root string
---@return CodexCli.ProjectDetails.Metadata
function Details:read_metadata(project_root)
  local metadata = fs.read_json(self:metadata_path(project_root), { version = METADATA_VERSION })
  metadata.version = metadata.version or METADATA_VERSION
  return metadata
end

--- Implements the write_metadata path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project_root string
---@param metadata CodexCli.ProjectDetails.Metadata
function Details:write_metadata(project_root, metadata)
  metadata.version = METADATA_VERSION
  fs.write_json(self:metadata_path(project_root), metadata)
end

--- Records the latest Codex interaction timestamp for a project.
---@param project CodexCli.Project
---@param timestamp? integer
function Details:touch_activity(project, timestamp)
  local project_root = project.root
  local metadata = self:read_metadata(project_root)
  metadata.last_codex_activity_at = timestamp or os.time()
  self:write_metadata(project_root, metadata)

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
  fs.remove(self:metadata_path(project_root))
end

--- Implements the detect_filetype path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param path string
---@return string?
local function detect_filetype(path)
  local ft = vim.filetype.match({ filename = path })
  if not ft or ft == "" then
    return
  end
  return ft
end

--- Implements the language_name path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param filetype string?
---@return string?
local function language_name(filetype)
  if not filetype then
    return
  end
  return LANGUAGE_LABELS[filetype] or filetype
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
        local excluded = false
        for excluded_name in pairs(EXCLUDED_DIRS) do
          if path:find("/" .. excluded_name .. "/", 1, true) then
            excluded = true
            break
          end
        end
        if not excluded then
          files[#files + 1] = path
        end
      end
    end
  end
  return files
end

--- Implements the line_count_for_file path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

--- Implements the compute path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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

      local filetype = detect_filetype(path)
      local language = language_name(filetype)
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

  local metadata = self:read_metadata(project.root)
  return {
    file_count = file_count,
    avg_lines_per_file = line_file_count > 0 and (line_total / line_file_count) or nil,
    remote_name = git.remote_name(project.root),
    last_codex_activity_at = metadata.last_codex_activity_at,
    last_file_modified_at = last_file_modified_at,
    languages = languages,
  }
end

--- Implements the get path for project details.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
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
