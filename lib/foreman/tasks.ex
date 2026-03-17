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

  def move_to_in_progress(%Task{status: status} = task)
      when status in ["todo", "review", "failed"] do
    project = Foreman.Projects.get_project!(task.project_id)
    branch_name = slugify(task.title)
    worktree_path = Path.join(project.repo_path, ".worktrees/#{branch_name}")

    # Only create worktree if coming from todo (review/failed already have one)
    if status == "todo" do
      case Git.create_worktree(project.repo_path, branch_name, worktree_path) do
        :ok -> start_agent(task, branch_name, worktree_path)
        {:error, reason} -> {:error, reason}
      end
    else
      # From review/failed — reuse existing runner if alive
      case Agent.Supervisor.find_runner(task.id) do
        nil ->
          start_agent(task, task.branch_name, task.worktree_path)

        _pid ->
          # Runner still alive, just update status
          {:ok, task} =
            task
            |> Task.changeset(%{status: "in_progress"})
            |> Repo.update()

          broadcast_project(task.project_id, {:task_updated, task})
          {:ok, task}
      end
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

    default_prompt = "# #{task.title}\n\n#{task.instructions}"
    prompt = Keyword.get(opts, :prompt, default_prompt)
    skip_chat_message = Keyword.get(opts, :skip_chat_message, false)
    images = task.images || []
    project = Foreman.Projects.get_project!(task.project_id)

    case Agent.Supervisor.start_runner(%{
           task_id: task.id,
           worktree_path: worktree_path,
           prompt: prompt,
           images: images,
           session_id: task.session_id,
           skip_chat_message: skip_chat_message,
           allowed_tools: project.allowed_tools,
           skip_permissions: project.skip_permissions
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
    notify_review(task)
    Foreman.ReviewNotifications.notify(task.project_id)
    {:ok, task}
  end

  defp notify_review(%Task{title: title}) do
    script = ~s[display notification "#{title}" with title "Foreman: Ready for Review"]
    System.cmd("osascript", ["-e", script], stderr_to_stdout: true)
  end

  def move_to_done(%Task{status: "review"} = task) do
    require Logger
    project = Foreman.Projects.get_project!(task.project_id)

    # Use spawn to avoid deadlock when called from within the runner itself
    spawn(fn -> Agent.Supervisor.stop_runner(task.id) end)

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
    else
      {:error, reason} ->
        Logger.error("Failed to move task #{task.id} to done: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def move_to_done(_task), do: {:error, "Can only move to done from review"}

  def move_to_todo(%Task{status: "done"} = task) do
    {:ok, task} =
      task
      |> Task.changeset(%{status: "todo", branch_name: nil, worktree_path: nil, session_id: nil})
      |> Repo.update()

    broadcast_project(task.project_id, {:task_updated, task})
    broadcast_task(task.id, {:status_changed, "todo"})
    {:ok, task}
  end

  def move_to_todo(_task), do: {:error, "Can only move to todo from done"}

  def move_to_failed(%Task{} = task) do
    # Use spawn to avoid deadlock when called from within the runner itself:
    # stop_runner is a blocking supervisor call, but the runner may be the one calling us.
    spawn(fn -> Agent.Supervisor.stop_runner(task.id) end)

    {:ok, task} =
      task
      |> Task.changeset(%{status: "failed"})
      |> Repo.update()

    broadcast_project(task.project_id, {:task_updated, task})
    broadcast_task(task.id, {:status_changed, "failed"})
    {:ok, task}
  end

  def resume_task(%Task{status: "failed", session_id: session_id} = task)
      when not is_nil(session_id) do
    start_agent(task, task.branch_name, task.worktree_path,
      prompt: "Please continue from where you left off."
    )
  end

  def resume_task(_task), do: {:error, "Can only resume failed tasks that have a session"}

  def retry_failed(%Task{status: "failed"} = task) do
    # Clear session_id for a fresh start without --resume
    {:ok, task} = task |> Task.changeset(%{session_id: nil}) |> Repo.update()
    move_to_in_progress(task)
  end

  def retry_failed(_task), do: {:error, "Can only retry failed tasks"}

  def delete_task(%Task{} = task) do
    Agent.Supervisor.stop_runner(task.id)

    if task.worktree_path && task.branch_name do
      project = Foreman.Projects.get_project!(task.project_id)
      Git.remove_worktree(project.repo_path, task.worktree_path)
      Git.delete_branch(project.repo_path, task.branch_name)
    end

    case Repo.delete(task) do
      {:ok, task} ->
        broadcast_project(task.project_id, {:task_deleted, task})
        {:ok, task}

      error ->
        error
    end
  end

  def update_session_id(task_id, session_id) do
    from(t in Task, where: t.id == ^task_id)
    |> Repo.update_all(set: [session_id: session_id])

    :ok
  end

  def update_result_metadata(task_id, metadata) do
    cost = metadata[:total_cost_usd] || 0.0
    input_tokens = metadata[:total_input_tokens] || 0
    output_tokens = metadata[:total_output_tokens] || 0
    cache_creation = metadata[:cache_creation_input_tokens] || 0
    cache_read = metadata[:cache_read_input_tokens] || 0
    turns = metadata[:num_turns] || 0
    duration = metadata[:duration_ms] || 0

    from(t in Task,
      where: t.id == ^task_id,
      update: [
        set: [
          total_cost_usd: fragment("COALESCE(total_cost_usd, 0.0) + ?", ^cost),
          total_input_tokens: fragment("COALESCE(total_input_tokens, 0) + ?", ^input_tokens),
          total_output_tokens: fragment("COALESCE(total_output_tokens, 0) + ?", ^output_tokens),
          cache_creation_input_tokens:
            fragment("COALESCE(cache_creation_input_tokens, 0) + ?", ^cache_creation),
          cache_read_input_tokens:
            fragment("COALESCE(cache_read_input_tokens, 0) + ?", ^cache_read),
          num_turns: fragment("COALESCE(num_turns, 0) + ?", ^turns),
          duration_ms: fragment("COALESCE(duration_ms, 0) + ?", ^duration)
        ]
      ]
    )
    |> Repo.update_all([])

    :ok
  end

  def send_feedback(%Task{status: "review"} = task, message, images \\ []) do
    # Move task back to in_progress
    {:ok, task} =
      task
      |> Task.changeset(%{status: "in_progress"})
      |> Repo.update()

    broadcast_project(task.project_id, {:task_updated, task})
    broadcast_task(task.id, {:status_changed, "in_progress"})

    # Reuse existing runner if alive (persistent session), otherwise start fresh
    case Agent.Supervisor.find_runner(task.id) do
      nil ->
        # Runner died — start a new one with --resume
        require Logger
        Logger.info("Runner not found for task #{task.id}, starting new session with --resume")
        project = Foreman.Projects.get_project!(task.project_id)

        Agent.Supervisor.start_runner(%{
          task_id: task.id,
          worktree_path: task.worktree_path,
          prompt: message,
          images: images,
          session_id: task.session_id,
          skip_chat_message: true,
          allowed_tools: project.allowed_tools,
          skip_permissions: project.skip_permissions
        })

      pid ->
        # Send feedback to the running agent via stdin
        Agent.Runner.send_message(pid, message, images)
    end

    {:ok, task}
  end

  def send_message_to_agent(%Task{status: "in_progress"} = task, message, images \\ []) do
    case Agent.Supervisor.find_runner(task.id) do
      nil -> {:error, "Agent not running"}
      pid -> Agent.Runner.send_message(pid, message, images)
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
    suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
    |> then(&"foreman/#{&1}-#{suffix}")
  end
end
