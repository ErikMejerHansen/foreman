# Create Todos

Break down your planned work into focused, independent tasks and register them in Foreman via the API.

## When to use

Run this at the start of a session to plan work upfront. Create all todos before starting implementation — this gives a complete picture and allows other agents to pick up parallel work.

## What makes a good todo

- **Small scope**: Completable in one focused agent session
- **Independent**: Can be worked on without blocking other todos (when possible)
- **Concrete**: Describes a specific outcome, not a vague goal
- **Single concern**: One thing, not bundled features

Good: "Add `created_via_api` boolean field to tasks table migration"
Bad: "Build the API and update the UI" (too broad, two concerns)

## How to create a todo

The Foreman server runs on `http://localhost:4000`. Find the `PROJECT_ID` from the URL (`/projects/PROJECT_ID`).

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
