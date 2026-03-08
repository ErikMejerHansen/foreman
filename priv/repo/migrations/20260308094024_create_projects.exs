defmodule Foreman.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :repo_path, :string, null: false

      timestamps()
    end
  end
end
