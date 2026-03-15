defmodule Foreman.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(user assistant system thinking tool_use todo web_fetch web_search)

  schema "messages" do
    field :role, :string
    field :content, :string
    field :images, {:array, :map}, default: []

    belongs_to :task, Foreman.Tasks.Task

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :task_id, :images])
    |> validate_required([:role, :content, :task_id])
    |> validate_inclusion(:role, @roles)
  end
end
