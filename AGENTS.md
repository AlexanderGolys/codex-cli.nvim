# Repository Guidelines

## Project Structure & Module Organization
- Runtime code lives under `lua/clodex/`; keep public entrypoints thin and behavior-heavy code in focused modules.
- Bootstrap stays in `plugin/clodex.lua`.
- Core module groups are `app/`, `execution/`, `project/`, `prompt/`, `session/`, `tab/`, `terminal/`, `ui/`, `util/`, and `workspace/`.
- The bundled MCP helper lives in `rust/clodex-mcp/`.
- Checked-in workflow skill content lives in `.codex/skills/prompt-nvim-clodex/` and is synced into project-local `.clodex/skills/` at runtime.
- Durable per-project user files may include root `README.md` and `TODO.md` plus `.clodex/` queue data.
- Tests live in `tests/specs/` and use `tests/minimal_init.lua`.
- Keep project-local agent data under each repository's `.clodex/` directory; avoid new global state unless it is explicitly plugin-global config/runtime data.

## Product Rules
- Treat `snacks.nvim` as required infrastructure.
- Support the two interactive backends that exist today: Codex and OpenCode.
- Keep one persistent session per registered project root and one shared free session rooted at `session.free_root`.
- Project sessions always start with `cwd = project.root`; the free session always starts with `cwd = session.free_root`.
- Keep queue and workspace summaries focused on durable repository facts plus queue contents; do not reintroduce inferred live task tracking.
- Keep queued workflow behavior centered on project-local queue files and the local MCP helper.
- Default queued git workflow stays commit-based unless a task explicitly needs branch-and-PR behavior.

## Style Guidelines
- Use 4-space indentation.
- Prefer short functions, early returns, and small focused locals.
- Use trailing commas in multiline tables.
- Prefer `string.format` or `:format` over manual concatenation when it improves clarity.
- Export one focused table per file.
- Use class-like tables with `__index` and explicit `.new(...)` constructors for stateful modules.
- Add LuaLS annotations for public classes, config shapes, params, and returns.
- Use `snake_case` for functions and fields.
- Keep public APIs meaningful; do not expose thin helper wrappers.
- Prefer self-documenting code, but when logic is still not obvious after naming/structure cleanup, add a short comment explaining what the code is doing or why the layout/math works that way.
- Keep generic reusable helpers in `lua/clodex/util.lua` or `lua/clodex/util/*.lua`.
- Prefer internal local helpers first, shared helpers second, and new public helpers last.
- Do not introduce magic constants; keep defaults centralized in `lua/clodex/config.lua` or name local constants clearly.
- In Lua, prefer typed config tables for related layout/tuning values instead of long runs of standalone local constants; that pattern is harder to read and maintain here than in statically typed codebases.

## Documentation Rules
- Keep `README.md` aligned with the real command set, config defaults, queue workflow, and shipped files.
- Keep `AGENTS.md` aligned with the current module layout, project files, and maintenance rules.
- When queued workflow behavior changes, update both `README.md` and `.codex/skills/prompt-nvim-clodex/SKILL.md`.
- Remove stale docs and obsolete private workflow references instead of documenting dead paths.

## Build, Test, and Development Commands
- Plugin load check: `nvim --headless "+lua require('clodex').setup()" +qa`
- Export sanity check: `nvim --headless "+lua print(vim.inspect(require('clodex')))" +qa`
- Focused spec: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/specs/<name>_spec.lua" +qa`
- Full suite: `bash bin/clodex-nvim-test`
- MCP helper build: `cargo build --release --manifest-path rust/clodex-mcp/Cargo.toml`

## Testing Guidelines
- Add or update focused specs for behavior changes.
- Cover setup/config merging, commands/public API stability, queue transitions, and session lifecycle edge cases.
- Add regression coverage for bug fixes.
- Prefer one focused spec file per module or behavior when practical.

## Cleanup Rules
- Remove obsolete files and dead code instead of keeping compatibility shims that no longer serve the project.
- Reuse existing helpers before adding new abstractions.
- If a helper becomes unused after a refactor, delete it.
- Do not keep broken private scripts or duplicated checked-in artifacts.

## Commit & Pull Request Guidelines
- Follow the existing imperative commit style.
- Keep commits focused.
- PRs should explain what changed, why, any backend/dependency assumptions, and how the change was validated.
