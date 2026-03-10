defmodule ForemanWeb.TaskLive.Show do
  use ForemanWeb, :live_view

  alias Foreman.Tasks
  alias Foreman.Chat
  alias Foreman.Git
  alias Foreman.Projects

  @impl true
  def mount(%{"project_id" => project_id, "id" => task_id}, _session, socket) do
    task = Tasks.get_task!(task_id)
    project = Projects.get_project!(project_id)
    messages = Chat.list_messages(task_id)

    if connected?(socket) do
      Tasks.subscribe_task(task_id)
    end

    diff = load_diff(project, task)

    {:ok,
     socket
     |> assign(:task, task)
     |> assign(:project, project)
     |> assign(:messages, messages)
     |> assign(:diff, diff)
     |> assign(:message_input, "")
     |> assign(:page_title, task.title)
     |> assign(:merge_error, nil)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    task = socket.assigns.task

    # Always persist the user message first so it appears in chat
    Chat.create_message(%{
      "task_id" => task.id,
      "role" => "user",
      "content" => message
    })

    result =
      case task.status do
        "in_progress" ->
          Tasks.send_message_to_agent(task, message)

        "review" ->
          Tasks.send_feedback(task, message)

        _ ->
          :ok
      end

    socket =
      case result do
        {:error, reason} -> put_flash(socket, :error, "#{reason}")
        _ -> socket
      end

    {:noreply, assign(socket, :message_input, "")}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_message_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message_input, message)}
  end

  @impl true
  def handle_event("approve_and_merge", _params, socket) do
    task = socket.assigns.task

    case Tasks.move_to_done(task) do
      {:ok, task} ->
        {:noreply,
         socket
         |> assign(:task, task)
         |> assign(:merge_error, nil)
         |> put_flash(:info, "Changes merged to main!")}

      {:error, reason} ->
        {:noreply, assign(socket, :merge_error, reason)}
    end
  end

  @impl true
  def handle_event("start_task", _params, socket) do
    task = socket.assigns.task

    case Tasks.move_to_in_progress(task) do
      {:ok, task} ->
        {:noreply, assign(socket, :task, task)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "#{reason}")}
    end
  end

  @impl true
  def handle_event("resume_task", _params, socket) do
    task = socket.assigns.task

    case Tasks.resume_task(task) do
      {:ok, task} ->
        {:noreply, assign(socket, :task, task)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "#{reason}")}
    end
  end

  @impl true
  def handle_event("retry_task", _params, socket) do
    task = socket.assigns.task

    case Tasks.retry_failed(task) do
      {:ok, task} ->
        {:noreply, assign(socket, :task, task)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "#{reason}")}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    messages = socket.assigns.messages ++ [message]
    socket = assign(socket, :messages, messages)

    socket =
      if socket.assigns.task.status == "in_progress" do
        assign(socket, :diff, load_diff(socket.assigns.project, socket.assigns.task))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:status_changed, _new_status}, socket) do
    task = Tasks.get_task!(socket.assigns.task.id)
    diff = load_diff(socket.assigns.project, task)

    {:noreply,
     socket
     |> assign(:task, task)
     |> assign(:diff, diff)}
  end

  defp load_diff(project, %{status: status, branch_name: branch, worktree_path: worktree_path} = _task)
       when status in ["in_progress", "review"] and is_binary(branch) do
    {:ok, diff} = Git.diff(project.repo_path, branch, worktree_path)
    diff
  end

  defp load_diff(_project, _task), do: nil

  defp status_badge_class("todo"), do: "bg-base-200 text-base-content"
  defp status_badge_class("in_progress"), do: "bg-info/20 text-info"
  defp status_badge_class("review"), do: "bg-warning/20 text-warning"
  defp status_badge_class("done"), do: "bg-success/20 text-success"
  defp status_badge_class("failed"), do: "bg-error/20 text-error"

  defp status_label("todo"), do: "To Do"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("review"), do: "Review"
  defp status_label("done"), do: "Done"
  defp status_label("failed"), do: "Failed"

  defp can_chat?(status), do: status in ["in_progress", "review"]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Flash Messages --%>
      <Layouts.flash_group flash={@flash} />

      <%!-- Header --%>
      <div class="bg-base-100 border-b border-base-300 px-6 py-4">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/projects/#{@project.id}"}
            class="text-base-content/60 hover:text-base-content"
          >
            &larr; Board
          </.link>
          <h1 class="text-xl font-bold">{@task.title}</h1>
          <span class={"px-2 py-1 rounded text-xs font-medium #{status_badge_class(@task.status)}"}>
            {status_label(@task.status)}
          </span>
          <%= if @task.branch_name do %>
            <span class="text-sm text-info font-mono">{@task.branch_name}</span>
          <% end %>
          <%= if @task.total_cost_usd do %>
            <span class="text-xs text-base-content/50 font-mono">
              ${:erlang.float_to_binary(@task.total_cost_usd, decimals: 4)}
            </span>
          <% end %>
          <%= if @task.total_input_tokens do %>
            <span class="text-xs text-base-content/50 font-mono">
              {format_tokens(@task.total_input_tokens)} in / {format_tokens(
                @task.total_output_tokens || 0
              )} out
            </span>
          <% end %>
          <%= if @task.num_turns do %>
            <span class="text-xs text-base-content/50">
              {@task.num_turns} turns
            </span>
          <% end %>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden">
        <%!-- Left: Instructions + Chat --%>
        <div class="flex-1 flex flex-col border-r">
          <%!-- Instructions --%>
          <div class="p-4 border-b border-base-300 bg-base-200">
            <h2 class="text-sm font-semibold text-base-content/70 mb-2">Instructions</h2>
            <p class="text-sm whitespace-pre-wrap">{@task.instructions}</p>
            <%= if @task.status == "todo" do %>
              <button
                phx-click="start_task"
                class="mt-3 bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
              >
                Start Task
              </button>
            <% end %>
            <%= if @task.status == "failed" do %>
              <div class="mt-3 flex gap-2">
                <%= if @task.session_id do %>
                  <button
                    phx-click="resume_task"
                    class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
                  >
                    Resume Session
                  </button>
                <% end %>
                <button
                  phx-click="retry_task"
                  class="bg-base-300 text-base-content px-4 py-2 rounded hover:bg-base-400 text-sm"
                >
                  Restart Fresh
                </button>
              </div>
            <% end %>
          </div>

          <%!-- Chat Messages --%>
          <div class="flex-1 overflow-y-auto p-4 space-y-3" id="chat-messages" phx-hook="ScrollBottom">
            <%= if @messages == [] && @task.status == "todo" do %>
              <p class="text-base-content/40 text-center py-8">
                Start this task to begin the conversation with the agent.
              </p>
            <% end %>
            <%= for message <- @messages do %>
              <%= if message.role == "tool_use" do %>
                <div class="text-xs text-base-content/40 font-mono py-0.5">
                  🛠️ {message.content}
                </div>
              <% else if message.role == "system" && !usage_limit_message?(message.content) do %>
                <div class="text-xs text-base-content/40 font-mono py-0.5">
                  ⚙️ {message.content}
                </div>
              <% else %>
                <div class={[
                  "rounded-lg p-3 text-sm",
                  message_class(message.role)
                ]}>
                  <div class="font-semibold text-xs mb-1 uppercase tracking-wide opacity-60">
                    {message.role}
                  </div>
                  <div class="whitespace-pre-wrap break-words">{message.content}</div>
                </div>
              <% end %>
            <% end %>
          </div>

          <%!-- Chat Input --%>
          <%= if can_chat?(@task.status) do %>
            <div class="p-4 border-t border-base-300 bg-base-100">
              <form phx-submit="send_message" phx-change="update_message_input" class="flex gap-2">
                <input
                  type="text"
                  name="message"
                  value={@message_input}
                  class="flex-1 rounded border-base-300 bg-base-100 text-base-content shadow-sm focus:border-primary focus:ring-primary px-3 py-2"
                  placeholder="Send a message to the agent..."
                  autocomplete="off"
                />
                <button
                  type="submit"
                  class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                >
                  Send
                </button>
                <%= if @task.status in ["in_progress", "review"] do %>
                  <button
                    type="button"
                    phx-click="send_message"
                    phx-value-message="Please commit your current changes"
                    class="bg-base-300 text-base-content px-4 py-2 rounded hover:bg-base-400 text-sm whitespace-nowrap"
                  >
                    Commit changes
                  </button>
                <% end %>
              </form>
            </div>
          <% end %>
        </div>

        <%!-- Right: Diff (when in_progress or review) --%>
        <%= if @task.status in ["in_progress", "review"] do %>
          <div class="w-1/2 flex flex-col">
            <div class="p-4 border-b border-base-300 bg-base-200 flex justify-between items-center">
              <h2 class="text-sm font-semibold text-base-content/70">Changes</h2>
              <%= if @task.status == "review" do %>
                <button
                  phx-click="approve_and_merge"
                  class="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 text-sm"
                >
                  Approve & Merge
                </button>
              <% end %>
            </div>
            <%= if @merge_error do %>
              <div class="p-4 bg-error/10 border-b border-error/30 text-error text-sm">
                <strong>Error:</strong> {@merge_error}
              </div>
            <% end %>
            <div class="flex-1 overflow-auto p-4">
              <%= if @diff && @diff != "" do %>
                <pre class="text-xs font-mono whitespace-pre overflow-x-auto"><%= colorize_diff(@diff) %></pre>
              <% else %>
                <p class="text-base-content/40 text-center py-8">No changes yet.</p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp usage_limit_message?(content) do
    content = String.downcase(content)
    String.contains?(content, "usage limit") or String.contains?(content, "rate limit") or
      String.contains?(content, "quota")
  end

  defp message_class("user"), do: "bg-info/10 border border-info/20 ml-8"
  defp message_class("assistant"), do: "bg-base-200 border border-base-300 mr-8"
  defp message_class("system"), do: "bg-warning/10 border border-warning/20 text-center"

  defp message_class("thinking"),
    do: "bg-purple-500/10 border border-purple-500/20 mr-8 italic opacity-75"

  defp message_class(_), do: "bg-base-200 border border-base-300"

  defp format_tokens(n) when is_integer(n) and n >= 1000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_tokens(n), do: to_string(n)

  defp colorize_diff(diff) do
    diff
    |> String.split("\n")
    |> Enum.map(fn line ->
      class =
        cond do
          String.starts_with?(line, "+") && !String.starts_with?(line, "+++") -> "text-success"
          String.starts_with?(line, "-") && !String.starts_with?(line, "---") -> "text-error"
          String.starts_with?(line, "@@") -> "text-info"
          true -> ""
        end

      escaped = line |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      "<span class=\"#{class}\">#{escaped}</span>"
    end)
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end
end
