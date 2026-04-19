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
      Foreman.ReviewNotifications.subscribe()
      Foreman.ReviewNotifications.clear(id)
    end

    other_review_projects =
      Foreman.ReviewNotifications.pending_project_ids()
      |> Enum.reject(&(&1 == id))

    {:ok,
     socket
     |> assign(:project, project)
     |> assign(:tasks, tasks)
     |> assign(:page_title, project.name)
     |> assign(:task_changeset, nil)
     |> assign(:task_images, [])
     |> assign(:show_all_done, false)
     |> assign(:other_review_projects, other_review_projects)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_task, _params) do
    assign(socket, :task_changeset, Tasks.change_task(%Task{}, %{}))
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:task_changeset, nil)
    |> assign(:task_images, [])
  end

  @impl true
  def handle_event("new_task", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{socket.assigns.project.id}/tasks/new")}
  end

  @impl true
  def handle_event("change_task", %{"task" => task_params}, socket) do
    changeset = Tasks.change_task(%Task{}, task_params)
    {:noreply, assign(socket, :task_changeset, changeset)}
  end

  @impl true
  def handle_event("paste_image", %{"data" => data, "media_type" => media_type}, socket) do
    image = %{"data" => data, "media_type" => media_type}
    {:noreply, update(socket, :task_images, &(&1 ++ [image]))}
  end

  @impl true
  def handle_event("remove_image", %{"index" => index}, socket) do
    images = List.delete_at(socket.assigns.task_images, index)
    {:noreply, assign(socket, :task_images, images)}
  end

  @impl true
  def handle_event("save_task", params, socket) do
    task_params =
      params
      |> Map.get("task", %{})
      |> Map.put("project_id", socket.assigns.project.id)
      |> Map.put("images", socket.assigns.task_images)

    auto_start = Map.get(params, "auto_start") == "on"

    case Tasks.create_task(task_params) do
      {:ok, task} ->
        if auto_start, do: Tasks.move_to_in_progress(task)
        tasks = Tasks.list_tasks_for_project(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:tasks, tasks)
         |> assign(:task_changeset, nil)
         |> assign(:task_images, [])
         |> push_event("clear_images", %{})
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

  @impl true
  def handle_info({:review_notification, project_id}, socket) do
    if project_id != socket.assigns.project.id do
      {:noreply,
       update(socket, :other_review_projects, &[project_id | List.delete(&1, project_id)])}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:review_notification_cleared, project_id}, socket) do
    {:noreply, update(socket, :other_review_projects, &List.delete(&1, project_id))}
  end

  defp tasks_by_status(tasks, "todo") do
    Enum.filter(tasks, &(&1.status in ["todo", "failed"]))
  end

  defp tasks_by_status(tasks, status) do
    Enum.filter(tasks, &(&1.status == status))
  end

  defp kanban_columns(_project) do
    ~w(todo in_progress review done)
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
          <.link navigate={~p"/projects"} class="text-base-content/60 hover:text-base-content flex items-center gap-1.5">
            &larr; Projects
            <%= if @other_review_projects != [] do %>
              <span class="w-2 h-2 bg-red-500 rounded-full flex-shrink-0" title="Another project has a task ready for review"></span>
            <% end %>
          </.link>
          <h1 class="text-xl font-bold">{@project.name}</h1>
          <span class="text-sm text-base-content/60 font-mono">{@project.repo_path}</span>
        </div>
        <div class="flex items-center gap-4">
          <Layouts.theme_toggle />
          <.link
            navigate={~p"/projects/#{@project.id}/stats"}
            class="text-base-content/60 hover:text-base-content"
            title="Stats"
          >
            <.icon name="hero-chart-bar-square" class="size-5" />
          </.link>
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
            <.form for={@task_changeset} phx-submit="save_task" phx-change="change_task" class="space-y-4" phx-hook="CmdEnterSubmit" id="new-task-form">
              <div>
                <label class="block text-sm font-medium text-base-content">Title</label>
                <input
                  type="text"
                  name="task[title]"
                  value={Ecto.Changeset.get_field(@task_changeset, :title) || ""}
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
                  id="task-instructions"
                  phx-hook="ImagePaste"
                  class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary px-3 py-2"
                  placeholder="Describe what the agent should do... (paste images with ⌘V)"
                  required
                >{Ecto.Changeset.get_field(@task_changeset, :instructions) || ""}</textarea>
                <div id="task-images-container" class="mt-2 flex flex-wrap gap-2"></div>
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
          <%= for status <- kanban_columns(@project) do %>
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
                    class={[
                      "rounded-lg shadow-sm border p-3 cursor-pointer hover:shadow-md transition-shadow group relative",
                      if(task.status == "failed",
                        do: "bg-error/10 border-error/40",
                        else: if(task.created_via_api, do: "bg-info/5 border-info/30", else: "bg-base-100 border-base-300")
                      )
                    ]}
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
                        {task.instructions}
                      </p>
                      <%= if task.branch_name do %>
                        <p class="text-xs text-info mt-2 font-mono">{task.branch_name}</p>
                      <% end %>
                      <%= if task.created_via_api do %>
                        <div class="flex items-center gap-1 mt-2">
                          <.icon name="hero-cpu-chip" class="w-3 h-3 text-info/60" />
                          <span class="text-xs text-info/60">agent</span>
                        </div>
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
