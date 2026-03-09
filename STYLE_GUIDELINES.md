# Style Guidelines

## Scope

These rules are derived from `snacks.nvim`, with the strongest influence coming from:

- `lua/snacks/init.lua`
- `lua/snacks/win.lua`
- `lua/snacks/terminal.lua`
- `lua/snacks/input.lua`
- `lua/snacks/picker/select.lua`
- `lua/snacks/util/init.lua`

They are the default style rules for all code in this repository.

## Formatting

- Use 2-space indentation.
- Prefer short functions with early returns.
- Use trailing commas in multiline tables.
- Keep top-level locals small and focused.
- Prefer direct string formatting with `string.format` or `:format`.

## Module Shape

- Export one focused table per file.
- Stateful modules should use class-like tables with `__index` and explicit `.new(...)` constructors.
- Public entry modules may expose a small facade with lazy `require(...)` calls.
- Prefer narrow modules over large mixed-responsibility files.

## Typing And Docs

- Add LuaLS annotations for public classes, config shapes, method params, and returns.
- Use explicit aliases when a table represents a constrained data shape.
- Distinguish records, classes, and ad-hoc maps in annotations.

## Naming

- Use `snake_case` for functions and fields.
- Use descriptive singular class names for model objects.
- Keep file names aligned with the module responsibility.
- Use consistent prefixes for related types, such as `CodexCli.*`.

## Architecture

- Keep public API thin and move behavior into internal modules.
- Separate models, managers, UI helpers, and filesystem utilities.
- Make config merging explicit instead of scattering defaults.
- Avoid hidden global state except for a deliberate app singleton.

## Runtime Behavior

- Prefer Neovim-native APIs and small helpers over heavy abstractions.
- Reuse persistent objects when the feature requires stable identity.
- Use `vim.notify` through a small wrapper so user-facing messages stay consistent.
- Preserve buffers where workflow depends on session continuity; destroy them only when the product behavior explicitly requires it.

## Prescriptive Rules

- New code in this repository should follow the class-like module pattern used in the implementation scaffold.
- Public config must be centralized in `lua/codex-cli/config.lua`.
- Cross-cutting helpers belong under `lua/codex-cli/util/`.
- UI adapters for Snacks belong under `lua/codex-cli/ui/`.
- Avoid mixing prompt-generation features into project/session modules.
- Do not use `goto` in any language used in this repository.
- Do not introduce magic constants. Numeric literals must be one of:
  - obvious protocol/Neovim sentinel values (`0`, `1`, `-1`) used directly with APIs,
  - documented defaults in centralized config,
  - named local/module-level constants with descriptive identifiers.
