local PromptCategory = require("codex-cli.prompt.category")
local PromptComposer = require("codex-cli.prompt.composer")
local PromptLibrary = require("codex-cli.prompt.library")
local PromptTitle = require("codex-cli.prompt.title")
local clipboard = require("codex-cli.util.clipboard")
local fs = require("codex-cli.util.fs")
local notify = require("codex-cli.util.notify")
local ui = require("codex-cli.ui.select")

--- Defines the CodexCli.AppPromptActions.ResolveOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.AppPromptActions.ResolveOpts
---@field project? CodexCli.Project
---@field project_value? string

--- Defines the CodexCli.AppPromptActions.PickPromptOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.AppPromptActions.PickPromptOpts: CodexCli.AppPromptActions.ResolveOpts
---@field project_required? boolean
---@field category? CodexCli.PromptCategory

--- Defines the CodexCli.AppPromptActions.AddTodoSpec type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.AppPromptActions.AddTodoSpec
---@field title string
---@field details? string
---@field kind? CodexCli.PromptCategory
---@field image_path? string

--- Defines the CodexCli.AppPromptActions.ErrorSource type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.AppPromptActions.ErrorSource
---@field label string
---@field value "clipboard_screenshot"|"file_screenshot"|"message"|"summary"|"custom"

--- Defines the CodexCli.AppPromptActions type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class CodexCli.AppPromptActions
---@field app CodexCli.App
local PromptActions = {}
PromptActions.__index = PromptActions

--- Creates a new app prompt actions instance from this module.
--- It is used by callers to bootstrap module state before running higher-level plugin actions.
---@param app CodexCli.App
---@return CodexCli.AppPromptActions
function PromptActions.new(app)
  return setmetatable({ app = app }, PromptActions)
end

--- Implements the resolve_project path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param opts? CodexCli.AppPromptActions.ResolveOpts
---@return CodexCli.Project?
function PromptActions:resolve_project(opts)
  opts = opts or {}
  local project = opts.project
  if not project and opts.project_value then
    project = self.app.registry:find_by_name_or_root(opts.project_value)
  end
  if project then
    return project
  end

  local state = self.app:current_tab()
  local target = self.app:resolve_target(state)
  if target.kind == "project" then
    return target.project
  end
end

--- Opens a picker path for app prompt actions and handles the chosen result.
--- It is used by user-driven selection flows to continue the action pipeline with valid input.
---@param target_project CodexCli.Project?
---@param callback fun(project: CodexCli.Project)
function PromptActions:pick_project(target_project, callback)
  if target_project then
    callback(target_project)
    return
  end

  ui.pick_project(self.app.registry:list(), { prompt = "Select project" }, function(project)
    if project then
      callback(project)
    end
  end)
end

