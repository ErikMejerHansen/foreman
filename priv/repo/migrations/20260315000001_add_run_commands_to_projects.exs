defmodule Foreman.Repo.Migrations.AddRunCommandsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :run_commands, :text
    end
  end
end
