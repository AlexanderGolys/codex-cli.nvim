local PromptAssets = require("clodex.prompt.assets")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")
local fs = require("clodex.util.fs")
local notify = require("clodex.util.notify")
local ui = require("clodex.ui.select")

--- Defines the Clodex.AppPromptActions.ResolveOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.AppPromptActions.ResolveOpts
---@field project? Clodex.Project
---@field project_root? string
---@field project_name? string
---@field project_value? string
---@field project_required? boolean

--- Defines the Clodex.AppPromptActions.PickPromptOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.AppPromptActions.PickPromptOpts: Clodex.AppPromptActions.ResolveOpts
---@field project_required? boolean
---@field category? Clodex.PromptCategory

--- Defines the Clodex.AppPromptActions.AddTodoSpec type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.AppPromptActions.AddTodoSpec
---@field title string
---@field details? string
---@field kind? Clodex.PromptCategory
---@field image_path? string
---@field completion_target? Clodex.QueueName

--- Defines the Clodex.AppPromptActions.BugSource type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.AppPromptActions.BugSource
---@field label string
---@field value "clipboard_screenshot"|"file_screenshot"|"message"|"summary"|"custom"

--- Defines the Clodex.AppPromptActions type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.AppPromptActions
---@field app Clodex.App
local PromptActions = {}
PromptActions.__index = PromptActions

---@param app Clodex.App
---@return Clodex.AppPromptActions
function PromptActions.new(app)
    return setmetatable({ app = app }, PromptActions)
end

---@param project Clodex.Project
---@return string?
local function library_language_hint(self, project)
    local details_store = self.app.project_details_store
    if not details_store or not details_store.get_cached then
        return nil
    end

    local details = details_store:get_cached(project)
    local languages = details and details.languages or nil
    local primary = type(languages) == "table" and languages[1] or nil
    local name = primary and primary.name or nil
    if type(name) ~= "string" or name == "other" then
        return nil
    end
    return name
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
---@return Clodex.Project?
function PromptActions:resolve_project(opts)
    opts = opts or {}
    local project = opts.project
    if not project and opts.project_root then
        project = self.app.registry:get(opts.project_root)
    end
    if not project and opts.project_name then
        project = self.app.registry:find_by_name(opts.project_name)
    end
    if not project and opts.project_value then
        project = self.app.registry:find_by_name_or_root(opts.project_value)
    end
    if project then
        return project
    end
    if opts.project_required then
        return nil
    end

    local state = self.app:current_tab()
    local target = self.app:resolve_target(state)
    if target.kind == "project" then
        return target.project
    end
end

--- Opens a picker path for app prompt actions and handles the chosen result.
--- It is used by user-driven selection flows to continue the action pipeline with valid input.
---@param target_project Clodex.Project?
---@param callback fun(project: Clodex.Project)
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

---@param project Clodex.Project
---@param callback fun(project: Clodex.Project, category: Clodex.PromptCategory)
function PromptActions:pick_category(project, callback)
    local items = {} ---@type { label: string, detail: string, category: Clodex.PromptCategoryDef }[]
    for _, category in ipairs(Prompt.categories.list()) do
        if category.id ~= "notworking" then
            items[#items + 1] = {
                label = category.label,
                detail = category.picker_detail or category.default_title,
                category = category,
            }
        end
    end

    ui.pick_text(items, {
        prompt = ("Prompt category for %s"):format(project.name),
        snacks = {
            preview = "none",
            layout = {
                hidden = { "preview" },
            },
        },
    }, function(item)
            if item then
                callback(project, item.category.id)
            end
        end)
end

---@param project Clodex.Project
---@param category Clodex.PromptCategory
---@return string?
function PromptActions:save_clipboard_image(project, category)
    return PromptAssets.save_clipboard_image(self.app.config:get().storage.workspaces_dir, project.root, category)
end

---@param project Clodex.Project
---@param category Clodex.PromptCategory
---@return fun(): string?
function PromptActions:paste_image_callback(project, category)
    return function()
        local image_path = self:save_clipboard_image(project, category)
        if not image_path then
            return nil
        end
        return ("Use the saved clipboard image at `%s` as an additional visual reference."):format(image_path)
    end
end

--- Opens a picker path for app prompt actions and handles the chosen result.
--- It is used by user-driven selection flows to continue the action pipeline with valid input.
---@param opts? Clodex.AppPromptActions.PickPromptOpts
---@param callback fun(project: Clodex.Project, category: Clodex.PromptCategory)
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

---@param project Clodex.Project
function PromptActions:prompt_for_todo(project)
    ui.multiline_input({
        prompt = ("Todo prompt for %s"):format(project.name),
        context = PromptContext.capture({ project = project }),
        paste_image = self:paste_image_callback(project, "todo"),
        submit_actions = {
            { value = "save",  label = "plan",    key = "<C-s>" },
            { value = "queue", label = "queue",   key = "<C-q>" },
            { value = "exec",  label = "run now", key = "<C-e>" },
        },
    }, function(body, action)
            local spec = body and Prompt.parse(body) or nil
            if not spec then
                return
            end
            local queue_opts = action == "exec"
            and { queue = "queued", implement = true, run_mode = "exec" }
            or action == "queue" and { queue = "queued" }
            or nil
            self.app.queue_actions:add_project_todo(project, {
                title = spec.title,
                details = spec.details,
            }, queue_opts)
        end)
