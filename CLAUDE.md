# Foreman

Multi-agent Claude orchestrator — a Phoenix LiveView app that manages multiple Claude Code agents working on the same git repo in parallel.

## Tech Stack

- **Elixir/Phoenix LiveView** (Phoenix 1.8, LiveView 1.1)
- **PostgreSQL** via Ecto (UUIDs for all primary keys)
- **Tailwind CSS v4** (via Phoenix's built-in tailwind integration)
- **SortableJS** for kanban drag-and-drop (`assets/vendor/sortable.js`)
- **Chart.js** for stats charts (via CDN in root layout)
- **Claude CLI** (`claude -p --output-format stream-json --input-format stream-json`) via Elixir Ports

## Commands

```bash
mix setup              # Install deps, create DB, migrate, setup assets
mix phx.server         # Start dev server on localhost:4000
mix test               # Run tests
mix compile --warnings-as-errors  # Compile with strict warnings
mix format             # Format code
mix precommit          # Full pre-commit check (compile, format, test)
```

**When working inside a git worktree**, run `mix deps.get` before `mix compile` — each worktree has an independent `_build` directory and compilation will fail without it.

## Architecture

### Database (3 tables, all UUID PKs)

- **projects** — `name`, `repo_path` (absolute path to local git repo)
- **tasks** — `title`, `instructions`, `status` (todo/in_progress/review/done/failed), `position`, `branch_name`, `worktree_path`, `session_id`, `images` (array of maps), `total_cost_usd`, `total_input_tokens`, `total_output_tokens`, `num_turns`, `duration_ms`, belongs_to project
- **messages** — `role` (user/assistant/system/thinking/tool_use/tool_use_summary), `content`, belongs_to task

### Backend Modules

| Module | Path | Purpose |
|--------|------|---------|
| `Foreman.Projects` | `lib/foreman/projects.ex` | Projects CRUD context |
| `Foreman.Tasks` | `lib/foreman/tasks.ex` | Tasks CRUD + state machine transitions |
| `Foreman.Chat` | `lib/foreman/chat.ex` | Messages CRUD, broadcasts via PubSub |
| `Foreman.Git` | `lib/foreman/git.ex` | Git operations via `System.cmd` — worktree, branch, diff, rebase, merge |
| `Foreman.Agent.Supervisor` | `lib/foreman/agent/supervisor.ex` | DynamicSupervisor for agent runners |
| `Foreman.Agent.Runner` | `lib/foreman/agent/runner.ex` | GenServer per task — manages claude CLI Port process |

### Ecto Schemas

| Schema | Path |
|--------|------|
| `Foreman.Projects.Project` | `lib/foreman/projects/project.ex` |
| `Foreman.Tasks.Task` | `lib/foreman/tasks/task.ex` |
| `Foreman.Chat.Message` | `lib/foreman/chat/message.ex` |

### LiveView Pages

| LiveView | Route | Purpose |
|----------|-------|---------|
| `ProjectLive.Index` | `/`, `/projects`, `/projects/new` | Project list + create form |
| `ProjectLive.Show` | `/projects/:id`, `/projects/:id/tasks/new` | Kanban board with 4 columns |
| `ProjectLive.Stats` | `/projects/:id/stats` | Per-task cost/token/duration stats with charts and table view |
| `TaskLive.Show` | `/projects/:project_id/tasks/:id` | Task detail: chat + diff viewer + sticky todo panel |

### Task State Machine

```
todo → in_progress → review → done
         ↑    ↑               |
         |    └───────────────┘  (feedback sends task back)
         |
       failed → in_progress  (retry or resume)
```

- **todo → in_progress**: Creates git worktree + branch, spawns `Foreman.Agent.Runner`
- **in_progress → review**: Auto-triggered when claude CLI exits successfully
- **in_progress → failed**: Auto-triggered on non-zero exit or error result from claude CLI
- **review → in_progress**: User sends feedback; reuses live runner if alive, otherwise starts new with `--resume <session_id>`
- **review → done**: Rebases from main, merges branch, removes worktree, deletes branch
- **done → todo**: User can move completed tasks back to todo (clears branch_name, worktree_path, session_id)
- **failed → in_progress (retry)**: Clears session_id, starts fresh agent
- **failed → in_progress (resume)**: Keeps session_id, resumes with `--resume`

### Agent Runner Details

- Spawns `claude -p --output-format stream-json --input-format stream-json --verbose --allowedTools Bash,Read,Edit,MultiEdit,Write,Glob,Grep,TodoWrite,TodoRead,WebFetch,WebSearch`
- Initial prompt sent via stdin as stream-json (includes task title + instructions)
- Supports optional `images` (array of base64 maps) attached to the task
- Working directory set to the git worktree path
- Parses stream-json output line by line, persists messages to DB
- Captures `session_id` from init events for session resumption
- Handles message types: `assistant`, `system`, `thinking`, `tool_use_summary`; skips `prompt_suggestion`
- Saves result metadata (cost, tokens, turns, duration) on completion using `COALESCE` accumulation
- Registered via `Foreman.Agent.Registry` (unique Registry keyed by task_id)
- macOS notification sent via `osascript` when task enters review

### PubSub Topics

- `"task:<task_id>"` — new messages, status changes (consumed by TaskLive.Show)
- `"project:<project_id>"` — task created/updated/deleted (consumed by ProjectLive.Show)

### JS Hooks (`assets/js/hooks/`)

- **Sortable** — SortableJS integration for kanban drag-and-drop, pushes `"move_task"` events
- **ScrollBottom** — Auto-scrolls chat container when new messages arrive
- **Charts** — Chart.js integration, reads `data-charts` JSON attribute and renders charts

## Testing

Tests use ExUnit with BDD-style `describe` blocks. One assertion per test — keep tests easy to read over clever.

```bash
mix test                          # Run all tests
mix test test/foreman/tasks_test.exs  # Run a single file
```

- Use `Foreman.DataCase` for tests that need database access
- Use `Foreman.ConnCase` for HTTP/LiveView tests
- Add shared fixtures to `test/support/fixtures.ex`

## Conventions

- All Ecto schemas use `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id`
- Git worktrees are created at `<repo_path>/.worktrees/<branch_name>`
- Branch names are prefixed: `foreman/<slugified-title>`
- Context modules handle PubSub broadcasting (not LiveViews)
- LiveViews subscribe to PubSub in `mount` when `connected?/1` is true
- PostgreSQL dev credentials: username `erikmejerhansen`, no password
