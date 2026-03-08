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
  def init(%{task_id: task_id, worktree_path: worktree_path, prompt: prompt} = args) do
    state = %__MODULE__{
      task_id: task_id,
      worktree_path: worktree_path,
      session_id: Map.get(args, :session_id),
      buffer: ""
    }

    Logger.info("Starting agent runner for task #{task_id} in #{worktree_path}")

    # Post the prompt as a user message unless caller already did it
    unless Map.get(args, :skip_chat_message, false) do
      Foreman.Chat.create_message(%{
        "task_id" => task_id,
        "role" => "user",
        "content" => prompt
      })
    end

    # Start the claude process
    case find_claude() do
      {:ok, claude_path} ->
        state = spawn_claude(state, prompt, claude_path)
        {:ok, state}

      {:error, reason} ->
        Logger.error("Cannot start agent for task #{task_id}: #{reason}")

        Foreman.Chat.create_message(%{
          "task_id" => task_id,
          "role" => "system",
          "content" => "Failed to start agent: #{reason}"
        })

        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:send_message, message}, state) do
    # Note: user message is already persisted by the LiveView before calling this

    if state.port && Port.info(state.port) do
      # Send message to the running claude process via stdin as NDJSON
      json_line =
        Jason.encode!(%{
          "type" => "user",
          "message" => %{
            "role" => "user",
            "content" => message
          }
        })

      Port.command(state.port, json_line <> "\r\n")
      Logger.info("Sent message to claude stdin for task #{state.task_id}")
      {:noreply, state}
    else
      # Port is not running (process exited), start a new session with --resume
      Logger.info("Starting new claude session for task #{state.task_id}")

      case find_claude() do
        {:ok, claude_path} ->
          state = spawn_claude(state, message, claude_path)
          {:noreply, state}

        {:error, reason} ->
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "system",
            "content" => "Failed to start agent: #{reason}"
          })

          {:noreply, %{state | port: nil}}
      end
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    Logger.debug("Claude port data (#{byte_size(data)} bytes) for task #{state.task_id}")

    # Append to buffer and process complete lines
    buffer = state.buffer <> data
    {lines, remaining} = split_lines(buffer)

    state =
      %{state | buffer: remaining}
      |> process_lines(lines)

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    Logger.info("Claude process exited normally for task #{state.task_id}")

    # Flush remaining buffer
    state =
      if state.buffer != "" do
        process_lines(state, [state.buffer])
      else
        state
      end

    {:noreply, %{state | port: nil, buffer: ""}}
  end

  @impl true
  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    Logger.error("Claude process exited with code #{code} for task #{state.task_id}")

    # Flush remaining buffer
    state =
      if state.buffer != "" do
        process_lines(state, [state.buffer])
      else
        state
      end

    Foreman.Chat.create_message(%{
      "task_id" => state.task_id,
      "role" => "system",
      "content" => "Agent exited with code #{code}"
    })

    {:noreply, %{state | port: nil, buffer: ""}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Runner unhandled message for task #{state.task_id}: #{inspect(msg, limit: 200)}")
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

  defp find_claude do
    # Check common locations since PATH may differ when running as a server
    candidates = [
      System.find_executable("claude"),
      Path.expand("~/.claude/local/bin/claude"),
      Path.expand("~/.local/bin/claude"),
      "/usr/local/bin/claude",
      "/opt/homebrew/bin/claude"
    ]

    case Enum.find(candidates, fn path -> path && File.exists?(path || "") end) do
      nil -> {:error, "claude CLI not found in PATH or common locations"}
      path -> {:ok, path}
    end
  end

  defp spawn_claude(state, prompt, claude_path) do
    args =
      [
        "-p",
        prompt,
        "--output-format",
        "stream-json",
        "--input-format",
        "stream-json",
        "--verbose",
        "--allowedTools",
        "Bash,Read,Edit,Write,Glob,Grep"
      ]

    # Add --resume if we have a session_id from a previous run
    args =
      if state.session_id do
        args ++ ["--resume", state.session_id]
      else
        args
      end

    Logger.info("Spawning claude at #{claude_path} in #{state.worktree_path}")
    Logger.debug("Claude args: #{inspect(args)}")

    port =
      Port.open({:spawn_executable, claude_path}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:cd, state.worktree_path},
        {:args, args},
        {:env, [
          # Clear CLAUDECODE so the spawned process doesn't think it's nested
          {~c"CLAUDECODE", false}
        ]}
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

  defp process_lines(state, lines) do
    Enum.reduce(lines, state, fn line, acc -> process_stream_line(acc, line) end)
  end

  defp process_stream_line(state, line) do
    Logger.debug("Claude raw message (task #{state.task_id}): #{line}")

    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
        thinking = extract_thinking(content)
        text = extract_text(content)
        Logger.debug("Claude assistant message for task #{state.task_id}: #{String.slice(text, 0, 100)}")

        if thinking != "" do
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "thinking",
            "content" => thinking
          })
        end

        if text != "" do
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "assistant",
            "content" => text
          })
        end

        state

      {:ok, %{"type" => "result", "result" => result_text, "session_id" => session_id}} ->
        Logger.info("Claude result for task #{state.task_id}, session: #{session_id}")
        Foreman.Tasks.update_session_id(state.task_id, session_id)

        if result_text && result_text != "" do
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "assistant",
            "content" => result_text
          })
        end

        # Move task to review — agent finished this turn
        task = Foreman.Tasks.get_task!(state.task_id)
        Foreman.Tasks.move_to_review(task)

        %{state | session_id: session_id}

      {:ok, %{"type" => "result", "session_id" => session_id}} ->
        Logger.info("Claude result (no text) for task #{state.task_id}, session: #{session_id}")
        Foreman.Tasks.update_session_id(state.task_id, session_id)

        task = Foreman.Tasks.get_task!(state.task_id)
        Foreman.Tasks.move_to_review(task)

        %{state | session_id: session_id}

      {:ok, %{"type" => type}} ->
        Logger.debug("Claude event type=#{type} for task #{state.task_id}")
        state

      {:ok, _other} ->
        Logger.debug("Claude unknown event for task #{state.task_id}: #{String.slice(line, 0, 200)}")
        state

      {:error, _error} ->
        if String.trim(line) != "" do
          Logger.warning("Non-JSON from claude (task #{state.task_id}): #{String.slice(line, 0, 500)}")
        end

        state
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

  defp extract_thinking(content) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) && &1["type"] == "thinking"))
    |> Enum.map(& &1["thinking"])
    |> Enum.join("")
  end

  defp extract_thinking(_), do: ""
end
