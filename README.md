# codex-cli.nvim

Project-aware [Codex CLI](https://platform.openai.com/docs/codex) integration for Neovim, built around `snacks.nvim` terminals and pickers.

The goal is to make Codex feel like a persistent editor-native tool instead of a disposable shell command: one Codex session per project, one ephemeral free session outside projects, tab-local project selection, and prompt helpers that can translate Neovim state into text Codex can understand.

## Status

Design and scaffold phase.

This README describes the intended behavior and structure of the plugin before the full implementation lands.

## Features

### Core terminal workflow

- Toggle Codex CLI inside a `snacks.nvim` terminal window.
- Launch Codex with the `codex` shell command in `bash`.
- Reuse one persistent Codex terminal session per project root.
- Reuse one free Codex terminal outside projects.
- Replace the free session when reopening Codex from a different non-project location.
- Keep project sessions alive until they are explicitly removed or Neovim exits.

### Project model

A project is defined as:

- `name`: display name in pickers and UI
- `root`: absolute root directory

The plugin will provide:

- add/remove project managemennt
- project lookup by current file or working directory
- persistent project storage
- a Snacks picker for switching the active project

### Tab-local behavior

State is local to each tab page.

Each tab may have:

- no active project
- one active project
- at most one visible Codex terminal window

Different tabs may point at different projects.

When the active project changes in a tab while Codex is already visible, the visible terminal window should switch to the session belonging to the newly selected project.

### Project-aware terminal routing

When toggling Codex:

- if the current buffer belongs to a known project, the project root controls the session key and terminal cwd
- if the current tab already has an active project, that project takes precedence for that tab
- if the current buffer does not belong to a project, Codex opens in the cwd of the current file or current working directory

### Git-root project suggestion

When opening a free Codex terminal outside any known project:

- walk upward from the current path
- if a `.git` root is found
- and that root is not already in the project registry
- ask whether it should be added as a new project
- if confirmed, add it and make it active in the current tab

The confirmation UI should use Snacks input/select UX.

## Prompt Expansion

A later goal of the plugin is a prompt expansion layer that converts Neovim state into prompt text before sending it to Codex.

The user-facing syntax is based on `&(...)` placeholders.

Examples:

- `&(current file)` -> `@relative/path/to/file.lua`
- `&(range<10, 40>)` -> `@relative/path/to/file.lua (lines 10:40)`
- `&(current line)` -> `@relative/path/to/file.lua (line 18)`
- `&(visible buffer)` -> visible text plus file metadata
- `&(diagnostics)` -> diagnostics rendered relative to the active project root
- `&(qf list)` -> quickfix items rendered into a compact prompt-friendly form

Example prompt:

```text
Fix all &(diagnostics)
```

Before being sent to Codex, the plugin should expand it into a concrete textual prompt derived from editor state.

## Prompt Library / Macros

The prompt system is intended to support a small library of reusable prompt templates.

Examples of future macros:

- `fix-diagnostics`
- `explain-current-file`
- `refactor-selection`
- `summarize-qf`

A macro may expand into plain text and may itself contain `&(...)` placeholders.

## Design Constraints

The implementation is expected to follow these constraints:

- Neovim plugin structure should be conventional and easy to navigate.
- Runtime dependencies should stay minimal.
- Required dependencies:
  - `folke/snacks.nvim`
  - `nvim-lua/plenary.nvim`
  - Codex CLI installed and available as `codex`
- Internal code should be as close to type-safe OOP-style Lua as is practical.
- Style should track the conventions used in `snacks.nvim`:
  - small focused modules
  - class-like tables with `__index`
  - explicit config/default merging
  - LuaLS annotations for public types and methods
  - lazy module loading where it helps keep the public API small

## Installation

Using `lazy.nvim`:

```lua
{
  "AlexanderGolys/codex-cli.nvim",
  dependencies = {
    "folke/snacks.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {
    codex_cmd = { "codex" },
  },
}
```

## Planned Configuration

```lua
require("codex-cli").setup({
  codex_cmd = { "codex" },
  storage = {
    projects_file = vim.fn.stdpath("data") .. "/codex-cli/projects.json",
    prompts_dir = vim.fn.stdpath("data") .. "/codex-cli/prompts",
  },
  terminal = {
    shell = "bash",
    win = {
      position = "right",
      width = 0.35,
    },
  },
  project_detection = {
    auto_suggest_git_root = true,
  },
  state_preview = {
    width = 48,
  },
})
```

Final option names may shift slightly, but the behavior above is the target.

## Planned Commands

The exact command surface may still change, but the expected workflow is centered around commands like:

- `:CodexToggle`
- `:CodexStateToggle`
- `:CodexProjectSelect`
- `:CodexProjectAdd`
- `:CodexProjectRemove`
- `:CodexPromptExpand`

## Proposed Architecture

The plugin is intended to be split into focused modules instead of a single `init.lua` file.

```text
lua/codex-cli/
  init.lua                -- public API facade
  config.lua              -- defaults and option merging
  app.lua                 -- top-level orchestrator
  commands.lua            -- user command registration
  project/
    project.lua           -- project model
    registry.lua          -- persistent project list
    detector.lua          -- current-path and git-root detection
    picker.lua            -- Snacks picker integration for project selection
  terminal/
    session.lua           -- persistent Codex terminal session
    manager.lua           -- project/free session lifecycle
  tab/
    state.lua             -- tab-local active project + visible terminal state
    manager.lua           -- tab state lookup and cleanup
  prompt/
    context.lua           -- extract editor state
    expander.lua          -- substitute &(...) placeholders
    library.lua           -- prompt templates and macros
    renderers/
      buffer.lua          -- current file, line, range, visible region
      diagnostics.lua     -- diagnostics rendering
      quickfix.lua        -- quickfix rendering
  ui/
    input.lua             -- Snacks-backed input/select helpers
  util/
    fs.lua                -- path and persistence helpers
    git.lua               -- git root detection helpers
    notify.lua            -- consistent notifications
plugin/
  codex-cli.lua           -- plugin bootstrap and commands
doc/
  codex-cli.txt           -- vim help once the API is stable
```

## Core Invariants

The session model should preserve these invariants:

1. There is at most one Codex session per project root.
2. There is at most one free Codex session outside projects.
3. Reopening the free session from another location destroys the old free session and starts a new one.
4. Project sessions are not destroyed during normal toggling.
5. Each tab has its own active-project pointer.
6. Each tab has at most one visible Codex terminal window.
7. Switching the active project in a tab swaps the visible Codex buffer for that tab.

## Development Notes

Recommended validation while implementing:

```bash
nvim --headless "+lua require('codex-cli').setup()" +qa
nvim --headless "+lua print(vim.inspect(require('codex-cli')))" +qa
```

For an isolated runtime with only `lazy.nvim`, `snacks.nvim`, and this plugin loaded:

```bash
./bin/codex-nvim-clean
```

That launcher uses [dev/nvim/init.lua](/home/flux/nvim-plugins/codex-cli/dev/nvim/init.lua) and repo-local XDG cache/data/state directories so it does not load your normal Neovim config.

Manual runtime checks should focus on:

- toggling inside and outside projects
- switching projects with Codex visible
- reopening the free session from a different cwd
- tab-local active-project behavior
- prompt expansion edge cases for diagnostics, quickfix items, and ranges

## Roadmap

### Phase 1

- module layout
- config and persistence
- project registry
- tab-local state
- Codex terminal session manager

### Phase 2

- Snacks picker and input flows
- git-root project suggestion
- stable commands and help docs

### Phase 3

- prompt expansion engine
- prompt macro library
- text renderers for diagnostics, ranges, visible content, and quickfix lists

## License

MIT
