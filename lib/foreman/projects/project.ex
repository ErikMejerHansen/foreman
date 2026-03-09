defmodule Foreman.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :name, :string
    field :repo_path, :string
    field :knowledge_sharing, :boolean, default: false

    has_many :tasks, Foreman.Tasks.Task

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :repo_path, :knowledge_sharing])
    |> validate_required([:name, :repo_path])
  end
end
