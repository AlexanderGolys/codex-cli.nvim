# Repository Guidelines

## Project Structure & Module Organization
- Core plugin code lives under `lua/clodex/`.
- Public entrypoints should stay thin and delegate to focused modules.
- Two fundamental runtime dependencies of this plugin are Codex CLI and `snacks.nvim`.
- Design for environments where both Codex CLI and `snacks.nvim` are installed and working well; do not add fallback architectures for missing core dependencies unless a task explicitly asks for them.
- Treat `snacks.nvim` as required infrastructure and prefer `snacks` APIs directly whenever they fit the problem.
- This plugin is meant to unlock modern cross-project/editor workflows, not to optimize for severely constrained or legacy environments.
- Target the three mainstream desktop OSes people actually use: macOS, Linux, and Windows.
- Do not compromise product direction just to support edge cases like prehistoric hardware, fringe operating systems, read-only working roots, or machines missing easily installable basic tools unless a task explicitly requires that support.
- Do not require Codex CLI agents to have broad/global filesystem access just to complete normal plugin workflows.
- Data exchanged between Neovim and Codex CLI agents should stay project-local under that project's `.clodex/` directory unless a task explicitly requires a different scope.
- Treat a Clodex session as a Neovim terminal buffer plus its live CLI child process, not as any external OS process or backend-native session concept.
- Keep project details and picker/workspace summaries focused on durable repository facts and queue contents; do not reintroduce inferred per-session current-task or run-state tracking there unless a task explicitly requires it.
- There is exactly one project session per registered project root plus one shared free session rooted at the configured `session.free_root`.
- Project sessions must always start with `cwd = project.root`; the free session must always start with `cwd = session.free_root`.
- Avoid growing module APIs around generic wrappers and pass-through helpers. Keep methods in domain modules meaningful and behavior-oriented.
- Generic helper functions are fine, but consolidate broadly reusable ones under `lua/clodex/util.lua` instead of scattering small wrapper APIs across many modules.
- If something is just a wrapper or implementation helper, define it as a local/nested function or move it to `lua/clodex/util.lua`; do not expose it through a module API in that helper-shaped form.
- Root files:
  - `README.md`: user-facing setup and architecture notes.
  - `LICENSE`: MIT license.
  - `.gitignore`: local/editor/runtime ignores.
- Runtime bootstrap should live under `plugin/`.
- As features expand, keep modules focused by domain (`project/`, `terminal/`, `tab/`, `prompt/`, `ui/`, `util/`).

## Style Guidelines
- Use 4-space indentation.
- Prefer short functions with early returns.
- Use trailing commas in multiline tables.
- Keep top-level locals small and focused.
- Prefer direct string formatting with `string.format` or `:format`.
- Export one focused table per file.
- Stateful modules should use class-like tables with `__index` and explicit `.new(...)` constructors.
- Public entry modules may expose a small facade with lazy `require(...)` calls.
- Prefer narrow modules over large mixed-responsibility files.
- Keep public/domain methods meaningful. Avoid filling module APIs with thin wrappers whose only job is to rename or forward helper logic.
- If a function is only a wrapper or implementation helper, keep it local to the module, nest it near the call site when that improves clarity, or move it to `lua/clodex/util.lua` if it is genuinely reusable. Do not expose helper-shaped functions as part of module APIs.
- Add LuaLS annotations for public classes, config shapes, method params, and returns.
- Use explicit aliases when a table represents a constrained data shape.
- Distinguish records, classes, and ad-hoc maps in annotations.
- Use `snake_case` for functions and fields.
- Use descriptive singular class names for model objects.
- Keep file names aligned with the module responsibility.
- Use consistent prefixes for related types, such as `Clodex.*`.
- Keep public API thin and move behavior into internal modules.
- Separate models, managers, UI helpers, and filesystem utilities.
- Make config merging explicit instead of scattering defaults.
- Avoid hidden global state except for a deliberate app singleton.
- Prefer Neovim-native APIs and small helpers over heavy abstractions.
- Treat `snacks.nvim` as required infrastructure for this plugin.
- Prefer `snacks` primitives and adapters over fallback implementations when both could solve the same problem.
- Reuse persistent objects when the feature requires stable identity.
- Use `vim.notify` through a small wrapper so user-facing messages stay consistent.
- Preserve buffers where workflow depends on session continuity; destroy them only when the product behavior explicitly requires it.
- Public config must be centralized in `lua/clodex/config.lua`.
- Cross-cutting helpers belong under `lua/clodex/util.lua`.
- Prefer internal local helpers first. When a helper is generic enough to share, move it to `lua/clodex/util.lua` instead of exposing more wrapper-style methods from unrelated modules.
- UI adapters for Snacks belong under `lua/clodex/ui/`.
- Avoid mixing prompt-generation features into project/session modules.
- Do not use `goto` in any language used in this repository.
- Do not introduce magic constants. Numeric literals must be one of:
  - obvious protocol/Neovim sentinel values (`0`, `1`, `-1`) used directly with APIs,
  - documented defaults in centralized config,
  - named local/module-level constants with descriptive identifiers.

## Build, Test, and Development Commands
- This repo does not define a `Makefile` or package manager scripts yet.
- Use Neovim headless checks while developing:
  - `nvim --headless "+lua require('clodex').setup()" +qa` validates plugin load.
  - `nvim --headless "+lua print(vim.inspect(require('clodex')))" +qa` sanity-checks exports.
- Manual runtime test: install with `lazy.nvim`, then run `:ClodexToggle`.

## Testing Guidelines
- Automated tests are not present yet; add tests as new behavior lands.
- Recommended test layout: `tests/` with one spec per module.
- Cover at least:
  - `setup()` option merging behavior.
  - Public API stability.
  - Project detection and session lifecycle edge cases.

## Commit & Pull Request Guidelines
- Follow the existing imperative style seen in history, e.g.:
  - `Init: add basic plugin structure with lua/clodex/init.lua`
  - `Add MIT license and .gitignore`
- Keep commits focused and scoped to one change.
- PRs should include:
  - What changed and why.
  - Any Neovim version/dependency assumptions (for example `snacks.nvim`).
  - Manual validation steps and outcomes.
  - Screenshots or terminal snippets when UI/interaction changes.
