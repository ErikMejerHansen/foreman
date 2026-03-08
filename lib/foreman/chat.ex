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
