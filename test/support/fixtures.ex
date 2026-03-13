defmodule Foreman.Fixtures do
  @moduledoc """
  Test fixtures for creating database records.
  """

  alias Foreman.Projects
  alias Foreman.Tasks
  alias Foreman.Chat

  def project_attrs(overrides \\ %{}) do
    Map.merge(
      %{"name" => "Test Project", "repo_path" => "/tmp/test-repo"},
      overrides
    )
  end

  def create_project(overrides \\ %{}) do
    {:ok, project} = Projects.create_project(project_attrs(overrides))
    project
  end

  def task_attrs(project_id, overrides \\ %{}) do
    Map.merge(
      %{
        "title" => "Test Task",
        "instructions" => "Do the thing",
        "project_id" => project_id
      },
      overrides
    )
  end

  def create_task(project_id, overrides \\ %{}) do
    {:ok, task} = Tasks.create_task(task_attrs(project_id, overrides))
    task
  end

  def create_task_with_status(project_id, status, overrides \\ %{}) do
    task = create_task(project_id, overrides)

    {:ok, task} =
      task
      |> Foreman.Tasks.Task.changeset(%{status: status})
      |> Foreman.Repo.update()

    task
  end

  def message_attrs(task_id, overrides \\ %{}) do
    Map.merge(
      %{
        "task_id" => task_id,
        "role" => "assistant",
        "content" => "Hello, I'm working on this."
      },
      overrides
    )
  end

  def create_message(task_id, overrides \\ %{}) do
    {:ok, message} = Chat.create_message(message_attrs(task_id, overrides))
    message
  end
end
