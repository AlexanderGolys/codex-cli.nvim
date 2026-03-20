---
name: prompt-nvim-clodex
description: Handle clodex.nvim-managed queued work by updating the local project queue files after implementation.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`, or when you are doing normal project work inside a repository managed by clodex.nvim and need to record the outcome in that project's local queue history.

When the prompt provides a queue item id and prompt kind before the skill call:

1. Finish the requested work first.
2. If the prompt kind is `ask`, do not create a commit for this queue item.
3. If the prompt kind is `freeform`, decide whether a commit is warranted based on the work you actually did. Create a focused git commit only when the result meaningfully changed project files and would be useful to preserve in git history. If the project root is not a git repository, skip the commit step and leave `history_commits` unset.
4. For any other prompt kind, create a focused git commit before you update the queue item when the project root is git-backed. If the project root is not a git repository, skip the commit step and leave `history_commits` unset.
5. When the `clodex` MCP server is available in the session, use its queue tools instead of ad-hoc JSON editing or one-off Python scripts:
   - use `queue_complete_current` to record `summary`, `commit`/`commits`, and optional `completion_target`
   - use `queue_fail_current` if the active item must return to `queued`
6. If the MCP server is unavailable, fall back to updating the project-local queue files directly from the current repository root under `.clodex/`:
   - `.clodex/planned.json`
   - `.clodex/queued.json`
   - `.clodex/implemented.json`
   - `.clodex/history.json`
7. Update queue state only after the implementation work is complete.
8. If the prompt also says `Completion destination for this prompt: history`, skip the implemented-review stop and move the completed item directly into `.clodex/history.json` after recording its completion metadata.
9. If the prompt also says `Completion destination for this prompt: agent_decides` and the prompt kind is `freeform`, decide whether the finished result belongs in `.clodex/implemented.json` or `.clodex/history.json`. Use `history` when the prompt is fully resolved by the conversation itself, and `implemented` when it produced an intermediate or reviewable outcome that should remain in the implemented lane first.
10. Find the queue item with the provided id in `.clodex/queued.json`, `.clodex/implemented.json`, or `.clodex/history.json`.
11. If it is still in `.clodex/queued.json`, remove it from there and add the same item to the front of `.clodex/implemented.json` without changing its `id`, unless the prompt explicitly requires direct completion to history or you decided to move a `freeform` prompt directly to history.
12. If it is already in `.clodex/implemented.json`, update it in place.
13. If it is already in `.clodex/history.json`, update it in place instead of duplicating it.
14. Set `history_summary`, `history_commits` (array of commit ids) when commits exist, `history_completed_at`, and refresh `updated_at`.
15. Preserve `execution_instructions` on queued items. Do not show or rewrite that hidden field unless the task explicitly requires it.
15. After updating the current item, inspect `.clodex/queued.json`. If another queued item remains, continue immediately with the next queued item and repeat this workflow.
16. Each next queued item already includes the same hidden execution instructions, so rely on the current prompt's instructions again instead of trying to remember the whole loop from earlier in the session.
17. Repeat until `.clodex/queued.json` is empty. Do not start prompts that are only in `.clodex/planned.json` or `.clodex/implemented.json`.

# Manual History

For normal project work outside queued prompt execution:

1. Update the project-local queue files under `.clodex/` after the work is complete.
2. Add a new item to the front of `.clodex/history.json` unless the newest matching history item already represents the same completed task, in which case update it in place.
3. Do not modify unrelated items in `.clodex/planned.json`, `.clodex/queued.json`, or `.clodex/implemented.json`.
4. Normalize obvious typos in the user request before you turn it into a title, prompt, or summary.
5. Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation.
6. Use a concise `title` that describes the completed task.
7. Set `kind` to `bug` for bug fixes or regressions, otherwise use the closest existing queue category such as `todo`, `refactor`, `freeform`, `idea`, or `ask`.
8. Set `details` when extra context from the user request matters later; otherwise leave it unset.
9. Set `prompt` to a clean plain-text version of the request that could have been queued manually.
10. Set `history_summary` to a short summary of what changed or what blocker remains.
11. If the project is in git and you changed code, create a focused commit for that completed task and set `history_commits` to an array containing that new commit id; otherwise leave it unset.
12. Set `history_completed_at` and `updated_at` to a UTC timestamp like `2026-03-13T16:40:17Z`.
13. If you create a new history item, also set `created_at` and include a non-empty `id`; a generated unique string is fine.
14. Preserve existing items instead of rewriting the whole file unnecessarily.

Only create or update a history record when the conversation actually resulted in project work worth remembering. Do not create history items for pure discussion, exploration, or no-op answers.
