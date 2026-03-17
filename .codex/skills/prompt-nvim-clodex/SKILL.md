---
name: prompt-nvim-clodex
description: Handle clodex.nvim queued prompt executions by updating the local workspace queue file when the work is complete.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`.

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
