defmodule Foreman.TasksTest do
  use Foreman.DataCase, async: true

  import Foreman.Fixtures

  alias Foreman.Tasks
  alias Foreman.Tasks.Task

  describe "create_task/1" do
    test "succeeds with valid attributes" do
      project = create_project()
      assert {:ok, %Task{}} = Tasks.create_task(task_attrs(project.id))
    end

    test "persists the task title" do
      project = create_project()
      {:ok, task} = Tasks.create_task(task_attrs(project.id, %{"title" => "My Feature"}))
      assert task.title == "My Feature"
    end

    test "persists the task instructions" do
      project = create_project()
      {:ok, task} = Tasks.create_task(task_attrs(project.id, %{"instructions" => "Build it"}))
      assert task.instructions == "Build it"
    end

    test "defaults status to todo" do
      project = create_project()
      {:ok, task} = Tasks.create_task(task_attrs(project.id))
      assert task.status == "todo"
    end

    test "fails when title is missing" do
      project = create_project()
      assert {:error, changeset} = Tasks.create_task(task_attrs(project.id, %{"title" => nil}))
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails when instructions are missing" do
      project = create_project()

      assert {:error, changeset} =
               Tasks.create_task(task_attrs(project.id, %{"instructions" => nil}))

      assert %{instructions: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails when status is not a valid value" do
      project = create_project()

      assert {:error, changeset} =
               Tasks.create_task(task_attrs(project.id, %{"status" => "bogus"}))

      assert %{status: _} = errors_on(changeset)
    end
  end

  describe "list_tasks_for_project/1" do
    test "returns an empty list when project has no tasks" do
      project = create_project()
      assert [] = Tasks.list_tasks_for_project(project.id)
    end

    test "returns tasks belonging to the project" do
      project = create_project()
      create_task(project.id)
      create_task(project.id)

      assert length(Tasks.list_tasks_for_project(project.id)) == 2
    end

    test "does not return tasks from other projects" do
      project_a = create_project(%{"name" => "A"})
      project_b = create_project(%{"name" => "B"})
      create_task(project_a.id)

      assert [] = Tasks.list_tasks_for_project(project_b.id)
    end
  end

  describe "get_task!/1" do
    test "returns the task with the given id" do
      project = create_project()
      task = create_task(project.id)
      assert Tasks.get_task!(task.id).id == task.id
    end

    test "preloads the associated project" do
      project = create_project()
      task = create_task(project.id)
      assert Tasks.get_task!(task.id).project.id == project.id
    end

    test "raises when task does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(Ecto.UUID.generate())
      end
    end
  end

  describe "change_task/2" do
    test "returns a changeset" do
      project = create_project()
      task = create_task(project.id)
      assert %Ecto.Changeset{} = Tasks.change_task(task)
    end
  end

  describe "move_to_review/1" do
    test "transitions task from in_progress to review" do
      project = create_project()
      task = create_task_with_status(project.id, "in_progress")
      {:ok, updated} = Tasks.move_to_review(task)
      assert updated.status == "review"
    end
  end

  describe "move_to_failed/1" do
    test "transitions task from in_progress to failed" do
      project = create_project()
      task = create_task_with_status(project.id, "in_progress")
      {:ok, updated} = Tasks.move_to_failed(task)
      assert updated.status == "failed"
    end
  end

  describe "move_to_todo/1" do
    test "transitions task from done to todo" do
      project = create_project()
      task = create_task_with_status(project.id, "done")
      {:ok, updated} = Tasks.move_to_todo(task)
      assert updated.status == "todo"
    end

    test "clears branch_name when moving back to todo" do
      project = create_project()
      task = create_task_with_status(project.id, "done")
      {:ok, task} = Ecto.Changeset.change(task, branch_name: "foreman/some-branch-abc1") |> Repo.update()
      {:ok, updated} = Tasks.move_to_todo(task)
      assert is_nil(updated.branch_name)
    end

    test "clears session_id when moving back to todo" do
      project = create_project()
      task = create_task_with_status(project.id, "done")
      {:ok, task} = Ecto.Changeset.change(task, session_id: "session-123") |> Repo.update()
      {:ok, updated} = Tasks.move_to_todo(task)
      assert is_nil(updated.session_id)
    end

    test "returns an error when task is not in done status" do
      project = create_project()
      task = create_task_with_status(project.id, "review")
      assert {:error, _} = Tasks.move_to_todo(task)
    end
  end

  describe "update_session_id/2" do
    test "sets the session_id on the task" do
      project = create_project()
      task = create_task(project.id)
      Tasks.update_session_id(task.id, "abc-123")
      assert Tasks.get_task!(task.id).session_id == "abc-123"
    end
  end

  describe "update_result_metadata/2" do
    test "sets total_cost_usd on the task" do
      project = create_project()
      task = create_task(project.id)
      Tasks.update_result_metadata(task.id, total_cost_usd: 0.05)
      assert Tasks.get_task!(task.id).total_cost_usd == 0.05
    end

    test "accumulates cost across multiple calls" do
      project = create_project()
      task = create_task(project.id)
      Tasks.update_result_metadata(task.id, total_cost_usd: 0.05)
      Tasks.update_result_metadata(task.id, total_cost_usd: 0.03)
      assert_in_delta Tasks.get_task!(task.id).total_cost_usd, 0.08, 0.0001
    end

    test "sets num_turns on the task" do
      project = create_project()
      task = create_task(project.id)
      Tasks.update_result_metadata(task.id, num_turns: 7)
      assert Tasks.get_task!(task.id).num_turns == 7
    end

    test "sets duration_ms on the task" do
      project = create_project()
      task = create_task(project.id)
      Tasks.update_result_metadata(task.id, duration_ms: 30_000)
      assert Tasks.get_task!(task.id).duration_ms == 30_000
    end
  end

  describe "delete_task/1" do
    test "removes the task from the database" do
      project = create_project()
      task = create_task(project.id)
      {:ok, _} = Tasks.delete_task(task)
      assert_raise Ecto.NoResultsError, fn -> Tasks.get_task!(task.id) end
    end
  end

  describe "resume_task/1" do
    test "returns an error when task is not failed" do
      project = create_project()
      task = create_task_with_status(project.id, "review")
      assert {:error, _} = Tasks.resume_task(task)
    end

    test "returns an error when failed task has no session_id" do
      project = create_project()
      task = create_task_with_status(project.id, "failed")
      assert {:error, _} = Tasks.resume_task(task)
    end
  end

  describe "retry_failed/1" do
    test "returns an error when task is not in failed status" do
      project = create_project()
      task = create_task_with_status(project.id, "review")
      assert {:error, _} = Tasks.retry_failed(task)
    end
  end
end
