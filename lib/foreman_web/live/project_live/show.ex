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
     |> assign(:task_changeset, nil)
     |> assign(:show_all_done, false)}
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
  def handle_event("toggle_knowledge_sharing", _params, socket) do
    project = socket.assigns.project
    new_value = !project.knowledge_sharing

    case Projects.update_project(project, %{knowledge_sharing: new_value}) do
      {:ok, project} ->
        {:noreply, assign(socket, :project, project)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update knowledge sharing setting")}
    end
  end

  @impl true
  def handle_event("new_task", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{socket.assigns.project.id}/tasks/new")}
  end

  @impl true
  def handle_event("save_task", params, socket) do
    task_params =
      params
      |> Map.get("task", %{})
      |> Map.put("project_id", socket.assigns.project.id)

    auto_start = Map.get(params, "auto_start") == "on"

    case Tasks.create_task(task_params) do
      {:ok, task} ->
        if auto_start, do: Tasks.move_to_in_progress(task)
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
        "todo" -> Tasks.move_to_todo(task)
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
  def handle_event("toggle_show_all_done", _params, socket) do
    {:noreply, update(socket, :show_all_done, &(!&1))}
  end

  @impl true
  def handle_event("cancel_new_task", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{socket.assigns.project.id}")}
  end

  @impl true
  def handle_event("delete_task", %{"id" => task_id}, socket) do
    task = Tasks.get_task!(task_id)

    case Tasks.delete_task(task) do
      {:ok, _task} ->
        tasks = Tasks.list_tasks_for_project(socket.assigns.project.id)
        {:noreply, assign(socket, :tasks, tasks)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "#{reason}")}
    end
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

  @impl true
  def handle_info({:task_deleted, _task}, socket) do
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
  defp status_color("failed"), do: "bg-error/10 border-error/30"

  defp status_label("todo"), do: "To Do"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("review"), do: "Review"
  defp status_label("done"), do: "Done"
  defp status_label("failed"), do: "Failed"

  defp status_icon("todo"), do: "○"
  defp status_icon("in_progress"), do: "◉"
  defp status_icon("review"), do: "◎"
  defp status_icon("done"), do: "●"
  defp status_icon("failed"), do: "✕"

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
        <div class="flex items-center gap-4">
          <label class="flex items-center gap-2 cursor-pointer text-sm">
            <input
              type="checkbox"
              checked={@project.knowledge_sharing}
              phx-click="toggle_knowledge_sharing"
              class="toggle toggle-sm"
            />
            <span class="text-base-content/70">Knowledge sharing</span>
          </label>
          <button
            phx-click="new_task"
            class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
          >
            + New Task
          </button>
        </div>
      </div>

      <%!-- New Task Modal --%>
      <%= if @task_changeset do %>
        <div
          id="new-task-modal"
          phx-update="ignore"
          class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
        >
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
                  class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary px-3 py-2"
                  placeholder="Fix login bug"
                  required
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-base-content">Instructions</label>
                <textarea
                  name="task[instructions]"
                  rows="6"
                  class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary px-3 py-2"
                  placeholder="Describe what the agent should do..."
                  required
                ></textarea>
              </div>
              <div class="flex items-center justify-between">
                <label class="flex items-center gap-2 cursor-pointer text-sm">
                  <input type="checkbox" name="auto_start" class="toggle toggle-sm" />
                  <span class="text-base-content/70">Start automatically</span>
                </label>
                <div class="flex gap-2">
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
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <%!-- Kanban Board --%>
      <div class="flex-1 overflow-x-auto p-6">
        <div class="flex gap-4 h-full min-w-max">
          <%= for status <- ~w(todo in_progress review done failed) do %>
            <% all_status_tasks = tasks_by_status(@tasks, status) %>
            <% displayed_tasks =
              if status == "done" && !@show_all_done,
                do: Enum.take(all_status_tasks, -8),
                else: all_status_tasks %>
            <% displayed_tasks =
              if status == "done", do: Enum.reverse(displayed_tasks), else: displayed_tasks %>
            <% hidden_count = length(all_status_tasks) - length(displayed_tasks) %>
            <div class={"flex flex-col w-80 rounded-lg border #{status_color(status)}"}>
              <%!-- Column Header --%>
              <div class="px-4 py-3 border-b font-semibold text-sm flex items-center gap-2">
                <span>{status_icon(status)}</span>
                <span>{status_label(status)}</span>
                <span class="ml-auto bg-base-100/50 px-2 py-0.5 rounded-full text-xs">
                  {length(all_status_tasks)}
                </span>
              </div>

              <%!-- Cards --%>
              <div
                class="flex-1 overflow-y-auto p-2 space-y-2"
                id={"column-#{status}"}
                phx-hook="Sortable"
                data-status={status}
              >
                <%= for task <- displayed_tasks do %>
                  <div
                    class="bg-base-100 rounded-lg shadow-sm border border-base-300 p-3 cursor-pointer hover:shadow-md transition-shadow group relative"
                    id={"task-#{task.id}"}
                    data-task-id={task.id}
                  >
                    <button
                      phx-click="delete_task"
                      phx-value-id={task.id}
                      data-confirm="Delete this task?"
                      class="absolute top-2 right-2 opacity-0 group-hover:opacity-100 text-base-content/40 hover:text-error text-lg leading-none transition-opacity"
                    >
                      &times;
                    </button>
                    <.link navigate={~p"/projects/#{@project.id}/tasks/#{task.id}"} class="block">
                      <h3 class="font-medium text-sm">{task.title}</h3>
                      <p class="text-xs text-base-content/60 mt-1 line-clamp-2">
                        {if task.summary, do: task.summary, else: task.instructions}
                      </p>
                      <%= if task.branch_name do %>
                        <p class="text-xs text-info mt-2 font-mono">{task.branch_name}</p>
                      <% end %>
                    </.link>
                  </div>
                <% end %>
                <%= if hidden_count > 0 do %>
                  <button
                    phx-click="toggle_show_all_done"
                    class="w-full text-xs text-base-content/50 hover:text-base-content py-1.5 text-center rounded border border-dashed border-base-300 hover:border-base-content/30 transition-colors"
                  >
                    + {hidden_count} older tasks
                  </button>
                <% end %>
                <%= if status == "done" && @show_all_done && length(all_status_tasks) > 8 do %>
                  <button
                    phx-click="toggle_show_all_done"
                    class="w-full text-xs text-base-content/50 hover:text-base-content py-1.5 text-center rounded border border-dashed border-base-300 hover:border-base-content/30 transition-colors"
                  >
                    Show less
                  </button>
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
