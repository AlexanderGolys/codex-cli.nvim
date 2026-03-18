---
name: prompt-nvim-clodex
description: Handle clodex.nvim queued prompt executions by updating local project queue files when the work is complete.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`.

When the prompt provides a queue item id and prompt kind before the skill call:

1. Finish the requested work first.
2. If the prompt kind is `ask`, do not create a commit for this queue item.
3. For any other prompt kind, create a focused git commit before you update the queue item when the project root is git-backed. If the project root is not a git repository, skip the commit step and leave `history_commits` unset.
4. Resolve the project-local queue files directly from the current repository root under `.clodex/`:
   - `.clodex/planned.json`
   - `.clodex/queued.json`
   - `.clodex/implemented.json`
   - `.clodex/history.json`
5. Update those queue files only after the implementation work is complete.
6. If the prompt also says `Completion destination for this prompt: history`, skip the implemented-review stop and move the completed item directly into `.clodex/history.json` after recording its completion metadata.
7. Find the queue item with the provided id in `.clodex/queued.json`, `.clodex/implemented.json`, or `.clodex/history.json`.
8. If it is still in `.clodex/queued.json`, remove it from there and add the same item to the front of `.clodex/implemented.json` without changing its `id`, unless the prompt explicitly requires direct completion to history.
9. If it is already in `.clodex/implemented.json`, update it in place.
10. If it is already in `.clodex/history.json`, update it in place instead of duplicating it.
11. Set `history_summary`, `history_commits` (array of commit ids) when commits exist, `history_completed_at`, and refresh `updated_at`.
12. Preserve `execution_instructions` on queued items. Do not show or rewrite that hidden field unless the task explicitly requires it.
13. After updating the current item, inspect `.clodex/queued.json`. If another queued item remains, continue immediately with the next queued item and repeat this workflow.
14. Each next queued item already includes the same hidden execution instructions, so rely on the current prompt's instructions again instead of trying to remember the whole loop from earlier in the session.
15. Repeat until `.clodex/queued.json` is empty. Do not start prompts that are only in `.clodex/planned.json` or `.clodex/implemented.json`.
