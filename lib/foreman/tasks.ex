defmodule Foreman.Tasks do
  import Ecto.Query
  alias Foreman.Repo
  alias Foreman.Tasks.Task
  alias Foreman.Git
  alias Foreman.Agent

  def list_tasks_for_project(project_id) do
    Repo.all(
      from t in Task,
        where: t.project_id == ^project_id,
        order_by: [asc: t.position, asc: t.inserted_at]
    )
  end

  def get_task!(id) do
    Repo.get!(Task, id) |> Repo.preload(:project)
  end

  def create_task(attrs) do
    result =
      %Task{}
      |> Task.changeset(Map.put_new(attrs, "status", "todo"))
      |> Repo.insert()

    case result do
      {:ok, task} ->
        broadcast_project(task.project_id, {:task_created, task})
        {:ok, task}

      error ->
        error
    end
  end

  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  def move_to_in_progress(%Task{status: status} = task) when status in ["todo", "review"] do
    project = Foreman.Projects.get_project!(task.project_id)
    branch_name = slugify(task.title)
    worktree_path = Path.join(project.repo_path, ".worktrees/#{branch_name}")

    # Only create worktree if coming from todo (review already has one)
    if status == "todo" do
      case Git.create_worktree(project.repo_path, branch_name, worktree_path) do
        :ok -> start_agent(task, branch_name, worktree_path)
        {:error, reason} -> {:error, reason}
      end
    else
      start_agent(task, task.branch_name, task.worktree_path)
    end
  end

  def move_to_in_progress(_task), do: {:error, "Cannot move to in_progress from current status"}

  defp start_agent(task, branch_name, worktree_path, opts \\ []) do
    {:ok, task} =
      task
      |> Task.changeset(%{
        status: "in_progress",
        branch_name: branch_name,
        worktree_path: worktree_path
      })
      |> Repo.update()

    prompt = Keyword.get(opts, :prompt, task.instructions)
    skip_chat_message = Keyword.get(opts, :skip_chat_message, false)

    case Agent.Supervisor.start_runner(%{
           task_id: task.id,
           worktree_path: worktree_path,
           prompt: prompt,
           session_id: task.session_id,
           skip_chat_message: skip_chat_message
         }) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("Failed to start agent runner for task #{task.id}: #{inspect(reason)}")
    end

    broadcast_project(task.project_id, {:task_updated, task})
    {:ok, task}
  end

  def move_to_review(%Task{} = task) do
    {:ok, task} =
      task
      |> Task.changeset(%{status: "review"})
      |> Repo.update()

    broadcast_project(task.project_id, {:task_updated, task})
    broadcast_task(task.id, {:status_changed, "review"})
    {:ok, task}
  end

  def move_to_done(%Task{status: "review"} = task) do
    project = Foreman.Projects.get_project!(task.project_id)

    with :ok <- Git.rebase_from_main(task.worktree_path),
         :ok <- Git.merge_to_main(project.repo_path, task.branch_name),
         :ok <- Git.remove_worktree(project.repo_path, task.worktree_path),
         :ok <- Git.delete_branch(project.repo_path, task.branch_name) do
      {:ok, task} =
        task
        |> Task.changeset(%{status: "done"})
        |> Repo.update()

      broadcast_project(task.project_id, {:task_updated, task})
      broadcast_task(task.id, {:status_changed, "done"})
      {:ok, task}
    end
  end

  def move_to_done(_task), do: {:error, "Can only move to done from review"}

  def update_session_id(task_id, session_id) do
    task = Repo.get!(Task, task_id)

    task
    |> Task.changeset(%{session_id: session_id})
    |> Repo.update()
  end

  def send_feedback(%Task{status: "review"} = task, message) do
    # Start a new runner with the feedback as the prompt and the session_id for resume.
    # The LiveView already persisted the user message, so skip_chat_message: true.
    start_agent(task, task.branch_name, task.worktree_path,
      prompt: message,
      skip_chat_message: true
    )
  end

  def send_message_to_agent(%Task{status: "in_progress"} = task, message) do
    case Agent.Supervisor.find_runner(task.id) do
      nil -> {:error, "Agent not running"}
      pid -> Agent.Runner.send_message(pid, message)
    end
  end

  # PubSub helpers

  def subscribe_project(project_id) do
    Phoenix.PubSub.subscribe(Foreman.PubSub, "project:#{project_id}")
  end

  def subscribe_task(task_id) do
    Phoenix.PubSub.subscribe(Foreman.PubSub, "task:#{task_id}")
  end

  defp broadcast_project(project_id, message) do
    Phoenix.PubSub.broadcast(Foreman.PubSub, "project:#{project_id}", message)
  end

  def broadcast_task(task_id, message) do
    Phoenix.PubSub.broadcast(Foreman.PubSub, "task:#{task_id}", message)
  end

  defp slugify(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
    |> then(&"foreman/#{&1}")
  end
end
