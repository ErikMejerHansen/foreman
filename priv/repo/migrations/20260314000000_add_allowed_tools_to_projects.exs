defmodule Foreman.Repo.Migrations.AddAllowedToolsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :allowed_tools, {:array, :string},
        null: false,
        default: [
          "Bash",
          "Read",
          "Edit",
          "MultiEdit",
          "Write",
          "Glob",
          "Grep",
          "TodoWrite",
          "TodoRead",
          "WebFetch",
          "WebSearch"
        ]
    end
  end
end
