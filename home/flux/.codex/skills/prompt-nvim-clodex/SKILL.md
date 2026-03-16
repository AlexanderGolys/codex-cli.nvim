---
name: prompt-nvim-clodex
description: Handle clodex.nvim queued prompt executions by updating the local workspace queue file when the work is complete.
---

# Queue Completion

Use this skill when a prompt includes `$prompt-nvim-clodex`.

When the prompt provides a project workspace path and queued item id before the skill call:

1. Finish the requested work first.
2. Update the exact workspace JSON file provided by the prompt only after the work is complete.
3. Find the queue item with the provided id in `queues.queued`.
4. Move that same item into `queues.history` without changing its `id`.
5. Set `history_summary`, `history_commit` when available, `history_completed_at`, and refresh `updated_at`.
6. If the item is already in `queues.history`, update it in place instead of duplicating it.
7. If more prompts are waiting in the project's workspace file under `queues.queued`, continue with the next queued prompt immediately after finishing the current one.
8. Repeat until `queues.queued` is empty. Do not start prompts that are only in `queues.planned`.
