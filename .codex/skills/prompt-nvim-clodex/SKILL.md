---
name: prompt-nvim-clodex
description: Handle clodex.nvim-managed queued work by updating the local project queue files after implementation.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`, or when you are doing normal project work inside a repository managed by clodex.nvim and need to record the outcome in that project's local queue history.

When the prompt provides a queue item id or tells you to use the Clodex queued-work MCP loop:

1. Use the `clodex` MCP server as the primary queue interface.
2. Call `get_task` for the current repository root to claim or resume the active queued task.
3. If `get_task` returns `status = done`, stop; the queue is exhausted.
4. Otherwise, implement the returned `work_prompt`.
5. Before any successful close, update relevant `README.md` content and agent/context files so they describe the current behavior, workflow, and user-facing changes introduced by the work.
6. For the current commit-based workflow, a successful close usually requires a focused git commit and a closure payload with `success`, `comment`, and `commit_id`.
   - Exception: `idea` prompts are planning-only. They should generate follow-up prompts or plans without changing code and should close with an empty `commit_id`.
7. Call `close_task` after the work is finished:
   - on success, use `success = true`, a short completion comment, and the new `commit_id`
   - on failure or blocker, use `success = false` and provide the blocker note in `comment`
8. If `close_task` returns another task, continue immediately with that task in the same loop.
9. If `close_task` returns `status = done`, stop; queued work is finished.
10. Only fall back to editing `.clodex/*.json` queue files directly when the `clodex` MCP server is unavailable in the session.

# Manual History

For normal project work outside queued prompt execution:

1. Update the project-local queue files under `.clodex/` after the work is complete.
2. Before any commit, update relevant `README.md` content and agent/context files so they describe the current behavior, workflow, and user-facing changes introduced by the work.
3. Add a new item to the front of `.clodex/history.json` unless the newest matching history item already represents the same completed task, in which case update it in place.
4. Do not modify unrelated items in `.clodex/planned.json`, `.clodex/queued.json`, or `.clodex/implemented.json`.
5. Normalize obvious typos in the user request before you turn it into a title, prompt, or summary.
6. Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation.
7. Use a concise `title` that describes the completed task.
8. Set `kind` to `bug` for bug fixes or regressions, otherwise use the closest existing queue category such as `todo`, `refactor`, `freeform`, `idea`, or `ask`.
9. Set `details` when extra context from the user request matters later; otherwise leave it unset.
10. Set `prompt` to a clean plain-text version of the request that could have been queued manually.
11. Set `history_summary` to a short summary of what changed or what blocker remains.
12. If the project is in git and you changed code, create a focused commit for that completed task and set `history_commits` to an array containing that new commit id; otherwise leave it unset.
13. Set `history_completed_at` and `updated_at` to a UTC timestamp like `2026-03-13T16:40:17Z`.
14. If you create a new history item, also set `created_at` and include a non-empty `id`; a generated unique string is fine.
15. Preserve existing items instead of rewriting the whole file unnecessarily.

Only create or update a history record when the conversation actually resulted in project work worth remembering. Do not create history items for pure discussion, exploration, or no-op answers.
