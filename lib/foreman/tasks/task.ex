defmodule Foreman.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(todo in_progress review done)

  schema "tasks" do
    field :title, :string
    field :instructions, :string
    field :status, :string, default: "todo"
    field :position, :integer, default: 0
    field :branch_name, :string
    field :worktree_path, :string
    field :session_id, :string

    belongs_to :project, Foreman.Projects.Project
    has_many :messages, Foreman.Chat.Message

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :instructions,
      :status,
      :position,
      :branch_name,
      :worktree_path,
      :session_id,
      :project_id
    ])
    |> validate_required([:title, :instructions, :project_id])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
