# codex-cli.nvim

Neovim plugin integrating codex CLI with snacks terminal, providing intelligent prompt generation from buffer context, diagnostics, and quickfix lists.

## Features

- **Snacks Terminal Integration** — Run codex CLI inside Neovim via snacks terminal
- **Project Manager** — Manage codex sessions and context per project
- **Smart Prompt Generation**:
  - Current buffer context (selected code)
  - LSP diagnostics (errors, warnings, info)
  - Quickfix list (search results, build errors)
  - File metadata (type, language, project info)

## Installation

Using lazy.nvim:

```lua
{
  "spectral-flux/codex-cli.nvim",
  config = function()
    require("codex-cli").setup({
      -- Config here
    })
  end,
}
```

## Usage

(TBD — to be implemented)

## Architecture

- **Terminal Integration** — snacks.nvim for terminal UI
- **Context Engine** — Extracts buffer, diagnostics, quickfix data
- **Session Manager** — Tracks codex CLI sessions per project
- **Prompt Builder** — Constructs intelligent prompts from context

## Development

Status: Active development
