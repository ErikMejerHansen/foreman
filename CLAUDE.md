# Foreman

Multi-agent Claude orchestrator — a Phoenix LiveView app that manages multiple Claude Code agents working on the same git repo in parallel.

## Tech Stack

- **Elixir/Phoenix LiveView** (Phoenix 1.8, LiveView 1.1)
- **PostgreSQL** via Ecto (UUIDs for all primary keys)
- **Tailwind CSS v4** (via Phoenix's built-in tailwind integration)
- **SortableJS** for kanban drag-and-drop (`assets/vendor/sortable.js`)
- **Claude CLI** (`claude -p --output-format stream-json`) via Elixir Ports

## Commands

```bash
mix setup              # Install deps, create DB, migrate, setup assets
mix phx.server         # Start dev server on localhost:4000
mix test               # Run tests
mix compile --warnings-as-errors  # Compile with strict warnings
mix format             # Format code
mix precommit          # Full pre-commit check (compile, format, test)
```

## Architecture

### Database (3 tables, all UUID PKs)

- **projects** — `name`, `repo_path` (absolute path to local git repo)
- **tasks** — `title`, `instructions`, `status` (todo/in_progress/review/done), `position`, `branch_name`, `worktree_path`, `session_id`, belongs_to project
- **messages** — `role` (user/assistant/system), `content`, belongs_to task

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
| `TaskLive.Show` | `/projects/:project_id/tasks/:id` | Task detail: chat + diff viewer |

### Task State Machine

```
todo → in_progress → review → done
                  ↑         |
                  └─────────┘  (feedback sends task back)
```

- **todo → in_progress**: Creates git worktree + branch, spawns `Foreman.Agent.Runner`
- **in_progress → review**: Auto-triggered when claude CLI exits successfully
- **review → in_progress**: User sends feedback, agent resumes with `--resume <session_id>`
- **review → done**: Rebases from main, merges branch, removes worktree, deletes branch

### Agent Runner Details

- Spawns `claude -p <prompt> --output-format stream-json --verbose --allowedTools Bash,Read,Edit,Write,Glob,Grep`
- Working directory set to the git worktree path
- Parses stream-json output line by line, persists messages to DB
- Captures `session_id` from result events for session resumption
- Registered via `Foreman.Agent.Registry` (unique Registry keyed by task_id)

### PubSub Topics

- `"task:<task_id>"` — new messages, status changes (consumed by TaskLive.Show)
- `"project:<project_id>"` — task created/updated (consumed by ProjectLive.Show)

### JS Hooks (`assets/js/hooks/`)

- **Sortable** — SortableJS integration for kanban drag-and-drop, pushes `"move_task"` events
- **ScrollBottom** — Auto-scrolls chat container when new messages arrive

## Conventions

- All Ecto schemas use `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id`
- Git worktrees are created at `<repo_path>/.worktrees/<branch_name>`
- Branch names are prefixed: `foreman/<slugified-title>`
- Context modules handle PubSub broadcasting (not LiveViews)
- LiveViews subscribe to PubSub in `mount` when `connected?/1` is true
- PostgreSQL dev credentials: username `erikmejerhansen`, no password
