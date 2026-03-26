# clodex.nvim

Project-aware Codex and OpenCode workflows for Neovim.

`clodex.nvim` keeps one persistent terminal session per registered project root, one shared free session outside registered projects, and a project-local `.clodex/` workspace for queue data, notes, bookmarks, and execution metadata.

## What it does

- Reuses long-lived `codex` and `opencode` terminal sessions instead of disposable shells.
- Tracks an active project per tab while sharing the same session for the same project root.
- Builds prompts from editor context such as the current file, selection, line, and diagnostics.
- Opens a queue workspace for planning, queuing, dispatching, and reviewing project work.
- Shows hidden sessions that are waiting for input in a floating blocked-input window.
- Ships a local Rust MCP helper in `rust/clodex-mcp/` for queue-aware task loops.

## Requirements

- Neovim 0.10+
- `snacks.nvim`
- `codex` and/or `opencode`
- `cargo` if you want to build the bundled MCP helper

## Installation

With `lazy.nvim`:

```lua
{
    "AlexanderGolys/clodex.nvim",
    build = "cargo build --release --manifest-path rust/clodex-mcp/Cargo.toml",
    dependencies = {
        "folke/snacks.nvim",
    },
    opts = {},
}
```

Minimal setup:

```lua
require("clodex").setup()
```

## Default config

```lua
require("clodex").setup({
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
        blocked_input = {
            enabled = true,
            poll_ms = 1000,
            win = {
                position = "float",
                width = 0.72,
                height = 0.8,
                border = "rounded",
            },
        },
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
        mini = {
            width = 42,
            height = 11,
            col = 2,
            winblend = 0,
        },
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
    prompt_execution = {
        receipts_dir = ".clodex/prompt-executions",
        poll_ms = 5000,
        skills_dir = ".clodex/skills",
        skill_name = "prompt-nvim-clodex",
        git_workflow = "commit",
    },
    mcp = {
        enabled = true,
        cmd = {},
        runtime_dir = vim.fn.stdpath("data") .. "/clodex/mcp",
    },
    session = {
        persist_current_project = true,
        free_root = vim.fn.expand("~"),
    },
    keymaps = {
        toggle = { lhs = "<leader>pt" },
        queue_workspace = { lhs = "<leader>pq" },
        state_preview = { lhs = "<leader>ps" },
        mini_state_preview = { lhs = "<leader>pS" },
        backend_toggle = { lhs = "<leader>pb" },
    },
})
```

## Prompt kinds

- `improvement` (`todo`)
- `bug`
- `fix` (`freeform`)
- `feature`
- `restructure` (`refactor`)
- `vision` (`idea`)
- `clean-up` (`cleanup`)
- `missing-docs` (`docs`)
- `ask`
- `notworking`

Legacy queue items and command aliases using `todo`, `freeform`, `adjustment`, `refactor`, `idea`, `cleanup`, `docs`, and `explain` are still accepted and mapped to the current prompt kinds.

`vision` prompts are planning-only and should produce plans or follow-up prompts instead of repository changes.

## Commands

- `:Clodex[ panel|cli|term|chat|history|backend [codex|opencode]|header]`
- `:ClodexDebug[ panel|mini|reload]`
- `:ClodexProject add [name]`
- `:ClodexProject readme`
- `:ClodexProject todo`
- `:ClodexProject dictionary`
- `:ClodexProject cheatsheet`
- `:ClodexProject cheatsheet-panel`
- `:ClodexProject cheatsheet-add`
- `:ClodexProject notes`
- `:ClodexProject note-add`
- `:ClodexProject bookmarks`
- `:ClodexProject bookmark-add`
- `:ClodexTodo [bug|implement|all] [for|project]`
- `:ClodexPrompt [kind] [for|project]`
- `:ClodexPromptFile [kind]`

Use `:'<,'>ClodexPrompt ...` from visual mode to seed prompt context from the selected range.

## Queue workflow

- `planned`: captured work not ready to run yet
- `queued`: ready to dispatch
- `implemented`: dispatched and finished, waiting for review unless completion goes straight to history
- `history`: verified or directly completed work with summary and commit metadata

Queued execution uses project-local skills under `.clodex/skills/` together with the checked-in `prompt-nvim-clodex` workflow in `.codex/skills/prompt-nvim-clodex/SKILL.md`. When the MCP helper is available, queued work runs through the local `get_task` / `close_task` loop, runs compaction before starting each newly returned task, and can also create follow-up prompts through `create_prompt`. If MCP is unavailable, the workflow falls back to editing the same `.clodex/*.json` files directly.

