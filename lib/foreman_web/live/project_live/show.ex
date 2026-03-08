defmodule ForemanWeb.ProjectLive.Show do
  use ForemanWeb, :live_view

  alias Foreman.Projects
  alias Foreman.Tasks
  alias Foreman.Tasks.Task

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project!(id)
    tasks = Tasks.list_tasks_for_project(id)

    if connected?(socket) do
      Tasks.subscribe_project(id)
    end

    {:ok,
     socket
     |> assign(:project, project)
     |> assign(:tasks, tasks)
     |> assign(:page_title, project.name)
     |> assign(:task_changeset, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_task, _params) do
    assign(socket, :task_changeset, Tasks.change_task(%Task{}, %{}))
  end

  defp apply_action(socket, :show, _params) do
    assign(socket, :task_changeset, nil)
  end

  @impl true
  def handle_event("new_task", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{socket.assigns.project.id}/tasks/new")}
  end

  @impl true
  def handle_event("save_task", %{"task" => task_params}, socket) do
    task_params = Map.put(task_params, "project_id", socket.assigns.project.id)

    case Tasks.create_task(task_params) do
      {:ok, _task} ->
        tasks = Tasks.list_tasks_for_project(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:tasks, tasks)
         |> assign(:task_changeset, nil)
         |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, task_changeset: changeset)}
    end
  end

  @impl true
  def handle_event("move_task", %{"task_id" => task_id, "status" => new_status}, socket) do
    task = Tasks.get_task!(task_id)

    result =
      case new_status do
        "in_progress" -> Tasks.move_to_in_progress(task)
        "review" -> Tasks.move_to_review(task)
        "done" -> Tasks.move_to_done(task)
        "todo" -> {:error, "Cannot move back to todo"}
        _ -> {:error, "Unknown status"}
      end

    case result do
      {:ok, _task} ->
        tasks = Tasks.list_tasks_for_project(socket.assigns.project.id)
        {:noreply, assign(socket, :tasks, tasks)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "#{reason}")}
    end
  end

  @impl true
  def handle_event("cancel_new_task", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{socket.assigns.project.id}")}
  end

  @impl true
  def handle_info({:task_created, _task}, socket) do
    tasks = Tasks.list_tasks_for_project(socket.assigns.project.id)
    {:noreply, assign(socket, :tasks, tasks)}
  end

  @impl true
  def handle_info({:task_updated, _task}, socket) do
    tasks = Tasks.list_tasks_for_project(socket.assigns.project.id)
    {:noreply, assign(socket, :tasks, tasks)}
  end

  defp tasks_by_status(tasks, status) do
    Enum.filter(tasks, &(&1.status == status))
  end

  defp status_color("todo"), do: "bg-base-200 border-base-300"
  defp status_color("in_progress"), do: "bg-info/10 border-info/30"
  defp status_color("review"), do: "bg-warning/10 border-warning/30"
  defp status_color("done"), do: "bg-success/10 border-success/30"

  defp status_label("todo"), do: "To Do"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("review"), do: "Review"
  defp status_label("done"), do: "Done"

  defp status_icon("todo"), do: "○"
  defp status_icon("in_progress"), do: "◉"
  defp status_icon("review"), do: "◎"
  defp status_icon("done"), do: "●"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Header --%>
      <div class="bg-base-100 border-b border-base-300 px-6 py-4 flex justify-between items-center">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/projects"} class="text-base-content/60 hover:text-base-content">
            &larr; Projects
          </.link>
          <h1 class="text-xl font-bold">{@project.name}</h1>
          <span class="text-sm text-base-content/60 font-mono">{@project.repo_path}</span>
        </div>
        <button
          phx-click="new_task"
          class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
        >
          + New Task
        </button>
      </div>

      <%!-- New Task Modal --%>
      <%= if @task_changeset do %>
        <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div
            class="bg-base-100 rounded-lg shadow-xl p-6 w-full max-w-lg"
            phx-click-away="cancel_new_task"
          >
            <h2 class="text-lg font-semibold mb-4">New Task</h2>
            <.form for={@task_changeset} phx-submit="save_task" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-base-content">Title</label>
                <input
                  type="text"
                  name="task[title]"
                  value=""
                  class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary"
                  placeholder="Fix login bug"
                  required
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content">Instructions</label>
                <textarea
                  name="task[instructions]"
                  rows="6"
                  class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary"
                  placeholder="Describe what the agent should do..."
                  required
                ></textarea>
              </div>
              <div class="flex gap-2 justify-end">
                <button
                  type="button"
                  phx-click="cancel_new_task"
                  class="px-4 py-2 rounded border border-base-300 hover:bg-base-200"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                >
                  Create Task
                </button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Kanban Board --%>
      <div class="flex-1 overflow-x-auto p-6">
        <div class="flex gap-4 h-full min-w-max">
          <%= for status <- ~w(todo in_progress review done) do %>
            <div class={"flex flex-col w-80 rounded-lg border #{status_color(status)}"}>
              <%!-- Column Header --%>
              <div class="px-4 py-3 border-b font-semibold text-sm flex items-center gap-2">
                <span>{status_icon(status)}</span>
                <span>{status_label(status)}</span>
                <span class="ml-auto bg-base-100/50 px-2 py-0.5 rounded-full text-xs">
                  {length(tasks_by_status(@tasks, status))}
                </span>
              </div>

              <%!-- Cards --%>
              <div
                class="flex-1 overflow-y-auto p-2 space-y-2"
                id={"column-#{status}"}
                phx-hook="Sortable"
                data-status={status}
              >
                <%= for task <- tasks_by_status(@tasks, status) do %>
                  <div
                    class="bg-base-100 rounded-lg shadow-sm border border-base-300 p-3 cursor-pointer hover:shadow-md transition-shadow"
                    id={"task-#{task.id}"}
                    data-task-id={task.id}
                  >
                    <.link navigate={~p"/projects/#{@project.id}/tasks/#{task.id}"} class="block">
                      <h3 class="font-medium text-sm">{task.title}</h3>
                      <p class="text-xs text-base-content/60 mt-1 line-clamp-2">{task.instructions}</p>
                      <%= if task.branch_name do %>
                        <p class="text-xs text-info mt-2 font-mono">{task.branch_name}</p>
                      <% end %>
                    </.link>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
