# Foreman

A local multi-agent Claude orchestrator. Foreman lets you run multiple [Claude Code](https://claude.ai/code) agents in parallel on the same git repository, managing them through a kanban-style board in your browser.

**Foreman is designed exclusively for local use.** It is not intended to be deployed or hosted remotely — it runs on your machine, talks to your local git repos, and uses your local Claude CLI installation.

Inspired by [VibeKanban](https://www.vibekanban.com/).

---

## What it does

You create a **project** pointing at a local git repo, then add **tasks** describing work you want done. When you start a task, Foreman:

1. Creates a git worktree and branch for the task
2. Spawns a Claude Code agent in that worktree
3. Streams the agent's output (messages, tool calls, thinking) into a live chat view
4. Moves the task to **Review** when the agent finishes
5. Lets you send feedback to continue the work, or merge the branch when you're happy

Multiple tasks run in parallel — each agent works in its own isolated worktree, so they don't step on each other.

## Features

- **Kanban board** — drag tasks between Todo, In Progress, Review, and Done columns
- **Parallel agents** — run as many Claude agents simultaneously as you like, each on its own branch
- **Live chat** — stream agent messages, tool use, and thinking in real time
- **Diff viewer** — see exactly what the agent changed before merging
- **Feedback loop** — send follow-up instructions to an agent in Review; it resumes with full session context
- **One-click merge** — rebases from main and merges the branch when you're satisfied
- **Knowledge sharing** — opt-in per-project setting that lets agents learn from each other: completed tasks get auto-summarised, and new agents receive context about what sibling tasks have done and are working on
- **Image attachments** — attach screenshots or diagrams to tasks for the agent to reference
- **Stats view** — per-task cost, token usage, turn count, and duration charts
- **macOS notifications** — get notified when a task moves to Review

## Prerequisites

- **macOS** (notifications use `osascript`; other features may work on Linux but are untested)
- **Elixir** 1.15+ and **Erlang/OTP** — install via [asdf](https://asdf-vm.com/) or [mise](https://mise.jdx.dev/)
- **PostgreSQL** running locally
- **Claude CLI** installed and authenticated (`claude` available in your PATH)
- **Node.js** (for asset compilation)

## Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd foreman

# 2. Install dependencies, create the database, and build assets
mix setup

# 3. Start the server
mix phx.server
```

Open [localhost:4000](http://localhost:4000) in your browser.

### Database configuration

By default, Foreman connects to PostgreSQL as your current system user with no password. If your setup is different, edit `config/dev.exs`:

```elixir
config :foreman, Foreman.Repo,
  username: "your_username",
  password: "your_password",
  database: "foreman_dev"
```

## Usage

1. **Create a project** — give it a name and point it at the absolute path of a local git repo
2. **Add tasks** — write a title and detailed instructions; optionally attach images
3. **Start a task** — click the play button to launch a Claude agent
4. **Watch it work** — open the task to see the live chat stream and tool calls
5. **Review** — when the agent finishes, check the diff and send feedback or merge

## How agents work

Each agent runs as:

```
claude -p --output-format stream-json --input-format stream-json --verbose \
  --allowedTools Bash,Read,Edit,MultiEdit,Write,Glob,Grep,TodoWrite,TodoRead,WebFetch,WebSearch
```

The agent's working directory is its dedicated git worktree. Foreman sends the task title and instructions as the initial prompt, streams the JSON output line by line, and persists all messages to the database.

When you send feedback on a task in Review, the agent resumes using `--resume <session_id>` so it retains full conversation context.

## Development

```bash
mix test               # Run tests
mix format             # Format code
mix precommit          # Full check: compile, format, test
```

## License

See [LICENSE](LICENSE).
