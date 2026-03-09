local fs = require("codex-cli.util.fs")
local git = require("codex-cli.util.git")

---@class CodexCli.ProjectDetector
---@field registry CodexCli.ProjectRegistry
local Detector = {}
Detector.__index = Detector

---@param registry CodexCli.ProjectRegistry
---@return CodexCli.ProjectDetector
function Detector.new(registry)
  local self = setmetatable({}, Detector)
  self.registry = registry
  return self
end

---@param buf? number
---@return string
function Detector:current_path(buf)
  return fs.current_path(buf)
end

---@param path? string
---@return string
function Detector:cwd_for_path(path)
  return fs.cwd_for_path(path or self:current_path())
end

---@param path? string
---@return CodexCli.Project?
function Detector:project_for_path(path)
  return self.registry:find_for_path(path or self:current_path())
end

---@param path? string
---@return string?
function Detector:git_candidate(path)
  local root = git.get_root(path or self:current_path())
  if root and not self.registry:has_root(root) then
    return root
  end
end

return Detector
