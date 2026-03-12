# clodex.nvim

Project-aware [Codex CLI](https://platform.openai.com/docs/codex) integration for Neovim.

`clodex.nvim` turns Codex into a persistent editor workflow instead of a disposable shell command. It manages long-lived Codex terminal sessions, keeps project context attached to tabs, and adds a queue-driven prompt workspace for staging, dispatching, and tracking implementation tasks directly from Neovim.

The plugin is intentionally Neovim-first rather than agent-first. It keeps the classic Codex CLI experience inside Neovim, then uses Neovim's own context to make prompt authoring faster and more structured. The editor resolves things like files, lines, selections, and diagnostics into plain prompt text before the prompt is sent, so the plugin can stay focused on helping Neovim use AI well instead of centering the whole workflow around agent management.

The plugin is built around a few core ideas:

- one persistent Codex session per registered project
- one ephemeral free session outside projects
- tab-local active project state
- queued prompts that move through `planned`, `queued`, and `history`
- prompt execution receipts so queued work can be completed asynchronously and tracked back in the editor

## Philosophy

The core idea behind `clodex.nvim` is simple:

- keep Codex CLI as the execution engine
- keep Neovim as the place where prompt context is gathered and shaped
- keep prompts portable by converting editor state into ordinary text before dispatch
- treat agent workflow features as optional extensions, not the center of gravity

That means the plugin is not primarily about teaching agents how to operate Neovim. Instead, Neovim does the editor-specific work up front and hands Codex normal prompt text that is easy to reuse anywhere.

Examples of that model:

- a file reference becomes something like `@{lua/clodex/ui/select.lua}`
- a line reference becomes something like `@{lua/clodex/ui/select.lua}: line 42`
- diagnostics become plain text produced by the editor, with enough explanation for the agent to act on them without knowing anything about Neovim

This keeps the system composable. The plugin stays focused on being a strong CLI wrapper with editor-native ergonomics, and if richer agent workflow features become useful later they can be added from that Neovim-first foundation.

## Status

The plugin is functional today and already covers the main terminal, project, and queue workflows. Its direction is intentionally conservative: better prompt generation, better editor integration, and better queue/session ergonomics, without turning the plugin into a separate agent platform.

## What The Plugin Does

### Persistent Codex terminals

Instead of spawning a fresh shell every time, the plugin reuses Codex terminals:

- registered projects get stable project sessions keyed by project root
- non-project work gets a single free session keyed by cwd
- when a free session later becomes a project session for the same root, the plugin promotes it instead of throwing the buffer away
- terminal visibility is tab-local, but the backing session is persistent

This is useful when you want Codex to keep conversational context while you move around the editor.

### Project-aware behavior

Projects are simple records:

- `name`: display label
- `root`: absolute project root

The plugin uses those records to:

- decide which Codex session should open
- route queued prompts to the correct project
- show project summaries in the workspace UI
- expose project state in statusline integrations

If the current buffer lives inside a known project, that project is preferred automatically. Tabs can also pin an active project explicitly, so different tabs can stay focused on different repositories.

### Queue-driven prompt workflow

Each project has a workspace file on disk containing three queues:

- `planned`: captured ideas, bugs, or tasks that are not ready to run yet
- `queued`: ready to dispatch to Codex
- `history`: completed work with execution metadata

Every queue item stores:

- category/kind
- title
- optional details
- rendered prompt text
- timestamps
- optional image path for visual prompts
- optional completion summary, commit, and completion time in history

This lets you treat Codex work more like a lightweight implementation backlog than an ad-hoc chat window.

### Editor-powered prompt generation

Prompt generation is a first-class part of the plugin.

The goal is not to expose Neovim concepts directly to agents. The goal is to let Neovim use its own knowledge of the current editing state to generate better prompts automatically.

In practice, that means editor state such as:

- current file
- current line
- visual selection
- visible buffer region
- word under cursor
- current diagnostics
- buffer diagnostics
- project diagnostics

can be turned into prompt-ready text before dispatch. The resulting prompt stays readable and portable, and the agent only sees ordinary text and file references rather than editor-specific commands or abstractions.

### Prompt categories

The plugin supports several prompt categories out of the box:

- `todo`
- `error`
- `visual`
- `adjustment`
- `refactor`
- `idea`
- `explain`
- `library`

These categories control default titles, visual highlighting, and some specialized behavior:

- `error` can pull in screenshot context
- `visual` can save a clipboard image into prompt assets
- `error` can prefill the latest Vim notification or traceback when you choose the message-based flow
- `library` lets you instantiate a saved prompt template

### Receipt-based prompt execution

Queued prompts are dispatched with a receipt contract. The plugin writes instructions into the prompt that tell Codex to create a small JSON receipt after the work is complete, then keep draining the project's `queued` lane until it is empty. Items in `planned` remain staged and are not started automatically. The plugin polls for those receipts and automatically moves finished items from `queued` to `history`.

That gives you:

- asynchronous completion tracking
- per-item summaries in history
- commit attribution
- completion timestamps
- a clean handoff between Neovim state and Codex execution

## Main Features

- Toggle a Clodex terminal with `:ClodexToggle`.
- Keep one persistent session per project root.
- Keep one free non-project session outside registered projects.
- Track active projects per tabpage.
- Show a floating state preview of current Codex/project state.
- Open a queue workspace with project summaries and prompt history.
- Add prompts from categories or saved prompt templates.
- Use editor state to make prompt generation semi-automatic while keeping prompts agent-friendly.
- Dispatch the next queued prompt or all queued prompts for a project.
- Poll execution receipts and promote completed prompts into history.
- Move, copy, rewind, edit, and delete queue items.
- Preserve session state across Vim sessions.
- Open a project's `TODO.md` or shared dictionary without leaving the current window.
- Expose a small `lualine` helper for current-project display.

## Requirements

- Neovim 0.10+ recommended
- [snacks.nvim](https://github.com/folke/snacks.nvim)
- Codex CLI installed and available in the configured `codex_cmd`

## Installation

Example with `lazy.nvim`:

```lua
{
  "AlexanderGolys/clodex.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  opts = {
    codex_cmd = { "codex" },
    prompt_execution = {
      skills_dir = vim.fn.expand("~/.codex/skills"),
    },
  },
}
```

Minimal manual setup:

```lua
require("clodex").setup()
```

## Configuration

Current defaults:

```lua
require("clodex").setup({
  codex_cmd = { "codex" },
  storage = {
    projects_file = vim.fn.stdpath("data") .. "/clodex/projects.json",
    workspaces_dir = ".clodex/workspaces",
    session_state_dir = vim.fn.stdpath("data") .. "/clodex/session-state",
  },
  terminal = {
    win = {
      position = "right",
      width = 0.35,
    },
    start_insert = true,
  },
  project_detection = {
    auto_suggest_git_root = true,
  },
  state_preview = {
    min_width = 36,
    max_width = 72,
    max_height = 0,
    row = 1,
    col = 2,
    winblend = 18,
  },
  queue_workspace = {
    width = 0.88,
    height = 0.78,
    project_width = 0.32,
    footer_height = 4,
    preview_max_lines = 5,
    fold_preview = true,
    date_format = "%H:%M %d.%m.%Y",
  },
  error_prompt = {
    screenshot_dir = nil,
  },
  highlights = {
    groups = {
      -- custom highlight specs
    },
  },
  prompt_execution = {
    receipts_dir = ".clodex/prompt-executions",
    relative_dir = "",
    poll_ms = 5000,
    skills_dir = nil,
    skill_name = "prompt-nvim-clodex",
  },
})
```

### Important configuration notes

`codex_cmd`

- Command used to start Codex terminals.
- Default is `codex`.

`storage.projects_file`

- JSON file containing the registered project list.
- This remains global by default so the plugin can keep one shared registry of known projects.

`storage.workspaces_dir`

- Queue data and prompt assets are stored under each project's own root here.
- Relative paths are resolved per project, so the default becomes `<project>/.clodex/workspaces`.
- Older data from the former global storage root is migrated into the project-local location on access.

`storage.session_state_dir`

- Session persistence snapshots are stored here.
- Neovim-only project details remain global under `stdpath("data")/clodex/project-details`.

`prompt_execution.receipts_dir`

- Receipt files are written under each project's local `.clodex/prompt-executions` directory by default.
- Relative paths are resolved per project, so the default becomes `<project>/.clodex/prompt-executions`.
- Older receipt files from the former global storage root are migrated into the project-local location when read.

`prompt_execution.relative_dir`

- Legacy fallback receipt path retained only for migration/cleanup of older in-flight jobs.

`prompt_execution.skills_dir`

- Optional path to your Codex skills root.
- When set, the plugin installs a generated skill at `<skills_dir>/<skill_name>/SKILL.md`.
- Queued prompt dispatch then ends with `$prompt-nvim-clodex` instead of inlining the full receipt instructions every time.

`highlights.groups`

- Preferred way to customize prompt/workspace highlight groups.

## Commands

Core commands:

- `:ClodexToggle`
- `:ClodexStateToggle`
- `:ClodexProjectAdd`
- `:ClodexProjectRename`
- `:ClodexProjectRemove`
- `:ClodexProjectClear`
- `:ClodexTerminalHeaderToggle`
- `:ClodexQueueWorkspace`
- `:ClodexProjectTodo`
- `:ClodexProjectDictionary`
- `:ClodexDebugReload`

Queue and prompt commands:

- `:ClodexTodoAdd`
- `:ClodexTodoError`
- `:ClodexTodoImplement`
- `:ClodexTodoImplementAll`
- `:ClodexPromptAdd`
- `:ClodexPromptAddFor`
- `:ClodexPromptTodo`
- `:ClodexPromptError`
- `:ClodexPromptVisual`
- `:ClodexPromptAdjustment`
- `:ClodexPromptRefactor`
- `:ClodexPromptIdea`
- `:ClodexPromptExplain`
- `:ClodexPromptTodoFor`
- `:ClodexPromptErrorFor`
- `:ClodexPromptVisualFor`
- `:ClodexPromptAdjustmentFor`
- `:ClodexPromptRefactorFor`
- `:ClodexPromptIdeaFor`
- `:ClodexPromptExplainFor`

## Queue Workspace

The queue workspace is the main control surface for prompt management.

The left pane shows:

- known projects
- whether a Codex session is running
- queue counts for `planned`, `queued`, and `history`
- project detail snapshots such as file counts, languages, git remote, and recent activity

The right pane shows:

- prompts grouped by queue
- category-colored titles
- prompt previews
- history metadata for completed items

Supported workspace actions include:

- activate/deactivate a project Codex session
- open the selected project workspace
- add prompts
- edit prompts
- move prompts between queues
- dispatch queued prompts
- copy or move prompts between projects
- delete prompts or whole projects

## How Prompt Execution Works

When a queued item is dispatched:

1. The plugin ensures the target project session is running.
2. It clears any stale receipt file for that queue item.
3. It renders the queue item into a Codex prompt.
4. It appends execution instructions describing where the JSON receipt must be written.
5. If a prompt skill is configured, it appends `$prompt-nvim-clodex`.
6. Codex performs the work and writes the receipt when done.
7. If more prompts are still in `queued`, Codex continues with the next one; items in `planned` are left alone.
8. The plugin polls receipt files on a timer and moves completed items into history.

### Receipt schema

Receipts currently contain:

- `summary`
- `commit`
- `completed_at`
- `version`

Those values are used to populate the history queue and to make completion status visible inside Neovim.

## Prompt Library

The built-in prompt library currently ships with reusable templates such as:

- `fix-diagnostics`
- `explain-current-file`
- `refactor-selection`
- `summarize-qf`

These are plain prompt blueprints that can be inserted into the queue as normal items.

## Public Lua API

Public entrypoints live in [`lua/clodex/init.lua`](/home/flux/nvim-plugins/clodex.nvim/lua/clodex/init.lua).

Main functions:

- `require("clodex").setup(opts)`
- `require("clodex").toggle()`
- `require("clodex").toggle_state_preview()`
  - `require("clodex").add_project(opts)`
- `require("clodex").rename_project(name)`
- `require("clodex").remove_project(value)`
- `require("clodex").clear_active_project()`
- `require("clodex").open_queue_workspace()`
- `require("clodex").add_todo(opts)`
- `require("clodex").add_prompt(opts)`
- `require("clodex").add_prompt_for_project(opts)`
- `require("clodex").add_error_todo(opts)`
- `require("clodex").implement_next_queued_item(opts)`
- `require("clodex").implement_all_queued_items(opts)`
- `require("clodex").debug_reload()`

Statusline helper:

- `require("clodex").lualine.project(opts)`
- `require("clodex").lualine.project_name(opts)`

Example:

```lua
sections = {
  lualine_x = {
    function()
      return require("clodex").lualine.project_name({
        include_detected = true,
        prefix = "Clodex:",
      })
    end,
  },
}
```

## Architecture

The codebase is intentionally split by responsibility:

```text
lua/clodex/
  init.lua
  app.lua
  commands.lua
  config.lua
  lualine.lua
  project/
  prompt/
  session/
  tab/
  terminal/
  ui/
  util/
  workspace/
plugin/
  clodex.lua
```

Important modules:

- `app.lua`: top-level orchestration and user-facing behavior
- `terminal/`: terminal session lifecycle and window management
- `project/`: registry, detection, metadata, and project picking
- `workspace/`: queued prompts, storage, and execution receipts
- `ui/`: floating windows, prompt workspace rendering, and selection helpers
- `config.lua`: defaults, merging, and highlight application

## API And Runtime Model

From an integration standpoint, the plugin uses:

- Neovim Lua APIs for buffers, windows, timers, extmarks, user commands, and autocommands
- `snacks.nvim` for terminal window construction and UI primitives
- filesystem JSON storage for projects and queue state
- Codex CLI as the actual execution backend

The runtime loop is straightforward:

- Neovim owns editor state and UI
- Neovim can turn editor state into plain prompt text before dispatch
- the plugin derives project/session intent from that state
- Codex CLI runs in a persistent terminal buffer
- queued prompt execution writes receipts back to disk
- the plugin polls those receipts and updates editor-visible state

## Roadmap

The current implementation is centered on project/session management and queued prompt execution. Planned or likely follow-up areas include:

- richer prompt-generation flows based on editor context such as current file, ranges, diagnostics, and quickfix lists
- more reusable prompt-library templates
- broader test coverage for config merging, queue transitions, and session persistence
- additional project/session metadata surfaced in the UI
- more refined prompt authoring flows for visual and diagnostic tasks

## Development

Useful checks while developing:

```bash
nvim --headless "+lua require('clodex').setup()" +qa
nvim --headless "+lua print(vim.inspect(require('clodex')))" +qa
```

Manual validation:

1. Register a project and open `:ClodexQueueWorkspace`.
2. Add prompts and move one into `queued`.
3. Dispatch it with `:ClodexTodoImplement`.
4. Confirm the prompt is sent to the project session.
5. Write a matching receipt file and verify the item moves into `history`.

## License

MIT. See [`LICENSE`](/home/flux/nvim-plugins/clodex.nvim/LICENSE).
