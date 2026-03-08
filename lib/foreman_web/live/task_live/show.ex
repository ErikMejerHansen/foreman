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
  def handle_info({:new_message, message}, socket) do
    messages = socket.assigns.messages ++ [message]
    {:noreply, assign(socket, :messages, messages)}
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

  defp load_diff(project, %{status: "review", branch_name: branch} = _task)
       when is_binary(branch) do
    case Git.diff(project.repo_path, branch) do
      {:ok, diff} -> diff
      {:error, _} -> nil
    end
  end

  defp load_diff(_project, _task), do: nil

  defp status_badge_class("todo"), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
  defp status_badge_class("in_progress"), do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300"
  defp status_badge_class("review"), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300"
  defp status_badge_class("done"), do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300"

  defp status_label("todo"), do: "To Do"
  defp status_label("in_progress"), do: "In Progress"
  defp status_label("review"), do: "Review"
  defp status_label("done"), do: "Done"

  defp can_chat?(status), do: status in ["in_progress", "review"]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Flash Messages --%>
      <Layouts.flash_group flash={@flash} />

      <%!-- Header --%>
      <div class="bg-white dark:bg-gray-900 border-b dark:border-gray-700 px-6 py-4">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/projects/#{@project.id}"} class="text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200">
            &larr; Board
          </.link>
          <h1 class="text-xl font-bold">{@task.title}</h1>
          <span class={"px-2 py-1 rounded text-xs font-medium #{status_badge_class(@task.status)}"}>
            {status_label(@task.status)}
          </span>
          <%= if @task.branch_name do %>
            <span class="text-sm text-blue-600 dark:text-blue-400 font-mono">{@task.branch_name}</span>
          <% end %>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden">
        <%!-- Left: Instructions + Chat --%>
        <div class="flex-1 flex flex-col border-r">
          <%!-- Instructions --%>
          <div class="p-4 border-b dark:border-gray-700 bg-gray-50 dark:bg-gray-800">
            <h2 class="text-sm font-semibold text-gray-600 dark:text-gray-400 mb-2">Instructions</h2>
            <p class="text-sm whitespace-pre-wrap">{@task.instructions}</p>
            <%= if @task.status == "todo" do %>
              <button
                phx-click="start_task"
                class="mt-3 bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 text-sm"
              >
                Start Task
              </button>
            <% end %>
          </div>

          <%!-- Chat Messages --%>
          <div class="flex-1 overflow-y-auto p-4 space-y-3" id="chat-messages" phx-hook="ScrollBottom">
            <%= if @messages == [] && @task.status == "todo" do %>
              <p class="text-gray-400 dark:text-gray-500 text-center py-8">
                Start this task to begin the conversation with the agent.
              </p>
            <% end %>
            <%= for message <- @messages do %>
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
          </div>

          <%!-- Chat Input --%>
          <%= if can_chat?(@task.status) do %>
            <div class="p-4 border-t dark:border-gray-700 bg-white dark:bg-gray-900">
              <form phx-submit="send_message" phx-change="update_message_input" class="flex gap-2">
                <input
                  type="text"
                  name="message"
                  value={@message_input}
                  class="flex-1 rounded border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                  placeholder="Send a message to the agent..."
                  autocomplete="off"
                />
                <button
                  type="submit"
                  class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                >
                  Send
                </button>
              </form>
            </div>
          <% end %>
        </div>

        <%!-- Right: Diff (when in review) --%>
        <%= if @task.status == "review" do %>
          <div class="w-1/2 flex flex-col">
            <div class="p-4 border-b dark:border-gray-700 bg-gray-50 dark:bg-gray-800 flex justify-between items-center">
              <h2 class="text-sm font-semibold text-gray-600 dark:text-gray-400">Changes</h2>
              <button
                phx-click="approve_and_merge"
                class="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 text-sm"
              >
                Approve & Merge
              </button>
            </div>
            <%= if @merge_error do %>
              <div class="p-4 bg-red-50 dark:bg-red-900/30 border-b border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 text-sm">
                <strong>Error:</strong> {@merge_error}
              </div>
            <% end %>
            <div class="flex-1 overflow-auto p-4">
              <%= if @diff do %>
                <pre class="text-xs font-mono whitespace-pre overflow-x-auto"><%= colorize_diff(@diff) %></pre>
              <% else %>
                <p class="text-gray-400 dark:text-gray-500 text-center py-8">No changes to display.</p>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp message_class("user"), do: "bg-blue-50 dark:bg-blue-900/30 border border-blue-200 dark:border-blue-700 ml-8"
  defp message_class("assistant"), do: "bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-600 mr-8"
  defp message_class("system"), do: "bg-yellow-50 dark:bg-yellow-900/30 border border-yellow-200 dark:border-yellow-700 text-center"
  defp message_class(_), do: "bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-600"

  defp colorize_diff(diff) do
    diff
    |> String.split("\n")
    |> Enum.map(fn line ->
      class =
        cond do
          String.starts_with?(line, "+") && !String.starts_with?(line, "+++") -> "text-green-600 dark:text-green-400"
          String.starts_with?(line, "-") && !String.starts_with?(line, "---") -> "text-red-600 dark:text-red-400"
          String.starts_with?(line, "@@") -> "text-blue-600 dark:text-blue-400"
          true -> ""
        end

      escaped = line |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      "<span class=\"#{class}\">#{escaped}</span>"
    end)
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end
end
