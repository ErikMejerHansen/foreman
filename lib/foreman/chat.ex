defmodule Foreman.Chat do
  import Ecto.Query
  alias Foreman.Repo
  alias Foreman.Chat.Message

  def list_messages(task_id) do
    Repo.all(
      from m in Message,
        where: m.task_id == ^task_id,
        order_by: [asc: m.inserted_at]
    )
  end

  def create_message(attrs) do
    task_id = attrs["task_id"]
    role = attrs["role"]
    content = attrs["content"]

    if duplicate_message?(task_id, role, content) do
      {:error, :duplicate}
    else
      result =
        %Message{}
        |> Message.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, message} ->
          Foreman.Tasks.broadcast_task(message.task_id, {:new_message, message})
          {:ok, message}

        error ->
          error
      end
    end
  end

  defp duplicate_message?(task_id, role, content)
       when is_binary(task_id) and is_binary(role) and is_binary(content) and content != "" do
    Repo.exists?(
      from m in Message,
        where:
          m.task_id == ^task_id and
            m.role == ^role and
            m.content == ^content
    )
  end

  defp duplicate_message?(_, _, _), do: false
end
