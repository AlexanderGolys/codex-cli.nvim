---
name: prompt-nvim-clodex
description: Handle clodex.nvim-managed project work by updating the local workspace queue file when implementation is completed or when direct project work should be remembered in history.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`, or when you are doing normal project work inside a repository managed by clodex.nvim and need to record the outcome in that project's workspace history.

When the prompt provides a queue item id and prompt kind before the skill call:

1. Finish the requested work first.
2. If the prompt kind is `ask`, do not create a commit for this queue item.
3. For any other prompt kind, create a focused git commit before you update the queue item when the project root is git-backed. If the project root is not a git repository, skip the commit step and leave `history_commit` unset.
4. Resolve the project-local workspace JSON file from the current repository root as `.clodex/workspaces/<sha256(project_root):sub(1, 16)>.json`, then update that file only after the work is complete.
5. Find the queue item with the provided id in `queues.queued`, `queues.implemented`, or `queues.history`.
6. If it is still in `queues.queued`, move that same item into `queues.implemented` without changing its `id`.
7. If it is already in `queues.implemented`, update it in place.
8. If it is already in `queues.history`, update it in place instead of duplicating it.
9. Set `history_summary`, `history_commit` when a commit exists, `history_completed_at`, and refresh `updated_at`.
10. If more prompts are waiting in the project's workspace file under `queues.queued`, continue with the next queued prompt immediately after finishing the current one.
11. Repeat until `queues.queued` is empty. Do not start prompts that are only in `queues.planned` or `queues.implemented`.

# Manual History

For normal project work outside queued prompt execution:

1. Update the project-local workspace JSON file after the work is complete.
2. Add a new item to the front of `queues.history` unless the newest matching history item already represents the same completed task, in which case update it in place.
3. Do not modify unrelated `queues.planned`, `queues.queued`, or `queues.implemented` items.
4. Normalize obvious typos in the user request before you turn it into a title, prompt, or summary.
5. Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation.
6. Use a concise `title` that describes the completed task.
7. Set `kind` to `error` for bug fixes or regressions, otherwise use the closest existing queue category such as `todo`, `refactor`, `adjustment`, or `idea`.
8. Set `details` when extra context from the user request matters later; otherwise leave it unset.
9. Set `prompt` to a clean plain-text version of the request that could have been queued manually.
10. Set `history_summary` to a short summary of what changed or what blocker remains.
11. If the project is in git and you changed code, create a focused commit for that completed task and set `history_commit` to that new commit id; otherwise leave it unset.
12. Set `history_completed_at` and `updated_at` to a UTC timestamp like `2026-03-13T16:40:17Z`.
13. If you create a new history item, also set `created_at` and include a non-empty `id`; a generated unique string is fine.
14. Preserve existing items instead of rewriting the whole file unnecessarily.

Only create or update a history record when the conversation actually resulted in project work worth remembering. Do not create history items for pure discussion, exploration, or no-op answers.