end

--- Opens a multiline prompt composer for a category-specific todo.
--- The composed body is parsed back into queue title/details before persistence.
---@param project Clodex.Project
---@param definition Clodex.PromptCategoryDef
---@param category Clodex.PromptCategory
---@param default_body? string
function PromptActions:compose_category_prompt(project, definition, category, default_body)
    ui.multiline_input({
        prompt = ("%s prompt for %s"):format(definition.label, project.name),
        default = default_body or definition.default_title,
        context = PromptContext.capture({ project = project }),
        paste_image = self:paste_image_callback(project, category),
        submit_actions = {
            { value = "save",  label = "plan",    key = "<C-s>" },
            { value = "queue", label = "queue",   key = "<C-q>" },
            { value = "exec",  label = "run now", key = "<C-e>" },
        },
    }, function(body, action)
            local spec = body and Prompt.parse(body) or nil
            if not spec then
                return
            end
            local queue_opts = action == "exec"
            and { queue = "queued", implement = true, run_mode = "exec" }
            or action == "queue" and { queue = "queued" }
            or nil
            self.app.queue_actions:add_project_todo(project, {
                title = spec.title,
                details = spec.details,
                kind = category,
            }, queue_opts)
        end)
end

---@param project Clodex.Project
---@param category Clodex.PromptCategory
function PromptActions:prompt_for_category(project, category)
    local definition = Prompt.categories.get(category)
    self:compose_category_prompt(project, definition, category)
end

---@param project Clodex.Project
function PromptActions:prompt_for_visual(project)
    ui.input({
        prompt = ("Visual prompt title for %s"):format(project.name),
        default = Prompt.categories.get("visual").default_title,
    }, function(title)
            title = title and vim.trim(title) or ""
            if title == "" then
                return
            end

            local image_path = self:save_clipboard_image(project, "visual")
            if not image_path then
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

---@param project Clodex.Project
function PromptActions:prompt_for_library(project)
    local templates = Prompt.library.list({ language = library_language_hint(self, project) })
    local items = {}
    for _, template in ipairs(templates) do
        items[#items + 1] = vim.tbl_extend("force", template, {
            detail = template.title,
            preview = {
                text = table.concat({
                    ("# %s"):format(template.label),
                    "",
                    ("- Kind: `%s`"):format(template.kind),
                    ("- Title: `%s`"):format(template.title),
                    "",
                    "## Template body",
                    "",
                    "```text",
                    Prompt.render(template.title, template.details),
                    "```",
                }, "\n"),
                ft = "markdown",
                loc = false,
            },
            preview_title = template.label,
        })
    end

    ---@param item Clodex.PromptLibrary.Template
    ui.pick_text(items, {
        prompt = ("Prompt library for %s"):format(project.name),
    }, function(item)
            if not item then
                return
            end
            self:compose_category_prompt(project, Prompt.categories.get(item.kind), item.kind, Prompt.render(
                item.title,
                item.details
            ))
        end)
end

---@param project Clodex.Project
---@param category Clodex.PromptCategory
function PromptActions:prompt_for_category_kind(project, category)
    if category == "bug" then
        self:add_bug_todo({ project = project })
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

