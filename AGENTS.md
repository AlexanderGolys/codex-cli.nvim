# Repository Guidelines

Style guidance for this repository lives in `STYLE_GUIDELINES.md`.

## Project Structure & Module Organization
- Core plugin code lives under `lua/codex-cli/`.
- Public entrypoints should stay thin and delegate to focused modules.
- Root files:
  - `README.md`: user-facing setup and architecture notes.
  - `LICENSE`: MIT license.
  - `.gitignore`: local/editor/runtime ignores.
- Runtime bootstrap should live under `plugin/`.
- As features expand, keep modules focused by domain (`project/`, `terminal/`, `tab/`, `prompt/`, `ui/`, `util/`).

## Build, Test, and Development Commands
- This repo does not define a `Makefile` or package manager scripts yet.
- Use Neovim headless checks while developing:
  - `nvim --headless "+lua require('codex-cli').setup()" +qa` validates plugin load.
  - `nvim --headless "+lua print(vim.inspect(require('codex-cli')))" +qa` sanity-checks exports.
- Manual runtime test: install with `lazy.nvim`, then run `:CodexToggle`.

## Testing Guidelines
- Automated tests are not present yet; add tests as new behavior lands.
- Recommended test layout: `tests/` with one spec per module.
- Cover at least:
  - `setup()` option merging behavior.
  - Public API stability.
  - Project detection and session lifecycle edge cases.

## Commit & Pull Request Guidelines
- Follow the existing imperative style seen in history, e.g.:
  - `Init: add basic plugin structure with lua/codex-cli/init.lua`
  - `Add MIT license and .gitignore`
- Keep commits focused and scoped to one change.
- PRs should include:
  - What changed and why.
  - Any Neovim version/dependency assumptions (for example `snacks.nvim`).
  - Manual validation steps and outcomes.
  - Screenshots or terminal snippets when UI/interaction changes.