---@param project CodexCli.Project
---@param callback fun(project: CodexCli.Project, category: CodexCli.PromptCategory)
function PromptActions:pick_category(project, callback)
  local items = {} ---@type { label: string, category: CodexCli.PromptCategoryDef }[]
  for _, category in ipairs(Category.list()) do
    items[#items + 1] = {
      label = category.label,
      category = category,
    }
  end

  ui.select(items, {
    prompt = ("Prompt category for %s"):format(project.name),
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if item then
      callback(project, item.category.id)
    end
  end)
end

--- Implements the asset_dir path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param category CodexCli.PromptCategory
---@return string
function PromptActions:asset_dir(category)
  return fs.join(self.app.config:get().storage.workspaces_dir, "prompt-assets", category)
end

--- Implements the asset_path path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param category CodexCli.PromptCategory
---@param ext string
---@return string
function PromptActions:asset_path(category, ext)
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local name = vim.fn.sha256(category .. "\n" .. timestamp):sub(1, 16)
  return fs.join(self:asset_dir(category), ("%s.%s"):format(name, ext))
end

--- Implements the category path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param category CodexCli.PromptCategory
---@return CodexCli.PromptCategoryDef
function PromptActions:category(category)
  return PromptCategory.get(category)
end

--- Opens a picker path for app prompt actions and handles the chosen result.
--- It is used by user-driven selection flows to continue the action pipeline with valid input.
---@param opts? CodexCli.AppPromptActions.PickPromptOpts
---@param callback fun(project: CodexCli.Project, category: CodexCli.PromptCategory)
function PromptActions:pick_target(opts, callback)
  opts = opts or {}
  local project = self:resolve_project(opts)

  if project and opts.category then
    callback(project, opts.category)
    return
  end

  if not project then
    self:pick_project(nil, function(selected_project)
      if not selected_project then
        return
      end
      if opts.category then
        callback(selected_project, opts.category)
        return
      end
      self:pick_category(selected_project, callback)
    end)
    return
  end

  self:pick_category(project, callback)
end

--- Implements the prompt_for_todo path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function PromptActions:prompt_for_todo(project)
  ui.multiline_input({
    prompt = ("Todo prompt for %s"):format(project.name),
  }, function(body)
    local spec = body and PromptComposer.parse(body) or nil
    if not spec then
      return
    end
    self.app.queue_actions:add_project_todo(project, {
      title = spec.title,
      details = spec.details,
    })
  end)
end

--- Opens a multiline prompt composer for a category-specific todo.
--- The composed body is parsed back into queue title/details before persistence.
---@param project CodexCli.Project
---@param definition CodexCli.PromptCategoryDef
---@param category CodexCli.PromptCategory
---@param default_body? string
function PromptActions:compose_category_prompt(project, definition, category, default_body)
  ui.multiline_input({
    prompt = ("%s prompt for %s"):format(definition.label, project.name),
    default = default_body or definition.default_title,
  }, function(body)
    local spec = body and PromptComposer.parse(body) or nil
    if not spec then
      return
    end
    self.app.queue_actions:add_project_todo(project, {
      title = spec.title,
      details = spec.details,
      kind = category,
    })
  end)
end

--- Implements the prompt_for_category path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param category CodexCli.PromptCategory
function PromptActions:prompt_for_category(project, category)
  local definition = self:category(category)
  self:compose_category_prompt(project, definition, category)
end

--- Implements the prompt_for_visual path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function PromptActions:prompt_for_visual(project)
  ui.input({
    prompt = ("Visual prompt title for %s"):format(project.name),
    default = self:category("visual").default_title,
  }, function(title)
    title = title and vim.trim(title) or ""
    if title == "" then
      return
    end

    local image_path = self:asset_path("visual", "png")
    if not clipboard.save_image(image_path) then
      notify.warn("No PNG image found in the clipboard")
      return
    end

    ui.input({
      prompt = "Visual prompt instructions",
    }, function(details)
      details = details and vim.trim(details) or ""
      self.app.queue_actions:add_project_todo(project, {
        title = title,
        kind = "visual",
        image_path = image_path,
        details = table.concat({
          ("Use the saved clipboard image at `%s` as the main visual reference."):format(image_path),
          details ~= "" and details or "Describe the requested visual change and implement it.",
        }, "\n\n"),
      })
    end)
  end)
end

--- Implements the prompt_for_library path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
function PromptActions:prompt_for_library(project)
  local templates = PromptLibrary.list()
  ui.select(templates, {
    prompt = ("Prompt library for %s"):format(project.name),
--- Implements the format_item path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    format_item = function(item)
      return ("%s  %s"):format(item.label, item.title)
    end,
  }, function(template)
    if not template then
      return
    end
    self:compose_category_prompt(project, self:category(template.kind), template.kind, PromptComposer.render(
      template.title,
      template.details
    ))
  end)
end

--- Implements the prompt_for_category_kind path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param category CodexCli.PromptCategory
function PromptActions:prompt_for_category_kind(project, category)
  if category == "error" then
    self:add_error_todo({ project = project })
    return
  end
  if category == "visual" then
    self:prompt_for_visual(project)
    return
  end
  if category == "todo" then
    self:prompt_for_todo(project)
    return
  end
  if category == "library" then
    self:prompt_for_library(project)
    return
  end

  self:prompt_for_category(project, category)
end

--- Implements the normalize_spec path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param spec { title: string, details?: string }
---@return { title: string, details?: string, broken: boolean }
function PromptActions:normalize_spec(project, spec)
  local normalized = PromptTitle.normalize({
    title = spec.title,
    details = spec.details,
    max_width = self.app.queue_workspace:prompt_title_width(),
  })
  if normalized.broken then
    notify.notify(("Prompt title was shortened for %s to fit the queue list"):format(project.name))
  end
  return normalized
end

--- Adds a new app prompt actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project CodexCli.Project
---@param summary? string
---@param source_details string
---@param image_path? string
function PromptActions:add_error_investigation(project, summary, source_details, image_path)
  summary = summary and vim.trim(summary) or ""
  local title = summary ~= "" and ("Investigate runtime error: " .. summary) or "Investigate runtime error"
  self.app.queue_actions:add_project_todo(project, {
    title = title,
    kind = "error",
    image_path = image_path,
    details = table.concat({
      "Investigate the runtime failure reported by the user.",
      source_details,
      "Explain the cause, implement a fix, and mention any follow-up validation that should be run.",
    }, "\n\n"),
  })
end

--- Adds a new app prompt actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project CodexCli.Project
---@param summary string
function PromptActions:add_problem_summary(project, summary)
  summary = vim.trim(summary)
  if summary == "" then
    return
  end

  self.app.queue_actions:add_project_todo(project, {
    title = "Investigate reported problem: " .. summary,
    kind = "error",
    details = table.concat({
      "Investigate the problem reported by the user.",
      ("Problem description: %s"):format(summary),
      "Explain the cause, implement a fix if needed, and mention any follow-up validation that should be run.",
    }, "\n\n"),
  })
end

--- Implements the error_sources path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param latest_screenshot? string
---@return CodexCli.AppPromptActions.ErrorSource[]
function PromptActions:error_sources(latest_screenshot)
  local sources = {
    {
      label = "Use screenshot from clipboard",
      value = "clipboard_screenshot",
    },
  }

  if latest_screenshot then
    sources[#sources + 1] = {
      label = ("Use latest screenshot (%s)"):format(fs.basename(latest_screenshot)),
      value = "file_screenshot",
    }
  end

  sources[#sources + 1] = {
    label = "Paste error message",
    value = "message",
  }
  sources[#sources + 1] = {
    label = "One-line problem description",
    value = "summary",
  }
  sources[#sources + 1] = {
    label = "Title and body",
    value = "custom",
  }

  return sources
end

--- Implements the pick_error_source path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
---@param project CodexCli.Project
---@param latest_screenshot? string
---@param screenshot_dir? string
function PromptActions:pick_error_source(project, latest_screenshot, screenshot_dir)
  ui.select(self:error_sources(latest_screenshot), {
    prompt = ("Error prompt source for %s"):format(project.name),
--- Implements the format_item path for app prompt actions.
--- This helper is used by orchestration code so this module stays consistent with the rest of the plugin.
--- Keep its effects aligned with callers that rely on project, queue, and terminal state shape.
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice.value == "custom" then
      self:prompt_for_category(project, "error")
      return
    end
    if choice.value == "summary" then
      ui.input({
        prompt = "Problem description",
      }, function(summary)
        summary = summary and vim.trim(summary) or ""
        if summary == "" then
          return
        end
        self:add_problem_summary(project, summary)
      end)
      return
    end
    if choice.value == "clipboard_screenshot" then
      ui.input({
        prompt = "Short error summary (optional)",
      }, function(summary)
        local image_path = self:asset_path("error", "png")
        if not clipboard.save_image(image_path) then
          notify.warn("No PNG image found in the clipboard")
          return
        end
        self:add_error_investigation(
          project,
          summary,
          ("Use the saved clipboard screenshot at `%s` as the main artifact."):format(image_path),
          image_path
        )
      end)
      return
    end

    ui.input({
      prompt = "Short error summary (optional)",
    }, function(summary)
      if choice.value == "file_screenshot" and latest_screenshot then
        self:add_error_investigation(
          project,
          summary,
          ("Use screenshot file `%s` from the configured screenshot directory `%s` as the main artifact."):format(
            fs.basename(latest_screenshot),
            screenshot_dir
          )
        )
        return
      end

      ui.input({
        prompt = "Error message",
      }, function(message)
        message = message and vim.trim(message) or ""
        if message == "" then
          return
        end
        self:add_error_investigation(project, summary, ("Error message:\n```\n%s\n```"):format(message))
      end)
    end)
  end)
end

--- Adds a new app prompt actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? CodexCli.AppPromptActions.ResolveOpts
function PromptActions:add_error_todo(opts)
  local screenshot_dir = self.app.config:get().error_prompt.screenshot_dir
  local latest_screenshot = screenshot_dir and fs.latest_file(screenshot_dir) or nil
  self:pick_project(self:resolve_project(opts), function(project)
    self:pick_error_source(project, latest_screenshot, screenshot_dir)
  end)
end

return PromptActions