---@param project Clodex.Project
---@param spec { title: string, details?: string }
---@return { title: string, details?: string, broken: boolean }
function PromptActions:normalize_spec(project, spec)
    local normalized = Prompt.normalize_title({
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
---@param project Clodex.Project
---@param summary? string
---@param source_details string
---@param image_path? string
---@param completion_target? Clodex.QueueName
function PromptActions:add_bug_investigation(project, summary, source_details, image_path, completion_target)
    summary = summary and vim.trim(summary) or ""
    local title = summary ~= "" and ("Investigate runtime bug: " .. summary) or "Investigate runtime bug"
    self.app.queue_actions:add_project_todo(project, {
        title = title,
        kind = "bug",
        image_path = image_path,
        completion_target = completion_target,
        details = table.concat({
            "Investigate the runtime failure reported by the user.",
            source_details,
            "Explain the cause, implement a fix, and mention any follow-up validation that should be run.",
        }, "\n\n"),
    })
end

--- Adds a new app prompt actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project Clodex.Project
---@param summary string
function PromptActions:add_problem_summary(project, summary)
    summary = vim.trim(summary)
    if summary == "" then
        return
    end

    self.app.queue_actions:add_project_todo(project, {
        title = "Investigate reported problem: " .. summary,
        kind = "bug",
        details = table.concat({
            "Investigate the problem reported by the user.",
            ("Problem description: %s"):format(summary),
            "Explain the cause, implement a fix if needed, and mention any follow-up validation that should be run.",
        }, "\n\n"),
    })
end

---@param latest_screenshot? string
---@return Clodex.AppPromptActions.BugSource[]
function PromptActions:bug_sources(latest_screenshot)
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
        label = "Paste error message or traceback",
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

---@param body string
---@return string?
local function freeform_message(body)
    local spec = Prompt.parse(body)
    if not spec then
        return nil
    end

    local parts = { spec.title }
    if spec.details and spec.details ~= "" then
        parts[#parts + 1] = spec.details
    end
    local message = vim.trim(table.concat(parts, "\n"))
    return message ~= "" and message or nil
end

---@return string?
local function read_bug_message_register()
    local registers = { "+", '"', "*" }
    for _, register in ipairs(registers) do
        local message = vim.trim((vim.fn.getreg(register) or ""):gsub("\r\n", "\n"))
        if message ~= "" then
            return message
        end
    end
end

---@param project Clodex.Project
---@param latest_screenshot? string
---@param screenshot_dir? string
function PromptActions:pick_bug_source(project, latest_screenshot, screenshot_dir)
    local items = {}
    for _, item in ipairs(self:bug_sources(latest_screenshot)) do
        local details_by_value = {
            clipboard_screenshot = "Save the current clipboard image as the main artifact.",
            file_screenshot = latest_screenshot and
                ("Reuse `%s` from the screenshot directory."):format(fs.basename(latest_screenshot))
                or "Reuse the latest screenshot from disk.",
            message = "Paste a raw error message or traceback from this project.",
            summary = "Start from a one-line description and expand it into an investigation prompt.",
            custom = "Open the full title-and-body prompt composer.",
        }
        items[#items + 1] = {
            label = item.label,
            detail = details_by_value[item.value],
            value = item.value,
            preview = {
                text = table.concat({
                    ("# %s"):format(item.label),
                    "",
                    details_by_value[item.value] or "",
                }, "\n"),
                ft = "markdown",
                loc = false,
            },
            preview_title = item.label,
        }
    end

    ---@param choice { label: string, detail: string, value: string, preview: table, preview_title: string }
    ui.pick_text(items, {
        prompt = ("Bug prompt source for %s"):format(project.name),
    }, function(choice)
            if not choice then
                return
            end
            if choice.value == "custom" then
                self:prompt_for_category(project, "bug")
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
                    prompt = "Short bug summary (optional)",
                }, function(summary)
                        local image_path = self:save_clipboard_image(project, "bug")
                        if not image_path then
                            return
                        end
                        self:add_bug_investigation(
                            project,
                            summary,
                            ("Use the saved clipboard screenshot at `%s` as the main artifact."):format(image_path),
                            image_path,
                            "history"
                        )
                    end)
                return
            end

            if choice.value == "message" then
                ui.input({
                    prompt = "Comment about the error (optional)",
                }, function(comment)
                        local message = read_bug_message_register()
                        if not message then
                            notify.warn("No error message found in the clipboard registers.")
                            return
                        end

                        comment = comment and vim.trim(comment) or ""
                        local source_details = {
                            ("Bug message:\n```\n%s\n```"):format(message),
                        }
                        if comment ~= "" then
                            table.insert(source_details, 1, ("User comment: %s"):format(comment))
                        end
                        self:add_bug_investigation(
                            project,
                            comment,
                            table.concat(source_details, "\n\n"),
                            nil,
                            "history"
                        )
                    end)
                return
            end

            ui.input({
                prompt = "Short bug summary (optional)",
            }, function(summary)
                    if choice.value == "file_screenshot" and latest_screenshot then
                        self:add_bug_investigation(
                            project,
                            summary,
                            ("Use screenshot file `%s` from the configured screenshot directory `%s` as the main artifact.")
                                :format(
                                fs.basename(latest_screenshot),
                                screenshot_dir
                            ),
                            nil,
                            "history"
                        )
                        return
                    end
                    ui.multiline_message_input({
                        prompt = "Bug message or traceback",
                        min_height = 10,
                        context = PromptContext.capture({ project = project }),
                        paste_image = self:paste_image_callback(project, "bug"),
                    }, function(body)
                            local message = body and freeform_message(body) or nil
                            message = message and vim.trim(message) or ""
                            if message == "" then
                                return
                            end
                            self:add_bug_investigation(
                                project,
                                summary,
                                ("Bug message:\n```\n%s\n```"):format(message),
                                nil,
                                "history"
                            )
                        end)
                end)
        end)
end

--- Adds a new app prompt actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param opts? Clodex.AppPromptActions.ResolveOpts
function PromptActions:add_bug_todo(opts)
    local screenshot_dir = self.app.config:get().bug_prompt.screenshot_dir
    local latest_screenshot = screenshot_dir and fs.latest_file(screenshot_dir) or nil
    self:pick_project(self:resolve_project(opts), function(project)
        self:pick_bug_source(project, latest_screenshot, screenshot_dir)
    end)
end

return PromptActions
