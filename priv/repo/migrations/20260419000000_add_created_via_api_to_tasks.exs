defmodule Foreman.Repo.Migrations.AddCreatedViaApiToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :created_via_api, :boolean, default: false, null: false
    end
  end
end
