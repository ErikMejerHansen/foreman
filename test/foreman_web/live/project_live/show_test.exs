defmodule ForemanWeb.ProjectLive.ShowTest do
  use ForemanWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Foreman.Fixtures

  describe "new task modal" do
    test "modal is not shown on initial load", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

      refute has_element?(view, "#new-task-modal")
    end

    test "modal opens when clicking New Task button", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

      view |> element("button", "+ New Task") |> render_click()

      assert has_element?(view, "#new-task-modal")
    end

    test "modal opens when navigating to /tasks/new", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      assert has_element?(view, "#new-task-modal")
    end

    test "modal closes when cancel button is clicked", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      view |> element("button", "Cancel") |> render_click()

      refute has_element?(view, "#new-task-modal")
    end

    test "modal stays open when a task_updated PubSub message arrives", %{conn: conn} do
      project = create_project()
      task = create_task(project.id)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      assert has_element?(view, "#new-task-modal")

      send(view.pid, {:task_updated, task})
      render(view)

      assert has_element?(view, "#new-task-modal")
    end

    test "modal stays open when a task_created PubSub message arrives", %{conn: conn} do
      project = create_project()
      task = create_task(project.id)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      assert has_element?(view, "#new-task-modal")

      send(view.pid, {:task_created, task})
      render(view)

      assert has_element?(view, "#new-task-modal")
    end

    test "modal stays open when a task_deleted PubSub message arrives", %{conn: conn} do
      project = create_project()
      task = create_task(project.id)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      assert has_element?(view, "#new-task-modal")

      send(view.pid, {:task_deleted, task})
      render(view)

      assert has_element?(view, "#new-task-modal")
    end

    test "submitting the form creates the task and closes the modal", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      view
      |> form("#new-task-form", task: %{title: "My New Task", instructions: "Do the thing"})
      |> render_submit()

      refute has_element?(view, "#new-task-modal")
      assert has_element?(view, "#new-task-form") == false
      assert render(view) =~ "My New Task"
    end

    test "modal stays open when a change_task event fires", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks/new")

      view
      |> form("#new-task-form", task: %{title: "Partial title"})
      |> render_change()

      assert has_element?(view, "#new-task-modal")
    end
  end
end
