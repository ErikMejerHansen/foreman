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
     |> assign(:sort_dir, :desc)
     |> assign(:view, :table)}
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

  @impl true
  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply, assign(socket, :view, String.to_existing_atom(view))}
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
    do:
      (task.total_input_tokens || 0) + (task.total_output_tokens || 0) +
        (task.cache_creation_input_tokens || 0) + (task.cache_read_input_tokens || 0)
  defp task_sort_value(task, :cache_write), do: task.cache_creation_input_tokens || 0
  defp task_sort_value(task, :cache_read), do: task.cache_read_input_tokens || 0
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
      cache_creation_input_tokens:
        tasks |> Enum.map(&(&1.cache_creation_input_tokens || 0)) |> Enum.sum(),
      cache_read_input_tokens:
        tasks |> Enum.map(&(&1.cache_read_input_tokens || 0)) |> Enum.sum(),
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

  # --- Chart config builders ---

  defp truncate(str, max) do
    if String.length(str) > max, do: String.slice(str, 0, max - 1) <> "…", else: str
  end

  defp chart_colors do
    %{
      blue: "rgba(96, 165, 250, 0.8)",
      blue_border: "rgba(96, 165, 250, 1)",
      emerald: "rgba(52, 211, 153, 0.8)",
      emerald_border: "rgba(52, 211, 153, 1)",
      amber: "rgba(251, 191, 36, 0.8)",
      amber_border: "rgba(251, 191, 36, 1)",
      red: "rgba(248, 113, 113, 0.8)",
      red_border: "rgba(248, 113, 113, 1)",
      violet: "rgba(167, 139, 250, 0.8)",
      violet_border: "rgba(167, 139, 250, 1)",
      gray: "rgba(156, 163, 175, 0.8)",
      gray_border: "rgba(156, 163, 175, 1)"
    }
  end

  defp base_options(title) do
    %{
      responsive: true,
      maintainAspectRatio: false,
      plugins: %{
        legend: %{display: false},
        title: %{display: true, text: title, font: %{size: 13}, padding: %{bottom: 12}}
      },
      scales: %{
        x: %{ticks: %{maxRotation: 45, font: %{size: 10}}},
        y: %{beginAtZero: true}
      }
    }
  end

  defp cost_chart(labels, tasks) do
    c = chart_colors()
    %{
      type: "bar",
      data: %{
        labels: labels,
        datasets: [%{
          label: "Cost (USD)",
          data: Enum.map(tasks, &Float.round(&1.total_cost_usd || 0.0, 6)),
          backgroundColor: c.blue,
          borderColor: c.blue_border,
          borderWidth: 1,
          borderRadius: 3
        }]
      },
      options: base_options("Cost per Task (USD)")
    }
  end

  defp tokens_chart(labels, tasks) do
    c = chart_colors()
    %{
      type: "bar",
      data: %{
        labels: labels,
        datasets: [
          %{
            label: "Input Tokens",
            data: Enum.map(tasks, &(&1.total_input_tokens || 0)),
            backgroundColor: c.blue,
            borderColor: c.blue_border,
            borderWidth: 1,
            borderRadius: 3,
            stack: "tokens"
          },
          %{
            label: "Cache Write",
            data: Enum.map(tasks, &(&1.cache_creation_input_tokens || 0)),
            backgroundColor: c.amber,
            borderColor: c.amber_border,
            borderWidth: 1,
            borderRadius: 3,
            stack: "tokens"
          },
          %{
            label: "Cache Read",
            data: Enum.map(tasks, &(&1.cache_read_input_tokens || 0)),
            backgroundColor: c.violet,
            borderColor: c.violet_border,
            borderWidth: 1,
            borderRadius: 3,
            stack: "tokens"
          },
          %{
            label: "Output Tokens",
            data: Enum.map(tasks, &(&1.total_output_tokens || 0)),
            backgroundColor: c.emerald,
            borderColor: c.emerald_border,
            borderWidth: 1,
            borderRadius: 3,
            stack: "tokens"
          }
        ]
      },
      options: Map.merge(base_options("Token Usage per Task"), %{
        plugins: %{
          legend: %{display: true, position: "top", labels: %{font: %{size: 11}, boxWidth: 12}},
          title: %{display: true, text: "Token Usage per Task", font: %{size: 13}, padding: %{bottom: 12}}
        }
      })
    }
  end

  defp turns_chart(labels, tasks) do
    c = chart_colors()
    %{
      type: "bar",
      data: %{
        labels: labels,
        datasets: [%{
          label: "Turns",
          data: Enum.map(tasks, &(&1.num_turns || 0)),
          backgroundColor: c.amber,
          borderColor: c.amber_border,
          borderWidth: 1,
          borderRadius: 3
        }]
      },
      options: base_options("Turns per Task")
    }
  end

  defp status_chart(tasks) do
    c = chart_colors()
    counts = Enum.frequencies_by(tasks, & &1.status)
    statuses = ["done", "in_progress", "review", "todo", "failed"]
    labels = ["Done", "In Progress", "Review", "To Do", "Failed"]
    colors = [c.emerald, c.blue, c.amber, c.gray, c.red]
    border_colors = [c.emerald_border, c.blue_border, c.amber_border, c.gray_border, c.red_border]
    data = Enum.map(statuses, &Map.get(counts, &1, 0))

    # Filter out zero-count statuses
    {labels, colors, border_colors, data} =
      Enum.zip([labels, colors, border_colors, data])
      |> Enum.filter(fn {_, _, _, d} -> d > 0 end)
      |> unzip4()

    %{
      type: "doughnut",
      data: %{
        labels: labels,
        datasets: [%{
          data: data,
          backgroundColor: colors,
          borderColor: border_colors,
          borderWidth: 2
        }]
      },
      options: %{
        responsive: true,
        maintainAspectRatio: false,
        plugins: %{
          legend: %{display: true, position: "bottom", labels: %{font: %{size: 11}, boxWidth: 12, padding: 8}},
          title: %{display: true, text: "Task Status Breakdown", font: %{size: 13}, padding: %{bottom: 8}}
        }
      }
    }
  end

  defp duration_chart(labels, tasks) do
    c = chart_colors()
    %{
      type: "bar",
      data: %{
        labels: labels,
        datasets: [%{
          label: "Duration (min)",
          data: Enum.map(tasks, fn t -> Float.round((t.duration_ms || 0) / 60_000, 1) end),
          backgroundColor: c.violet,
          borderColor: c.violet_border,
          borderWidth: 1,
          borderRadius: 3
        }]
      },
      options: base_options("Duration per Task (minutes)")
    }
  end

  defp build_chart_configs(tasks_with_data, all_tasks) do
    labels = Enum.map(tasks_with_data, fn t -> truncate(t.title || "Untitled", 20) end)

    [
      cost_chart(labels, tasks_with_data),
      tokens_chart(labels, tasks_with_data),
      turns_chart(labels, tasks_with_data),
      status_chart(all_tasks),
      duration_chart(labels, tasks_with_data)
    ]
  end

  defp averages([]), do: %{cost: nil, input_tokens: nil, output_tokens: nil, turns: nil}

  defp averages(tasks) do
    count = length(tasks)

    %{
      cost: tasks |> Enum.map(&(&1.total_cost_usd || 0.0)) |> Enum.sum() |> Kernel./(count),
      input_tokens:
        tasks |> Enum.map(&(&1.total_input_tokens || 0)) |> Enum.sum() |> Kernel./(count) |> round(),
      output_tokens:
        tasks |> Enum.map(&(&1.total_output_tokens || 0)) |> Enum.sum() |> Kernel./(count) |> round(),
      turns: tasks |> Enum.map(&(&1.num_turns || 0)) |> Enum.sum() |> Kernel./(count) |> round()
    }
  end

  defp trends(tasks) when length(tasks) < 2,
    do: %{cost: :neutral, input_tokens: :neutral, output_tokens: :neutral, turns: :neutral}

  defp trends(tasks) do
    mid = div(length(tasks), 2)
    first_avgs = averages(Enum.take(tasks, mid))
    second_avgs = averages(Enum.drop(tasks, mid))

    compare = fn key ->
      f = Map.get(first_avgs, key) || 0
      s = Map.get(second_avgs, key) || 0

      cond do
        s > f -> :up
        s < f -> :down
        true -> :neutral
      end
    end

    %{
      cost: compare.(:cost),
      input_tokens: compare.(:input_tokens),
      output_tokens: compare.(:output_tokens),
      turns: compare.(:turns)
    }
  end

  defp unzip4(list) do
    {as, bs, cs, ds} =
      Enum.reduce(list, {[], [], [], []}, fn {a, b, c, d}, {as, bs, cs, ds} ->
        {[a | as], [b | bs], [c | cs], [d | ds]}
      end)
    {Enum.reverse(as), Enum.reverse(bs), Enum.reverse(cs), Enum.reverse(ds)}
  end

  @impl true
  def render(assigns) do
    tasks_with_data =
      assigns.tasks
      |> Enum.filter(&(&1.total_cost_usd || &1.total_input_tokens || &1.num_turns))
      |> Enum.sort_by(& &1.inserted_at)

    totals = totals(tasks_with_data)
    sorted = sort_tasks(assigns.tasks, assigns.sort_by, assigns.sort_dir)
    chart_configs = build_chart_configs(tasks_with_data, assigns.tasks)

    avgs = averages(tasks_with_data)
    task_trends = trends(tasks_with_data)

    assigns =
      assign(assigns,
        totals: totals,
        avgs: avgs,
        task_trends: task_trends,
        sorted_tasks: sorted,
        chart_configs_json: Jason.encode!(chart_configs)
      )

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
        <div class="flex items-center gap-4">
          <Layouts.theme_toggle />
          <div class="flex items-center gap-1 bg-base-200 rounded-lg p-1">
          <button
            phx-click="set_view"
            phx-value-view="table"
            class={"px-3 py-1.5 rounded-md text-sm transition-colors #{if @view == :table, do: "bg-base-100 shadow-sm font-medium", else: "text-base-content/60 hover:text-base-content"}"}
          >
            Table
          </button>
          <button
            phx-click="set_view"
            phx-value-view="charts"
            class={"px-3 py-1.5 rounded-md text-sm transition-colors #{if @view == :charts, do: "bg-base-100 shadow-sm font-medium", else: "text-base-content/60 hover:text-base-content"}"}
          >
            Charts
          </button>
          </div>
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

        <%!-- Average Cards --%>
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Avg Cost</div>
            <div class="flex items-baseline gap-1.5">
              <div class="text-xl font-bold">{format_cost(@avgs.cost)}</div>
              <%= if @task_trends.cost != :neutral do %>
                <span class={if @task_trends.cost == :up, do: "text-error text-sm font-bold", else: "text-success text-sm font-bold"}>
                  {if @task_trends.cost == :up, do: "↑", else: "↓"}
                </span>
              <% end %>
            </div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Avg Input Tokens</div>
            <div class="flex items-baseline gap-1.5">
              <div class="text-xl font-bold">{format_tokens(@avgs.input_tokens)}</div>
              <%= if @task_trends.input_tokens != :neutral do %>
                <span class={if @task_trends.input_tokens == :up, do: "text-error text-sm font-bold", else: "text-success text-sm font-bold"}>
                  {if @task_trends.input_tokens == :up, do: "↑", else: "↓"}
                </span>
              <% end %>
            </div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Avg Output Tokens</div>
            <div class="flex items-baseline gap-1.5">
              <div class="text-xl font-bold">{format_tokens(@avgs.output_tokens)}</div>
              <%= if @task_trends.output_tokens != :neutral do %>
                <span class={if @task_trends.output_tokens == :up, do: "text-error text-sm font-bold", else: "text-success text-sm font-bold"}>
                  {if @task_trends.output_tokens == :up, do: "↑", else: "↓"}
                </span>
              <% end %>
            </div>
          </div>
          <div class="bg-base-100 border border-base-300 rounded-lg p-4">
            <div class="text-xs text-base-content/50 uppercase tracking-wide mb-1">Avg Turns</div>
            <div class="flex items-baseline gap-1.5">
              <div class="text-xl font-bold">{if (@avgs.turns || 0) > 0, do: @avgs.turns, else: "—"}</div>
              <%= if @task_trends.turns != :neutral do %>
                <span class={if @task_trends.turns == :up, do: "text-error text-sm font-bold", else: "text-success text-sm font-bold"}>
                  {if @task_trends.turns == :up, do: "↑", else: "↓"}
                </span>
              <% end %>
            </div>
          </div>
        </div>

        <%= if @view == :table do %>
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
                  <th class="text-right px-4 py-3 font-medium text-amber-600/80">
                    <button phx-click="sort" phx-value-col="cache_write" class="hover:text-base-content">
                      Cache Write{sort_indicator(:cache_write, @sort_by, @sort_dir)}
                    </button>
                  </th>
                  <th class="text-right px-4 py-3 font-medium text-violet-600/80">
                    <button phx-click="sort" phx-value-col="cache_read" class="hover:text-base-content">
                      Cache Read{sort_indicator(:cache_read, @sort_by, @sort_dir)}
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
                    <td class="px-4 py-3 text-right font-mono text-xs text-amber-600/80">
                      {format_tokens(task.cache_creation_input_tokens)}
                    </td>
                    <td class="px-4 py-3 text-right font-mono text-xs text-violet-600/80">
                      {format_tokens(task.cache_read_input_tokens)}
                    </td>
                    <td class="px-4 py-3 text-right font-mono text-xs">
                      {format_tokens(
                        (task.total_input_tokens || 0) + (task.total_output_tokens || 0) +
                          (task.cache_creation_input_tokens || 0) +
                          (task.cache_read_input_tokens || 0)
                      )}
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
                    <td colspan="10" class="px-4 py-8 text-center text-base-content/40">
                      No tasks yet
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>

        <%= if @view == :charts do %>
          <%= if Enum.empty?(@tasks) do %>
            <div class="bg-base-100 border border-base-300 rounded-lg p-12 text-center text-base-content/40">
              No task data to chart yet
            </div>
          <% else %>
            <div
              id="charts-container"
              phx-hook="Charts"
              data-charts={@chart_configs_json}
              class="grid grid-cols-1 md:grid-cols-2 gap-4"
            >
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
