# clodex.nvim

Project-aware [Codex CLI](https://platform.openai.com/docs/codex) integration for Neovim.
`clodex.nvim` turns Codex into a persistent editor workflow instead of a disposable shell command. It manages long-lived Codex terminal sessions, keeps project context attached to tabs, and adds a queue-driven prompt workspace for staging, dispatching, and tracking implementation tasks directly from Neovim.

The plugin is intentionally Neovim-first rather than agent-first. It keeps the classic Codex CLI experience inside Neovim, then uses Neovim's own context to make prompt authoring faster and more structured. The editor resolves things like files, lines, selections, and diagnostics into plain prompt text before the prompt is sent, so the plugin can stay focused on helping Neovim use AI well instead of centering the whole workflow around agent management.

The plugin is built around a few core ideas:

- one persistent Codex session per registered project
- one ephemeral free session outside projects
- tab-local active project state
- queued prompts that move through `planned`, `queued`, `implemented`, and `history`
- prompt execution receipts so queued work can be completed asynchronously and tracked back in the editor

## Philosophy

The core idea behind `clodex.nvim` is simple:

- keep Codex CLI as the execution engine
- keep Neovim as the place where prompt context is gathered and shape
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

When opening a project README or workspace target, Clodex keeps the current buffer in place if it has unsaved changes instead of forcing an `:edit` that would fail with `E37`.

### Queue-driven prompt workflow

Each project keeps four queue files on disk under `.clodex/`:

- `planned`: captured ideas, bugs, or tasks that are not ready to run yet
- `queued`: ready to dispatch to Codex
- `implemented`: work that has been dispatched and completed, but is waiting for human verification
- `history`: verified work with execution metadata

Every queue item stores:

- category/kind
- title
- optional details
- rendered prompt text
- timestamps
- optional image path for visual prompts
- optional completion summary, commits, and completion time in implemented/history

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
- `bug`
- `visual`
- `adjustment`
- `refactor`
- `idea`
- `ask`
- `library`

These categories control default titles, visual highlighting, and some specialized behavior:

- `bug` can pull in screenshot context
- `visual` can save a clipboard image into prompt assets
- multiline prompt editors can paste a clipboard image into the prompt body with `Ctrl-V`
- `bug` can build a message-based investigation directly from the clipboard/register contents and only asks you for an optional comment
- `library` lets you instantiate a saved prompt template

### Queue-file prompt execution

Queued prompts are dispatched with a queue-state update contract. The plugin writes instructions into the prompt that tell Codex to finish the work, use kind-aware completion rules, and prefer the local `clodex` MCP queue tools for completion metadata updates when they are available. If the MCP server is unavailable, the same instructions fall back to updating the project-local `.clodex/queued.json`, `.clodex/implemented.json`, and `.clodex/history.json` files directly. Items in `planned` remain staged and are not started automatically. The plugin moves dispatched items from `queued` to `implemented`, and the agent records execution metadata on that implemented item before optionally moving it to `history`.

That gives you:

- asynchronous completion tracking
- per-item summaries during implementation and after verification
- commit attribution
- completion timestamps
- a clean handoff between Neovim state and Codex execution

## Main Features

- Toggle a Clodex terminal with `:Clodex cli`.
- Keep one persistent session per project root.
- Keep one free non-project session outside registered projects.
- Track active projects per tabpage.
- Show a floating state preview of current Codex/project state.
- Open a queue workspace with project summaries and prompt history.
- Add prompts from categories or saved prompt templates.
- Use editor state to make prompt generation semi-automatic while keeping prompts agent-friendly.
- Dispatch the next queued prompt or all queued prompts for a project.
- Poll queue-file changes and update implemented prompts with completion metadata.
- Move, copy, rewind, edit, and delete queue items.
- Preserve session state across Vim sessions.
- Open a project's `TODO.md` or shared dictionary without leaving the current window.
- Expose a small `lualine` helper for current-project display.

## Requirements

- Neovim 0.10+ recommended
- [snacks.nvim](https://github.com/folke/snacks.nvim)
- Codex CLI or OpenCode CLI installed for the configured backend

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
  },
}
```

Example with `lazy.nvim` using the plugin defaults explicitly:

```lua
{
  "AlexanderGolys/clodex.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  opts = {
    backend = "codex",
    codex_cmd = { "codex" },
    opencode_cmd = { "opencode" },
    storage = {
      projects_file = vim.fn.stdpath("data") .. "/clodex/projects.json",
      workspaces_dir = ".clodex",
      session_state_dir = vim.fn.stdpath("data") .. "/clodex/session-state",
      history_file = vim.fn.stdpath("data") .. "/clodex/history.md",
    },
    terminal = {
      provider = "snacks",
      win = {
        position = "right",
        width = 0.4,
      },
      start_insert = true,
      prefer_native_statusline = true,
    },
    project_detection = {
      auto_suggest_git_root = false,
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
      width = 1,
      height = 1,
      project_width = 0.3,
      footer_height = 3,
      preview_max_lines = 5,
      fold_preview = true,
      date_format = "ago",
    },
    bug_prompt = {
      screenshot_dir = nil,
    },
    highlights = {
      groups = {},
    },
    prompt_execution = {
      receipts_dir = ".clodex/prompt-executions",
      poll_ms = 5000,
      skills_dir = vim.fn.expand("~/.codex/skills"),
      skill_name = "prompt-nvim-clodex",
    },
    session = {
      persist_current_project = true,
    },
    keymaps = {
      toggle = { lhs = "<leader>pt" },
      queue_workspace = { lhs = "<leader>pq" },
      state_preview = { lhs = "<leader>ps" },
    },
    manual_history = {
      model_instructions_file = "",
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
  backend = "codex",
  codex_cmd = { "codex" },
  opencode_cmd = { "opencode" },
  storage = {
    projects_file = vim.fn.stdpath("data") .. "/clodex/projects.json",
    workspaces_dir = ".clodex",
    session_state_dir = vim.fn.stdpath("data") .. "/clodex/session-state",
  },
  terminal = {
    provider = "snacks",
    win = {
      position = "right",
      width = 0.35,
    },
    start_insert = true,
  },
  project_detection = {
    auto_suggest_git_root = false,
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
  bug_prompt = {
    screenshot_dir = nil,
  },
  highlights = {
    groups = {
      -- custom highlight specs
    },
  },
  prompt_execution = {
    receipts_dir = ".clodex/prompt-executions",
    poll_ms = 5000,
    skills_dir = vim.fn.expand("~/.codex/skills"),
    skill_name = "prompt-nvim-clodex",
  },
  keymaps = {
    toggle = { lhs = "<leader>pt" },
    queue_workspace = { lhs = "<leader>pq" },
    state_preview = { lhs = "<leader>ps" },
  },
})
```

### Important configuration notes

`keymaps`

- Defaults now accept legacy string values (`"<leader>pt"`) or table-based setters:
  - `toggle`: runs `:Clodex cli`
  - `queue_workspace`: runs `:Clodex`
  - `state_preview`: runs `:ClodexDebug panel`
  - `mini_state_preview`: runs `:ClodexDebug mini`
  - `backend_toggle`: runs `:Clodex backend`
  - `lhs` (string): key sequence.
  - `enabled` (boolean): set to `false` to disable.
  - `mode` (string|string[]): keymap mode(s).
  - Neovim keymap option keys (for example `silent`, `noremap`, `nowait`, `expr`).
- Example:
  ```lua
  keymaps = {
      toggle = { lhs = "<leader>pt", mode = "n", silent = true },
      queue_workspace = { lhs = "<leader>pq", enabled = false },
      state_preview = "<leader>ps", -- legacy style remains supported
  },
  ```

`backend`

- Selects the interactive CLI backend.
- Supported values are `codex` and `opencode`.
- Default is `codex`.

`codex_cmd`

- Command used to start Codex terminals.
- Default is `codex`.

`opencode_cmd`

- Command used to start OpenCode terminals when `backend = "opencode"`.
- Default is `opencode`.

`terminal.provider`

- Chooses how Clodex starts the interactive terminal job.
- Supported values are `snacks` and `term`.
- `snacks` uses `snacks.terminal`; `term` uses Neovim's built-in terminal via `termopen()` while keeping the same Clodex session/window workflow.
- Default is `snacks`.

`storage.projects_file`

- JSON file containing the registered project list.
- This remains global by default so the plugin can keep one shared registry of known projects.

`project_detection.auto_suggest_git_root`

- Defaults to `false`.
- Clodex does not add or suggest projects automatically during normal terminal toggles.
- Projects should only be registered through explicit user actions such as `:ClodexProject add`.

`storage.workspaces_dir`

- Queue data and prompt assets are stored under each project's own root here.
- Relative paths are resolved per project, so the default becomes `<project>/.clodex`.
- Older data from the former global storage root is migrated into the project-local location on access.

`storage.session_state_dir`

- Session persistence snapshots are stored here.
- Neovim-only project details remain global under `stdpath("data")/clodex/project-details`.

`prompt_execution.receipts_dir`

- Project-local execution artifacts are written under each project's local `.clodex/prompt-executions` directory by default.
- Relative paths are resolved per project, so the default becomes `<project>/.clodex/prompt-executions`.
- Older receipt files from the former global storage root are still recognized for compatibility with legacy in-flight jobs.

`prompt_execution.skills_dir`

- Backend-specific synced skill root.
- For `backend = "codex"`, the default is `~/.codex/skills`, and `setup()` syncs the checked-in skill into `<skills_dir>/<skill_name>/SKILL.md`.
- For `backend = "opencode"`, the default is `.opencode/skills`, and Clodex syncs the checked-in skill into `<project>/.opencode/skills/<skill_name>/SKILL.md` when dispatching a prompt for that project.
- Set this to an empty string to disable synced skill mode and fall back to inline `$prompt` instructions.
- Queued prompt dispatch still ends with `$prompt-nvim-clodex` instead of inlining the full queue-file update instructions every time.

`highlights.groups`

- Preferred way to customize prompt/workspace highlight groups.

## Commands

Core commands:

- `:Clodex` or `:Clodex panel`
- `:Clodex cli`
- `:Clodex history`
- `:Clodex backend`
- `:Clodex header`
- `:ClodexDebug panel`
- `:ClodexDebug mini`
- `:ClodexDebug reload`
- `:ClodexProject add [name]?`
- `:ClodexProject readme`
- `:ClodexProject dictionary`
- `:ClodexProject cheatsheet`
- `:ClodexProject cheatsheet-panel`
- `:ClodexProject cheatsheet-add`
- `:ClodexProject notes`
- `:ClodexProject note-add`
- `:ClodexProject bookmarks`
- `:ClodexProject bookmark-add`

Queue and prompt commands:

- `:ClodexTodo [add]? [for]? [project]?`
- `:ClodexTodo bug [for]? [project]?`
- `:ClodexTodo implement [for]? [project]?`
- `:ClodexTodo all [for]? [project]?`
- `:ClodexPrompt [kind]? [for]? [project]?`
- `:ClodexPrompt refactor`
- `:ClodexPrompt bug for`
- `:ClodexPrompt ask demo-project`


## Queue Workspace

The queue workspace is the main control surface for prompt management.

The left pane shows:

- known projects
- whether a Codex session is running
- queue counts for `planned`, `queued`, `implemented`, and `history`
- project detail snapshots such as file counts, languages, git remote, and recent activity

The right pane shows:

- prompts grouped by queue
- category-colored titles
- prompt previews
- implementation/history metadata for completed items

Supported workspace actions include:

- activate/deactivate a project Codex session
- open the selected project workspace
- add prompts
- edit prompts
- move prompts between queues
- dispatch queued prompts
- copy or move prompts between projects
- delete prompts or whole projects

Confirmation pickers from the workspace open as focused modal overlays above the main panels, so destructive actions stay keyboard-accessible instead of leaving focus behind on the workspace panes.

## How Prompt Execution Works

When a queued item is dispatched:

1. The plugin ensures the target project session is running.
2. It renders the queue item into a Codex prompt.
3. It appends hidden execution instructions describing which queue item id and prompt kind must be used for completion.
4. If a prompt skill is configured, it appends `$prompt-nvim-clodex`.
5. Codex performs the work, skips commits for `ask` prompts, creates a focused commit for other kinds when the project is git-backed, and updates the current item in the project-local queue files when done.
6. If more prompts are still in `queued`, Codex continues with the next one; items in `planned` are left alone.
7. The plugin polls queue-file revisions on a timer and refreshes the matching item in Neovim.

### Implemented Item Metadata

Implemented/history items are updated in place with:

- `history_summary`
- `history_commits`
- `history_completed_at`

Those values are used to populate the implemented/history views and to make completion status visible inside Neovim.

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

Terminal statusline note:

- Clodex sets its intended local `statusline` and `winbar` for `clodex_terminal` buffers when that filetype is created.
- When `lualine.nvim` is already loaded, Clodex automatically excludes `clodex_terminal` from lualine's statusline and winbar targets so the native mirrored Codex CLI line stays visible in terminal buffers.
- If you prefer your own statusline in Codex terminal buffers, disable that behavior in `setup()`:

```lua
require("clodex").setup({
  terminal = {
    prefer_native_statusline = false,
  },
})
```

- If you manage lualine manually and want the equivalent explicit rule, exclude `clodex_terminal` from lualine yourself:

```lua
require("lualine").setup({
    options = {
      disabled_filetypes = {
        statusline = { "clodex_terminal" },
        winbar = { "clodex_terminal" },
      },
    },
})
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
- `workspace/`: queued prompts, queue-file storage, and execution receipts
- `ui/`: floating windows, prompt workspace rendering, and selection helpers
- `config.lua`: defaults, merging, and highlight application

## API And Runtime Model

From an integration standpoint, the plugin uses:

- Neovim Lua APIs for buffers, windows, timers, extmarks, user commands, and autocommands
- `snacks.nvim` for terminal window construction and UI primitives
- filesystem JSON storage for projects and queue state
- Codex CLI or OpenCode CLI as the interactive execution backend

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

Testing with Plenary:

```bash
bin/clodex-nvim-test
```

The test suite expects Plenary to be discoverable in the same runtime environment as this repository (or globally available in your `runtimepath`).

If task context getting lost between branches, use the local task switch helper:

```bash
cd /home/flux/nvim-plugins/clodex.nvim
private/taskctl/taskctl start "Fix broken todo registration"
private/taskctl/taskctl status
private/taskctl/taskctl list
private/taskctl/taskctl done
```

You can install this helper as a global command in your `$HOME/.local/bin`:

```bash
ln -sfn "$(pwd)/private/taskctl/taskctl" "$HOME/.local/bin/taskctl"
```

It keeps a local branch ledger in `.clodex/task-memory` so you can resume the exact task branch later even after switching to another task.

If you want a separate local git workflow, keep it in your personal dotfiles or shell scripts and wire it to your own Neovim keymaps. The plugin stays focused on Codex/project workflow only.

This plugin intentionally does **not** provide:

- branch creation/switching helpers
- commit helpers
- PR/rebase/review helpers
- lazygit or GitHub command integrations

Use your preferred local tooling for Git operations and keep that outside this plugin.

Fresh, minimal Neovim instance for this plugin only:

```bash
./bin/clodex-nvim-minimal
```

That launcher uses a clean, isolated `XDG_*` directory and loads dependencies via `lazy.nvim`:

- `clodex.nvim` from this repo
- `snacks.nvim`
- `catppuccin` (colorscheme)
- `nvim-treesitter`

`lazy.nvim` is also bootstrapped only inside this isolated data root (no fallback to your main Neovim lazy cache), so first launch from a fresh environment will install dependencies locally and keep them separated.

Install it as a global TUI command (`clodex-nvim`) available from any directory:

```bash
./bin/install-clodex-nvim-tui
hash -r
clodex-nvim .
```

That command acts like `nvim` with a different `-u`-style config and forwards all CLI arguments.

Code placement policy:

- Plugin runtime code that is shipped/public: `lua/`, `plugin/`, and this README/docs.
- Private/local launcher artifacts (local Lua bootstrap, local launcher scripts, cached local test state): keep outside tracked plugin code and add to local ignore rules (already configured for this repo).
- If you add another local helper for a private workflow, put it under your local ignore area and avoid loading it in the plugin runtime path.

Testing guidelines:

- Every new feature should ship with at least one new spec in [`tests/specs`](/home/flux/nvim-plugins/clodex.nvim/tests/specs), and the full suite should be run before merge.
- If a bug is reported and fixed, add a regression spec that reproduces the bug and fails on the old behavior, then passes after the fix.
- Prefer keeping one focused spec file per public module area (`workspace`, `prompt`, `config`, `util`) and naming specs by behavior (`queue transitions`, `config merge`, `context tokens`).
- Update this section when test tooling, required env vars, or plugin dependencies change so contributors always have a reliable command list.

Manual validation:

1. Register a project and open `:Clodex`.
2. Add prompts and move one into `queued`.
3. Dispatch it with `:ClodexTodo implement`.
4. Confirm the prompt is sent to the project session.
5. Confirm Codex creates a focused commit, updates the implemented item metadata in the `.clodex` queue files, and shows the commit in the main panel preview.

## License

MIT. See [`LICENSE`](/home/flux/nvim-plugins/clodex.nvim/LICENSE).
