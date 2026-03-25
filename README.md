# clodex.nvim

Project-aware Codex/OpenCode workflows for Neovim.

`clodex.nvim` keeps one persistent terminal session per registered project, one shared free session outside projects, and a project-local `.clodex/` workspace for queued prompts, notes, bookmarks, and execution metadata.

## What it does

- Keeps long-lived terminal buffers for `codex` or `opencode` instead of spawning disposable shells.
- Tracks the active project per tab while reusing the same backing session for the same project root.
- Stores queue state per project in `.clodex/{planned,queued,implemented,history}.json`.
- Builds prompts from editor context such as the current file, line, selection, and diagnostics.
- Opens a queue workspace for moving, editing, dispatching, and reviewing prompts.
- Surfaces hidden sessions that are waiting for user input in a floating terminal.
- Ships a local Rust MCP helper in `rust/clodex-mcp/` for queue-aware prompt completion.

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
            winblend = 28,
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

- `todo`
- `bug`
- `freeform`
- `refactor`
- `idea`
- `ask`
- `library`
- `notworking`

Legacy queue items using `adjustment` and `explain` are still accepted and mapped to `freeform` and `ask` behavior.

`idea` prompts are planning-only: they should generate follow-up prompts or implementation plans without changing repository code.

## Commands

- `:Clodex` or `:Clodex panel`
- `:Clodex cli`
- `:Clodex history`
- `:Clodex backend [codex|opencode]`
- `:Clodex header`
- `:ClodexDebug panel`
- `:ClodexDebug mini`
- `:ClodexDebug reload`
- `:ClodexProject add [name]`
- `:ClodexProject readme`
- `:ClodexProject dictionary`
- `:ClodexProject cheatsheet`
- `:ClodexProject cheatsheet-panel`
- `:ClodexProject cheatsheet-add`
- `:ClodexProject notes`
- `:ClodexProject note-add`
- `:ClodexProject bookmarks`
- `:ClodexProject bookmark-add`
- `:ClodexTodo [for|project]`
- `:ClodexTodo bug [for|project]`
- `:ClodexTodo implement [for|project]`
- `:ClodexTodo all [for|project]`
- `:ClodexPrompt [kind] [for|project]`
- `:ClodexPromptFile [kind]`

Use `:'<,'>ClodexPrompt ...` from visual mode to seed prompt context from the selected range.

## Queue workflow

- `planned`: captured work not ready to run yet
- `queued`: ready to dispatch
- `implemented`: dispatched and finished, waiting for review unless completion goes straight to history
- `history`: verified or directly completed work with summary/commit metadata

Queued execution uses project-local skills under `.clodex/skills/` and the bundled `prompt-nvim-clodex` workflow instructions. When the MCP helper is available, queued work runs through the local `get_task` / `close_task` loop so the agent can keep claiming the next queued item until the project queue is exhausted; the same helper also exposes `create_prompt` for dropping new planned or queued follow-up prompts straight into `.clodex/*.json` after a planning discussion. Otherwise it falls back to editing the same `.clodex/*.json` files directly.

The unified prompt creator keeps footer actions visible at all times. A target-project picker now stays docked on the left and defaults to the active project for the current tab; use `Up`/`Down` there to change the target, `Right` to jump back into the editor, and `Left` or `Shift-Tab` from the first input to move back to the project list. Use `</>` to switch prompt kinds, `[/]` to switch bug-source tabs, `Ctrl-V` to replace the attached clipboard image, and `Ctrl-S`, `Ctrl-Q`, `Ctrl-E`, or `Ctrl-L` to plan, queue, run immediately, or send straight to the live project chat. Draft text now follows you across kind and bug-source tabs whenever the destination exposes the same input, and hidden fields are cached until you return to a compatible editor. Attached clipboard images are previewed in a separate pane docked to the right of the creator. Closing the queue workspace also clears any project or prompt filters so the next open starts from the full list again. Immediate direct execution currently works only with the Codex backend.

In the queue workspace project panel, press `I` to set, change, or remove a custom project icon through `snacks.picker.icons()`. The chosen icon is then shown next to that project in left-side project lists.

## Project files

Clodex keeps durable project data inside each repository:

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
```

Core runtime code lives under `lua/clodex/` and `plugin/clodex.lua`. The bundled MCP helper lives under `rust/clodex-mcp/`. Tests live under `tests/specs/`.

## License

MIT. See `LICENSE`.

 &&&ClodexPromptTodoTitleActive&&&  TODO  &&&  &&&DiagnosticVirtualTextWarn&&&Prompt title
a&&&Lorem ipsum dolor sit amet, consectetur adipiscing elit,
    sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
 &&&ClodexPromptTodoTitleActive&&&  TODO  &&&  &&&@constructor&&&Prompt title&&&
    Lorem ipsum dolor sit amet, consectetur adipiscing elit,
    sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
