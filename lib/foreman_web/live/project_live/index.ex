defmodule ForemanWeb.ProjectLive.Index do
  use ForemanWeb, :live_view

  alias Foreman.Projects
  alias Foreman.Projects.Project

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, projects: Projects.list_projects())}
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
                class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary"
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
                class="mt-1 block w-full rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary"
                placeholder="/path/to/git/repo"
                required
              />
            </div>
            <div class="flex gap-2">
              <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
                Create
              </button>
              <.link patch={~p"/projects"} class="px-4 py-2 rounded border border-base-300 hover:bg-base-200">
                Cancel
              </.link>
            </div>
          </.form>
        </div>
      <% end %>

      <div class="grid gap-4">
        <%= if @projects == [] do %>
          <p class="text-base-content/60 text-center py-12">No projects yet. Create one to get started.</p>
        <% end %>
        <%= for project <- @projects do %>
          <div class="bg-base-100 rounded-lg shadow p-6 hover:shadow-md transition-shadow">
            <div class="flex justify-between items-center">
              <.link navigate={~p"/projects/#{project.id}"} class="flex-1">
                <h2 class="text-lg font-semibold">{project.name}</h2>
                <p class="text-sm text-base-content/60 mt-1 font-mono">{project.repo_path}</p>
              </.link>
              <button
                phx-click="delete"
                phx-value-id={project.id}
                data-confirm="Delete this project?"
                class="text-red-500 hover:text-red-700 text-sm ml-4"
              >
                Delete
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