### MCP tools

- `get_task`: high-level queued-work entrypoint; claims or resumes the active item and returns the next `work_prompt`
- `close_task`: high-level queued-work closer; records success or failure and advances the loop when another queued item exists
- `create_prompt`: creates a follow-up prompt item, usually when an `ask` or planning task turns into actionable work
- `queue_status`: read-only queue inspection for UI/debug surfaces that need queue counts or active-state visibility, not for normal prompt-by-prompt task execution

Typical patterns:

- normal queued loop: `get_task` -> implement -> commit -> `close_task(success = true, comment, commit_id)`
- blocked queued loop: `get_task` -> investigate -> `close_task(success = false, comment)`
- MCP-driven delegation loop: `get_task` -> implement -> `close_task` -> MCP either returns the next task or reports that no queued work remains
- planning follow-up: finish an `ask`/discussion item, then use `create_prompt` to queue the next concrete task

The prompt creator keeps footer actions visible, docks the target-project picker on the left, preserves compatible drafts across kind switches, and can preview attached clipboard images in a separate pane. `Ctrl-S`, `Ctrl-Q`, `Ctrl-E`, and `Ctrl-L` plan, queue, run immediately, or send straight to the live chat. Immediate direct execution currently works only with the Codex backend.

In the queue workspace project panel, press `I` to set, change, or remove a custom project icon through `snacks.picker.icons()`.

## Project files

Clodex keeps durable project data inside each repository:

- `README.md`
- `TODO.md`
- `.clodex/planned.json`
- `.clodex/queued.json`
- `.clodex/implemented.json`
- `.clodex/history.json`
- `.clodex/skills/`
- `.clodex/PROJECT_DICTIONARY.md`
- `.clodex/cheatsheet.md`
- `.clodex/notes/`
- `.clodex/bookmarks.json`

Global plugin state stays under `stdpath("data")/clodex/`, including the project registry, session snapshots, MCP runtime config, and the optional history markdown log.

## Public API

Main entrypoints live in `lua/clodex/init.lua`:

- `require("clodex").setup(opts)`
- `require("clodex").toggle()`
- `require("clodex").toggle_state_preview()`
- `require("clodex").toggle_mini_state_preview()`
- `require("clodex").toggle_backend()`
- `require("clodex").toggle_terminal_header()`
- `require("clodex").add_project(opts)`
- `require("clodex").rename_project(name)`
- `require("clodex").remove_project(value)`
- `require("clodex").clear_active_project()`
- `require("clodex").open_queue_workspace()`
- `require("clodex").open_history()`
- `require("clodex").open_project_readme_file(project)`
- `require("clodex").open_project_todo_file(project)`
- `require("clodex").open_project_dictionary_file(project)`
- `require("clodex").open_project_cheatsheet_file(project)`
- `require("clodex").toggle_project_cheatsheet_preview(project)`
- `require("clodex").add_project_cheatsheet_item(project)`
- `require("clodex").open_project_notes_picker(project)`
- `require("clodex").create_project_note(project)`
- `require("clodex").add_project_bookmark(project)`
- `require("clodex").open_project_bookmarks_picker(project)`
- `require("clodex").add_todo(opts)`
- `require("clodex").add_bug_todo(opts)`
- `require("clodex").add_prompt(opts)`
- `require("clodex").add_prompt_for_project(opts)`
- `require("clodex").add_prompt_for_current_file_project(opts)`
- `require("clodex").implement_next_queued_item(opts)`
- `require("clodex").implement_all_queued_items(opts)`

Statusline helpers:

- `require("clodex").lualine.project(opts)`
- `require("clodex").lualine.project_name(opts)`

## Development

Useful checks:

```bash
nvim --headless "+lua require('clodex').setup()" +qa
nvim --headless "+lua print(vim.inspect(require('clodex')))" +qa
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/specs/config_spec.lua" +qa
bash bin/clodex-nvim-test
cargo build --release --manifest-path rust/clodex-mcp/Cargo.toml
```

Core runtime code lives under `lua/clodex/` and `plugin/clodex.lua`. The bundled MCP helper lives under `rust/clodex-mcp/`. Checked-in workflow instructions live under `.codex/skills/`. Tests live under `tests/specs/`.

## License

MIT. See `LICENSE`.
