defmodule Foreman.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @all_tools ~w(Bash Read Edit MultiEdit Write Glob Grep TodoWrite TodoRead WebFetch WebSearch)

  def all_tools, do: @all_tools

  schema "projects" do
    field :name, :string
    field :repo_path, :string
    field :allowed_tools, {:array, :string}, default: @all_tools

    has_many :tasks, Foreman.Tasks.Task

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :repo_path, :allowed_tools])
    |> validate_required([:name, :repo_path])
  end
end
