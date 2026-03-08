defmodule Foreman.Agent.Runner do
  use GenServer
  require Logger

  defstruct [:task_id, :port, :session_id, :buffer, :worktree_path]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args,
      name: {:via, Registry, {Foreman.Agent.Registry, args.task_id}}
    )
  end

  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end

  # Server callbacks

  @impl true
  def init(%{task_id: task_id, worktree_path: worktree_path, instructions: instructions} = args) do
    state = %__MODULE__{
      task_id: task_id,
      worktree_path: worktree_path,
      session_id: Map.get(args, :session_id),
      buffer: ""
    }

    # Start the claude process
    state = spawn_claude(state, instructions)
    {:ok, state}
  end

  @impl true
  def handle_cast({:send_message, message}, state) do
    # Persist the user message
    Foreman.Chat.create_message(%{
      "task_id" => state.task_id,
      "role" => "user",
      "content" => message
    })

    # If there's an existing port, close it first
    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    state = spawn_claude(state, message)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Append to buffer and process complete lines
    buffer = state.buffer <> data
    {lines, remaining} = split_lines(buffer)

    state = %{state | buffer: remaining}

    Enum.each(lines, fn line ->
      process_stream_line(state.task_id, line, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    Logger.info("Claude agent completed for task #{state.task_id}")

    # Flush remaining buffer
    if state.buffer != "" do
      process_stream_line(state.task_id, state.buffer, state)
    end

    # Move task to review
    task = Foreman.Tasks.get_task!(state.task_id)
    Foreman.Tasks.move_to_review(task)

    {:noreply, %{state | port: nil, buffer: ""}}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.error("Claude agent failed for task #{state.task_id} with exit code #{code}")

    # Flush remaining buffer
    if state.buffer != "" do
      process_stream_line(state.task_id, state.buffer, state)
    end

    Foreman.Chat.create_message(%{
      "task_id" => state.task_id,
      "role" => "system",
      "content" => "Agent exited with code #{code}"
    })

    {:noreply, %{state | port: nil, buffer: ""}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    :ok
  end

  # Private

  defp spawn_claude(state, prompt) do
    claude_path = System.find_executable("claude") || raise "claude CLI not found in PATH"

    args =
      if state.session_id do
        ["-p", prompt, "--resume", state.session_id, "--output-format", "stream-json",
         "--verbose", "--allowedTools", "Bash,Read,Edit,Write,Glob,Grep"]
      else
        ["-p", prompt, "--output-format", "stream-json",
         "--verbose", "--allowedTools", "Bash,Read,Edit,Write,Glob,Grep"]
      end

    port =
      Port.open({:spawn_executable, claude_path}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:cd, state.worktree_path},
        {:args, args}
      ])

    %{state | port: port}
  end

  defp split_lines(data) do
    parts = String.split(data, "\n")

    case parts do
      [single] ->
        {[], single}

      multiple ->
        {complete, [remaining]} = Enum.split(multiple, -1)
        {Enum.reject(complete, &(&1 == "")), remaining}
    end
  end

  defp process_stream_line(task_id, line, _state) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
        text = extract_text(content)

        if text != "" do
          Foreman.Chat.create_message(%{
            "task_id" => task_id,
            "role" => "assistant",
            "content" => text
          })
        end

      {:ok, %{"type" => "result", "result" => result_text, "session_id" => session_id}} ->
        Foreman.Tasks.update_session_id(task_id, session_id)

        if result_text && result_text != "" do
          Foreman.Chat.create_message(%{
            "task_id" => task_id,
            "role" => "assistant",
            "content" => result_text
          })
        end

      {:ok, %{"type" => "result", "session_id" => session_id}} ->
        Foreman.Tasks.update_session_id(task_id, session_id)

      {:ok, _other} ->
        :ok

      {:error, _} ->
        if String.trim(line) != "" do
          Logger.debug("Non-JSON output from claude: #{String.slice(line, 0, 200)}")
        end
    end
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) && &1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("")
  end

  defp extract_text(content) when is_binary(content), do: content
  defp extract_text(_), do: ""
end
