defmodule ForemanWeb.TaskLive.ShowTest do
  use ForemanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Foreman.Fixtures

  alias Foreman.Tasks

  describe "done → todo transition" do
    test "shows Start Task button when status_changed to todo message arrives", %{conn: conn} do
      project = create_project()
      task = create_task_with_status(project.id, "done")
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/#{task.id}")

      refute has_element?(view, "button", "Start Task")

      {:ok, _} = Tasks.move_to_todo(task)
      render(view)

      assert has_element?(view, "button", "Start Task")
    end
  end
end
