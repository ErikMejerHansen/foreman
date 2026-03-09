# Plan: Per-Project Knowledge Sharing (Opt-in)

Add an opt-in per-project feature that enriches agent prompts with context about sibling tasks and stores completion summaries for institutional knowledge.

## Changes

### 1. Migration: Add `knowledge_sharing` to projects, `summary` to tasks

Create a new migration that:
- Adds `knowledge_sharing` boolean to `projects` table (default `false`)
- Adds `summary` text to `tasks` table (nullable)

### 2. Update Ecto schemas

**`lib/foreman/projects/project.ex`**:
- Add `field :knowledge_sharing, :boolean, default: false` to schema
- Add `:knowledge_sharing` to `cast/3` in changeset

**`lib/foreman/tasks/task.ex`**:
- Add `field :summary, :string` to schema
- Add `:summary` to `cast/3` in changeset

### 3. Build context enrichment in `Foreman.Tasks`

Add a private function `build_enriched_prompt/2` that:
- Takes a task and its project
- Queries sibling tasks (same project) that are `done` (with summaries) and `in_progress`
- Builds a context block prepended to the task instructions:

```
## Project Context
Recently completed tasks:
- "Task title" — Summary text here
- "Other task" — Summary text here

Currently in progress:
- "Another task"

## Your Task
<original instructions>
```

- Returns the original instructions unchanged if `project.knowledge_sharing` is `false`
- Returns the original instructions unchanged if there are no sibling tasks worth mentioning

Modify `start_agent/4` to call this function when building the prompt (only for fresh starts from `todo`, not for `--resume` from review).

### 4. Generate summaries on task completion

Add a `generate_summary/1` function in `Foreman.Tasks` that:
- Takes a completed task
- Calls `claude` CLI with a cheap, focused prompt: "Summarize what was done in 2-3 sentences" using the task's chat messages as context
- Stores the result in the task's `summary` field

Call this in `move_to_done/1` **after** the merge succeeds but before broadcasting, only when `project.knowledge_sharing` is `true`.

For the summary generation, use a simple `System.cmd("claude", ["-p", prompt, "--max-tokens", "200"])` call (not a full Agent.Runner) to keep it lightweight. The prompt will include the task title, instructions, and a condensed version of the chat messages.

### 5. Add UI toggle on project page

**`lib/foreman_web/live/project_live/show.ex`**:
- Add a toggle/checkbox in the project header area (near the project name) labeled "Knowledge sharing"
- Handle a `"toggle_knowledge_sharing"` event that updates the project's `knowledge_sharing` field via `Projects.update_project/2`

**`lib/foreman/projects.ex`**:
- Add `update_project/2` function if it doesn't exist

### 6. Show summaries on done task cards (optional, lightweight)

On the kanban board, for `done` tasks that have a summary, show the summary text instead of (or in addition to) the instructions snippet. This gives visual confirmation that summaries are being captured.

## Files to modify

| File | Change |
|------|--------|
| `priv/repo/migrations/YYYYMMDD_add_knowledge_sharing.exs` | New migration |
| `lib/foreman/projects/project.ex` | Add `knowledge_sharing` field |
| `lib/foreman/projects.ex` | Add `update_project/2` |
| `lib/foreman/tasks/task.ex` | Add `summary` field |
| `lib/foreman/tasks.ex` | Add `build_enriched_prompt/2`, `generate_summary/1`, modify `start_agent/4` and `move_to_done/1` |
| `lib/foreman_web/live/project_live/show.ex` | Add toggle UI + event handler |

## Token cost analysis

- **Prompt enrichment**: ~200-500 tokens per task start (only when enabled, scales with number of completed tasks — could cap at last N tasks)
- **Summary generation**: One cheap inference per task completion (~200 output tokens, minimal input)
- **No cost when disabled**: Feature is entirely opt-in, zero overhead when `knowledge_sharing` is `false`
