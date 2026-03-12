defmodule Foreman.Agent.Runner do
  use GenServer
  require Logger

  defstruct [:task_id, :port, :session_id, :buffer, :worktree_path, seen_uuids: MapSet.new()]

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

    task = Foreman.Tasks.get_task!(state.task_id)
    Foreman.Tasks.move_to_failed(task)

    {:stop, :normal, %{state | port: nil, buffer: ""}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug(
      "Runner unhandled message for task #{state.task_id}: #{inspect(msg, limit: 200)}"
    )

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
        "--output-format",
        "stream-json",
        "--input-format",
        "stream-json",
        "--verbose",
        "--allowedTools",
        "Bash,Read,Edit,Write,Glob,Grep,TodoWrite,TodoRead"
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
        {:env,
         [
           # Clear CLAUDECODE so the spawned process doesn't think it's nested
           {~c"CLAUDECODE", false}
         ]}
      ])

    # Send the initial prompt via stdin as stream-json (required when --input-format stream-json is used)
    json_line =
      Jason.encode!(%{
        "type" => "user",
        "message" => %{
          "role" => "user",
          "content" => prompt
        }
      })

    Port.command(port, json_line <> "\n")

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
      {:ok, %{"uuid" => uuid}} when is_binary(uuid) and uuid != "" ->
        if MapSet.member?(state.seen_uuids, uuid) do
          Logger.debug("Skipping duplicate message uuid=#{uuid} for task #{state.task_id}")
          state
        else
          process_decoded_line(%{state | seen_uuids: MapSet.put(state.seen_uuids, uuid)}, line)
        end

      _ ->
        process_decoded_line(state, line)
    end
  end

  defp process_decoded_line(state, line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
        thinking = extract_thinking(content)
        text = extract_text(content)
        tool_uses = extract_tool_use(content)

        Logger.debug(
          "Claude assistant message for task #{state.task_id}: #{String.slice(text, 0, 100)}"
        )

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

        Enum.each(tool_uses, fn {role, content} ->
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => role,
            "content" => content
          })
        end)

        state

      # Result: error
      {:ok,
       %{
         "type" => "result",
         "is_error" => true,
         "session_id" => session_id
       } = result} ->
        error_text = result["result"] || ""
        Logger.error("Claude result error for task #{state.task_id}: #{error_text}")
        Foreman.Tasks.update_session_id(state.task_id, session_id)
        save_result_metadata(state.task_id, result)

        if error_text != "" do
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "system",
            "content" => error_text
          })
        end

        task = Foreman.Tasks.get_task!(state.task_id)
        Foreman.Tasks.move_to_failed(task)

        %{state | session_id: session_id}

      # Result: success with text
      {:ok, %{"type" => "result", "session_id" => session_id} = result} ->
        result_text = result["result"]
        Logger.info("Claude result for task #{state.task_id}, session: #{session_id}")
        Foreman.Tasks.update_session_id(state.task_id, session_id)
        save_result_metadata(state.task_id, result)

        if result_text && result_text != "" do
          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "assistant",
            "content" => result_text
          })
        end

        task = Foreman.Tasks.get_task!(state.task_id)
        Foreman.Tasks.move_to_review(task)

        %{state | session_id: session_id}

      # System init — capture session_id and model info
      {:ok, %{"type" => "system", "subtype" => "init", "session_id" => session_id} = init} ->
        model = init["model"] || "unknown"
        Logger.info("Claude init for task #{state.task_id}: model=#{model}")
        Foreman.Tasks.update_session_id(state.task_id, session_id)

        Foreman.Chat.create_message(%{
          "task_id" => state.task_id,
          "role" => "system",
          "content" => "Agent started (model: #{model})"
        })

        %{state | session_id: session_id}

      # Compaction status — agent is compacting context
      {:ok, %{"type" => "system", "subtype" => "status", "status" => "compacting"}} ->
        Foreman.Chat.create_message(%{
          "task_id" => state.task_id,
          "role" => "system",
          "content" => "Compacting context..."
        })

        state

      # Compact boundary — compaction completed
      {:ok, %{"type" => "system", "subtype" => "compact_boundary", "compact_metadata" => meta}} ->
        pre_tokens = meta["pre_tokens"]
        trigger = meta["trigger"] || "auto"

        content =
          if pre_tokens do
            "Context compacted (#{trigger}, was #{format_number(pre_tokens)} tokens)"
          else
            "Context compacted (#{trigger})"
          end

        Foreman.Chat.create_message(%{
          "task_id" => state.task_id,
          "role" => "system",
          "content" => content
        })

        state

      # Rate limit events
      {:ok, %{"type" => "rate_limit_event", "rate_limit_info" => info}} ->
        status = info["status"]

        if status in ["rejected", "allowed_warning"] do
          resets_at = info["resetsAt"]

          content =
            if resets_at do
              time = DateTime.from_unix!(resets_at) |> Calendar.strftime("%H:%M:%S")
              "Rate limited (#{status}) — resets at #{time}"
            else
              "Rate limited (#{status})"
            end

          Foreman.Chat.create_message(%{
            "task_id" => state.task_id,
            "role" => "system",
            "content" => content
          })
        end

        state

      # Tool use summary
      {:ok, %{"type" => "tool_use_summary", "summary" => summary}} ->
        Foreman.Chat.create_message(%{
          "task_id" => state.task_id,
          "role" => "tool_use",
          "content" => summary
        })

        state

      # Silently skip known event types that don't need user-facing messages
      {:ok, %{"type" => type}}
      when type in [
             "stream_event",
             "user",
             "tool_progress",
             "auth_status",
             "prompt_suggestion"
           ] ->
        state

      {:ok, %{"type" => "system", "subtype" => subtype}}
      when subtype in [
             "status",
             "hook_started",
             "hook_progress",
             "hook_response",
             "task_started",
             "task_progress",
             "task_notification",
             "files_persisted"
           ] ->
        state

      {:ok, %{"type" => type}} ->
        Logger.debug("Claude unhandled event type=#{type} for task #{state.task_id}")
        state

      {:ok, _other} ->
        Logger.debug(
          "Claude unknown event for task #{state.task_id}: #{String.slice(line, 0, 200)}"
        )

        state

      {:error, _error} ->
        if String.trim(line) != "" do
          Logger.warning(
            "Non-JSON from claude (task #{state.task_id}): #{String.slice(line, 0, 500)}"
          )
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

  defp extract_tool_use(content) when is_list(content) do
    content
    |> Enum.filter(&(is_map(&1) && &1["type"] == "tool_use"))
    |> Enum.map(fn tool ->
      name = tool["name"] || "unknown"
      input = tool["input"] || %{}
      {role, summary} = summarize_tool_use(name, input)
      {role, summary}
    end)
  end

  defp extract_tool_use(_), do: []

  defp summarize_tool_use("Bash", %{"command" => cmd}),
    do: {"tool_use", "Running Bash: #{String.slice(cmd, 0, 120)}"}

  defp summarize_tool_use("Read", %{"file_path" => path}), do: {"tool_use", "Reading #{path}"}
  defp summarize_tool_use("Edit", %{"file_path" => path}), do: {"tool_use", "Editing #{path}"}
  defp summarize_tool_use("Write", %{"file_path" => path}), do: {"tool_use", "Writing #{path}"}
  defp summarize_tool_use("Glob", %{"pattern" => pat}), do: {"tool_use", "Searching files: #{pat}"}
  defp summarize_tool_use("Grep", %{"pattern" => pat}), do: {"tool_use", "Searching content: #{pat}"}

  defp summarize_tool_use("TodoWrite", %{"todos" => todos}) when is_list(todos) do
    content =
      todos
      |> Enum.map(fn todo ->
        icon =
          case todo["status"] do
            "completed" -> "✓"
            "in_progress" -> "→"
            _ -> "○"
          end

        "#{icon} #{todo["content"]}"
      end)
      |> Enum.join("\n")

    {"todo", content}
  end

  defp summarize_tool_use(name, _input), do: {"tool_use", "Using #{name}"}

  defp save_result_metadata(task_id, result) do
    usage = result["usage"] || %{}

    Foreman.Tasks.update_result_metadata(task_id,
      total_cost_usd: result["total_cost_usd"],
      total_input_tokens: usage["input_tokens"],
      total_output_tokens: usage["output_tokens"],
      num_turns: result["num_turns"],
      duration_ms: result["duration_ms"]
    )
  end

  defp format_number(n) when is_integer(n) and n >= 1000 do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(n), do: to_string(n)
end
