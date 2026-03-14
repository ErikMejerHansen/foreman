defmodule ForemanWeb.ProjectLive.Index do
  use ForemanWeb, :live_view

  alias Foreman.Projects
  alias Foreman.Projects.Project

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Foreman.ReviewNotifications.subscribe()
    end

    review_project_ids = Foreman.ReviewNotifications.pending_project_ids()

    {:ok, assign(socket, projects: Projects.list_projects(), review_project_ids: review_project_ids)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Project")
    |> assign(:changeset, Projects.change_project(%Project{}))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Projects")
    |> assign(:changeset, nil)
  end

  @impl true
  def handle_event("save", %{"project" => project_params}, socket) do
    case Projects.create_project(project_params) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created")
         |> assign(:projects, Projects.list_projects())
         |> push_patch(to: ~p"/projects")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    project = Projects.get_project!(id)
    {:ok, _} = Projects.delete_project(project)

    {:noreply, assign(socket, projects: Projects.list_projects())}
  end

  @impl true
  def handle_info({:review_notification, project_id}, socket) do
    {:noreply, update(socket, :review_project_ids, &[project_id | List.delete(&1, project_id)])}
  end

  @impl true
  def handle_info({:review_notification_cleared, project_id}, socket) do
    {:noreply, update(socket, :review_project_ids, &List.delete(&1, project_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto py-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-2xl font-bold">Foreman</h1>
        <.link
          patch={~p"/projects/new"}
          class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
        >
          New Project
        </.link>
      </div>

      <%= if @changeset do %>
        <div class="bg-base-100 rounded-lg shadow p-6 mb-6">
          <h2 class="text-lg font-semibold mb-4">New Project</h2>
          <.form for={@changeset} phx-submit="save" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-base-content">Name</label>
              <input
                type="text"
                name="project[name]"
                value={@changeset.changes[:name] || ""}
                class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary px-3 py-2"
                placeholder="My Project"
                required
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-base-content">Repository Path</label>
              <input
                type="text"
                name="project[repo_path]"
                value={@changeset.changes[:repo_path] || ""}
                class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary px-3 py-2"
                placeholder="/path/to/git/repo"
                required
              />
            </div>
            <div class="flex gap-2">
              <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
                Create
              </button>
              <.link
                patch={~p"/projects"}
                class="px-4 py-2 rounded border border-base-300 hover:bg-base-200"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      <% end %>

      <div class="grid gap-4">
        <%= if @projects == [] do %>
          <p class="text-base-content/60 text-center py-12">
            No projects yet. Create one to get started.
          </p>
        <% end %>
        <%= for project <- @projects do %>
          <div class="bg-base-100 rounded-lg shadow p-6 hover:shadow-md transition-shadow border border-base-content/15">
            <div class="flex justify-between items-center">
              <.link navigate={~p"/projects/#{project.id}"} class="flex-1">
                <div class="flex items-center gap-2">
                  <h2 class="text-lg font-semibold">{project.name}</h2>
                  <%= if project.id in @review_project_ids do %>
                    <span class="w-2 h-2 bg-red-500 rounded-full flex-shrink-0" title="Task ready for review"></span>
                  <% end %>
                </div>
                <p class="text-sm text-base-content/60 mt-1 font-mono">{project.repo_path}</p>
              </.link>
              <div class="flex items-center gap-3 ml-4">
                <.link
                  navigate={~p"/projects/#{project.id}/settings"}
                  class="text-base-content/50 hover:text-base-content"
                  title="Settings"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
                  </svg>
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={project.id}
                  data-confirm="Delete this project?"
                  title="Delete"
                  class="bg-red-500 hover:bg-red-600 text-white rounded p-1"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
