---
name: prompt-nvim-clodex
description: Handle clodex.nvim queued prompt executions by updating the local workspace queue file when the work is complete.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`.

When the prompt provides a project workspace path and queue item id before the skill call:

1. Finish the requested work first.
__CLODEX_COMMIT_STEP__
3. Update the exact workspace JSON file provided by the prompt only after the work is complete.
4. Find the queue item with the provided id in `queues.queued`, `queues.implemented`, or `queues.history`.
5. If it is still in `queues.queued`, move that same item into `queues.implemented` without changing its `id`.
6. If it is already in `queues.implemented`, update it in place.
7. If it is already in `queues.history`, update it in place instead of duplicating it.
8. Set `history_summary`, __CLODEX_COMMIT_FIELD__ `history_completed_at`, and refresh `updated_at`.
9. If more prompts are waiting in the project's workspace file under `queues.queued`, continue with the next queued prompt immediately after finishing the current one.
10. Repeat until `queues.queued` is empty. Do not start prompts that are only in `queues.planned` or `queues.implemented`.
