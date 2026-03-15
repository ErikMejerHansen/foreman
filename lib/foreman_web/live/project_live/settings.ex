defmodule ForemanWeb.ProjectLive.Settings do
  use ForemanWeb, :live_view

  alias Foreman.Projects
  alias Foreman.Projects.Project

  @tool_descriptions %{
    "Bash" => "Run shell commands in the worktree",
    "Read" => "Read file contents",
    "Edit" => "Make targeted edits to existing files",
    "MultiEdit" => "Apply multiple edits to a file in one shot",
    "Write" => "Create or overwrite files",
    "Glob" => "Find files by name pattern",
    "Grep" => "Search file contents with regex",
    "TodoWrite" => "Update the agent's todo list",
    "TodoRead" => "Read the agent's todo list",
    "WebFetch" => "Fetch content from a URL",
    "WebSearch" => "Search the web"
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project!(id)

    {:ok,
     socket
     |> assign(:page_title, "Settings — #{project.name}")
     |> assign(:project, project)
     |> assign(:changeset, Projects.change_project(project))}
  end

  @impl true
  def handle_event("save", %{"project" => project_params}, socket) do
    # Checkboxes only send values for checked boxes, so we normalise:
    # if "allowed_tools" is missing entirely, treat it as an empty selection.
    params = Map.put_new(project_params, "allowed_tools", [])

    case Projects.update_project(socket.assigns.project, params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Settings saved")
         |> assign(:project, project)
         |> assign(:changeset, Projects.change_project(project))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tool_descriptions, @tool_descriptions)

    ~H"""
    <div class="max-w-2xl mx-auto py-8 px-4">
      <div class="flex items-center gap-2 mb-8 text-sm">
        <.link navigate={~p"/projects"} class="text-base-content/50 hover:text-base-content transition-colors">
          Projects
        </.link>
        <span class="text-base-content/30">/</span>
        <.link navigate={~p"/projects/#{@project.id}"} class="text-base-content/50 hover:text-base-content transition-colors">
          {@project.name}
        </.link>
        <span class="text-base-content/30">/</span>
        <span class="text-base-content font-medium">Settings</span>
      </div>

      <.form for={@changeset} phx-submit="save" class="space-y-6">
        <%!-- General --%>
        <div class="bg-base-100 rounded-xl border border-base-content/15 divide-y divide-base-content/10">
          <div class="px-6 py-4">
            <h2 class="font-semibold">General</h2>
          </div>
          <div class="px-6 py-5 space-y-4">
            <div>
              <label class="block text-sm font-medium mb-1">Name</label>
              <input
                type="text"
                name="project[name]"
                value={Ecto.Changeset.get_field(@changeset, :name)}
                class="block w-full rounded-lg border border-base-content/20 bg-base-200/50 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50"
                required
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Repository Path</label>
              <input
                type="text"
                name="project[repo_path]"
                value={Ecto.Changeset.get_field(@changeset, :repo_path)}
                class="block w-full rounded-lg border border-base-content/20 bg-base-200/50 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-primary/50"
                required
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Run Commands</label>
              <p class="text-xs text-base-content/50 mb-1.5">
                Shell commands to start the project for review. Runs in a new Terminal window at the task's worktree path.
              </p>
              <textarea
                name="project[run_commands]"
                rows="3"
                class="block w-full rounded-lg border border-base-content/20 bg-base-200/50 px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-primary/50"
                placeholder="mix phx.server"
              >{Ecto.Changeset.get_field(@changeset, :run_commands)}</textarea>
            </div>
          </div>
        </div>

        <%!-- Allowed Tools --%>
        <div class="bg-base-100 rounded-xl border border-base-content/15 divide-y divide-base-content/10">
          <div class="px-6 py-4">
            <h2 class="font-semibold">Allowed Tools</h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Controls which tools the Claude agent can use on tasks in this project.
            </p>
          </div>
          <div class="divide-y divide-base-content/10">
            <%= for tool <- Project.all_tools() do %>
              <label class="flex items-center gap-4 px-6 py-3.5 hover:bg-base-200/40 cursor-pointer transition-colors">
                <input
                  type="checkbox"
                  name="project[allowed_tools][]"
                  value={tool}
                  checked={tool in (Ecto.Changeset.get_field(@changeset, :allowed_tools) || [])}
                  class="rounded border-base-300 text-primary focus:ring-primary shrink-0"
                />
                <div class="min-w-0">
                  <span class="text-sm font-mono font-medium">{tool}</span>
                  <p class="text-xs text-base-content/50 mt-0.5">{@tool_descriptions[tool]}</p>
                </div>
              </label>
            <% end %>
          </div>
        </div>

        <div class="flex gap-2">
          <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-blue-700 transition-colors">
            Save changes
          </button>
          <.link
            navigate={~p"/projects/#{@project.id}"}
            class="px-4 py-2 rounded-lg border border-base-content/20 text-sm hover:bg-base-200 transition-colors"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
