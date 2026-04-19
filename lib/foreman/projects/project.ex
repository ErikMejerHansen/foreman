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
    field :run_commands, :string
    field :skip_permissions, :boolean, default: false
    field :chrome_url, :string
    field :total_cost_usd, :decimal, virtual: true

    has_many :tasks, Foreman.Tasks.Task

    timestamps()
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :repo_path, :allowed_tools, :run_commands, :skip_permissions, :chrome_url])
    |> validate_required([:name, :repo_path])
  end
end
