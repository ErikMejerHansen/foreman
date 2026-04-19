---
name: create-todos
description: Break down planned work into tasks and register them in Foreman via the API. Use when the user asks to "create todos", "plan tasks", "add tasks to Foreman", or at the start of a session to plan implementation work.
disable-model-invocation: true
allowed-tools: Bash, Read
---

# Create Todos

Break down planned work into focused, independent tasks and register them in Foreman via the API.

## What makes a good todo

- **Small scope**: Completable in one focused agent session
- **Independent**: Can be worked on without blocking other todos (when possible)
- **Concrete**: Describes a specific outcome, not a vague goal
- **Single concern**: One thing, not bundled features

Good: "Add `created_via_api` boolean field to tasks table migration"
Bad: "Build the API and update the UI" (too broad, two concerns)

## Steps

1. Find the `PROJECT_ID` from the Foreman URL (`/projects/PROJECT_ID`) or ask the user
2. Plan the tasks — break the work into small, independent units
3. Create each task via the API:

```bash
curl -s -X POST http://localhost:4000/api/projects/PROJECT_ID/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "task": {
      "title": "Short, specific title",
      "instructions": "Clear description of what needs to be done and why. Include relevant context, constraints, and what done looks like."
    }
  }'
```

A successful response:
```json
{"data": {"id": "...", "title": "...", "status": "todo", "created_via_api": true}}
```

## Writing good instructions

Write instructions as if briefing a capable engineer with no prior context:
- Explain the goal and why it matters
- Describe the current state and what needs to change
- List constraints or conventions to follow (check AGENTS.md or CLAUDE.md in the project)
- Define what "done" looks like

## After creating todos

Report back a summary of what was created — titles and a one-line rationale for how the work was split up.
