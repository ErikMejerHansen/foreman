defmodule ForemanWeb.ProjectLive.Stats do
  use ForemanWeb, :live_view

  alias Foreman.Projects
  alias Foreman.Tasks

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project!(id)
    tasks = Tasks.list_tasks_for_project(id)

    {:ok,
     socket
     |> assign(:project, project)
     |> assign(:tasks, tasks)
     |> assign(:page_title, "#{project.name} — Stats")
     |> assign(:sort_by, :cost)
     |> assign(:sort_dir, :desc)}
  end

  @impl true
  def handle_event("sort", %{"col" => col}, socket) do
    col = String.to_existing_atom(col)
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == col do
        {col, toggle_dir(socket.assigns.sort_dir)}
      else
        {col, :desc}
      end

    {:noreply, socket |> assign(:sort_by, sort_by) |> assign(:sort_dir, sort_dir)}
  end

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp sort_tasks(tasks, col, dir) do
    sorted = Enum.sort_by(tasks, &task_sort_value(&1, col), :asc)
    if dir == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp task_sort_value(task, :title), do: task.title || ""
  defp task_sort_value(task, :status), do: task.status || ""
  defp task_sort_value(task, :cost), do: task.total_cost_usd || 0.0
  defp task_sort_value(task, :input_tokens), do: task.total_input_tokens || 0
  defp task_sort_value(task, :output_tokens), do: task.total_output_tokens || 0
  defp task_sort_value(task, :total_tokens),
    do: (task.total_input_tokens || 0) + (task.total_output_tokens || 0)
  defp task_sort_value(task, :turns), do: task.num_turns || 0
  defp task_sort_value(task, :duration), do: task.duration_ms || 0

  defp format_cost(nil), do: "—"
  defp format_cost(cost) when cost == 0, do: "—"
  defp format_cost(cost), do: "$#{:erlang.float_to_binary(cost, decimals: 4)}"

  defp format_tokens(nil), do: "—"
  defp format_tokens(0), do: "—"
  defp format_tokens(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_duration(nil), do: "—"
  defp format_duration(0), do: "—"
  defp format_duration(ms) do
    secs = div(ms, 1000)
    cond do
      secs < 60 -> "#{secs}s"
      secs < 3600 -> "#{div(secs, 60)}m #{rem(secs, 60)}s"
      true -> "#{div(secs, 3600)}h #{div(rem(secs, 3600), 60)}m"
    end
  end

  defp totals(tasks) do
    %{
      cost: tasks |> Enum.map(&(&1.total_cost_usd || 0.0)) |> Enum.sum(),
      input_tokens: tasks |> Enum.map(&(&1.total_input_tokens || 0)) |> Enum.sum(),
      output_tokens: tasks |> Enum.map(&(&1.total_output_tokens || 0)) |> Enum.sum(),
      turns: tasks |> Enum.map(&(&1.num_turns || 0)) |> Enum.sum(),
      duration_ms: tasks |> Enum.map(&(&1.duration_ms || 0)) |> Enum.sum()
    }
  end

  defp status_badge("todo"), do: {"bg-base-200 text-base-content/60", "To Do"}
  defp status_badge("in_progress"), do: {"bg-info/20 text-info", "In Progress"}
  defp status_badge("review"), do: {"bg-warning/20 text-warning", "Review"}
  defp status_badge("done"), do: {"bg-success/20 text-success", "Done"}
  defp status_badge("failed"), do: {"bg-error/20 text-error", "Failed"}
  defp status_badge(s), do: {"bg-base-200", s}

  defp sort_indicator(col, col, :asc), do: " ↑"
  defp sort_indicator(col, col, :desc), do: " ↓"
  defp sort_indicator(_, _, _), do: ""

  @impl true
  def render(assigns) do
    tasks_with_data = Enum.filter(assigns.tasks, &(&1.total_cost_usd || &1.total_input_tokens || &1.num_turns))
    totals = totals(tasks_with_data)
    sorted = sort_tasks(assigns.tasks, assigns.sort_by, assigns.sort_dir)
    assigns = assign(assigns, totals: totals, sorted_tasks: sorted)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <%!-- Header --%>
      <div class="bg-base-100 border-b border-base-300 px-6 py-4 flex justify-between items-center">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/projects/#{@project.id}"} class="text-base-content/60 hover:text-base-content">
            &larr; {@project.name}
          </.link>
          <h1 class="text-xl font-bold">Statistics</h1>
        </div>
      </div>

      <div class="p-6 space-y-6">
        <%!-- Summary Cards --%>
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Tasks</div>
            <div class="text-2xl font-bold">{length(@tasks)}</div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Total Cost</div>
            <div class="text-2xl font-bold">{format_cost(@totals.cost)}</div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Input Tokens</div>
            <div class="text-2xl font-bold">{format_tokens(@totals.input_tokens)}</div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Output Tokens</div>
            <div class="text-2xl font-bold">{format_tokens(@totals.output_tokens)}</div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Total Turns</div>
            <div class="text-2xl font-bold">{if @totals.turns > 0, do: @totals.turns, else: "—"}</div>
          </div>
        </div>

        <%!-- Per-task Table --%>
        <div class="bg-base-100 border border-base-300 rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-base-200/50 border-b border-base-300">
              <tr>
                <th class="text-left px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="title" class="hover:text-base-content">
                    Task{sort_indicator(:title, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-left px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="status" class="hover:text-base-content">
                    Status{sort_indicator(:status, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-right px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="cost" class="hover:text-base-content">
                    Cost{sort_indicator(:cost, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-right px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="input_tokens" class="hover:text-base-content">
                    Input Tokens{sort_indicator(:input_tokens, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-right px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="output_tokens" class="hover:text-base-content">
                    Output Tokens{sort_indicator(:output_tokens, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-right px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="total_tokens" class="hover:text-base-content">
                    Total Tokens{sort_indicator(:total_tokens, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-right px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="turns" class="hover:text-base-content">
                    Turns{sort_indicator(:turns, @sort_by, @sort_dir)}
                  </button>
                </th>
                <th class="text-right px-4 py-3 font-medium">
                  <button phx-click="sort" phx-value-col="duration" class="hover:text-base-content">
                    Duration{sort_indicator(:duration, @sort_by, @sort_dir)}
                  </button>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-300">
              <%= for task <- @sorted_tasks do %>
                <% {badge_class, badge_label} = status_badge(task.status) %>
                <tr class="hover:bg-base-200/30 transition-colors">
                  <td class="px-4 py-3">
                    <.link
                      navigate={~p"/projects/#{@project.id}/tasks/#{task.id}"}
                      class="font-medium hover:text-primary"
                    >
                      {task.title}
                    </.link>
                  </td>
                  <td class="px-4 py-3">
                    <span class={"text-xs px-2 py-0.5 rounded-full #{badge_class}"}>
                      {badge_label}
                    </span>
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-xs">
                    {format_cost(task.total_cost_usd)}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-xs">
                    {format_tokens(task.total_input_tokens)}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-xs">
                    {format_tokens(task.total_output_tokens)}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-xs">
                    {format_tokens((task.total_input_tokens || 0) + (task.total_output_tokens || 0))}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-xs">
                    {if task.num_turns && task.num_turns > 0, do: task.num_turns, else: "—"}
                  </td>
                  <td class="px-4 py-3 text-right font-mono text-xs">
                    {format_duration(task.duration_ms)}
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@tasks) do %>
                <tr>
                  <td colspan="8" class="px-4 py-8 text-center text-base-content/40">
                    No tasks yet
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
