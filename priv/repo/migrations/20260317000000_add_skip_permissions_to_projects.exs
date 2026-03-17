defmodule Foreman.Repo.Migrations.AddSkipPermissionsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :skip_permissions, :boolean, default: false, null: false
    end
  end
end
