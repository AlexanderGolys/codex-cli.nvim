local fs = require("codex-cli.util.fs")
local git = require("codex-cli.util.git")

--- Defines the CodexCli.ProjectDetector type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.ProjectDetector
---@field registry CodexCli.ProjectRegistry
local Detector = {}
Detector.__index = Detector

--- Creates a new project detector instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param registry CodexCli.ProjectRegistry
---@return CodexCli.ProjectDetector
function Detector.new(registry)
  local self = setmetatable({}, Detector)
  self.registry = registry
  return self
end

--- Implements the current_path path for project detector.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param buf? number
---@return string
function Detector:current_path(buf)
  return fs.current_path(buf)
end

--- Implements the cwd_for_path path for project detector.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param path? string
---@return string
function Detector:cwd_for_path(path)
  return fs.cwd_for_path(path or self:current_path())
end

--- Implements the project_for_path path for project detector.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param path? string
---@return CodexCli.Project?
function Detector:project_for_path(path)
  return self.registry:find_for_path(path or self:current_path())
end

--- Implements the git_candidate path for project detector.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param path? string
---@return string?
function Detector:git_candidate(path)
  local root = git.get_root(path or self:current_path())
  if root and not self.registry:has_root(root) then
    return root
  end
end

return Detector
