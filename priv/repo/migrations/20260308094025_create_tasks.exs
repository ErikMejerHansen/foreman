defmodule Foreman.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :title, :string, null: false
      add :instructions, :text, null: false
      add :status, :string, null: false, default: "todo"
      add :position, :integer, null: false, default: 0
      add :branch_name, :string
      add :worktree_path, :string
      add :session_id, :string

      timestamps()
    end

    create index(:tasks, [:project_id])
    create index(:tasks, [:project_id, :status])
  end
end
