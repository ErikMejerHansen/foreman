defmodule Foreman.Repo.Migrations.AddImagesToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :images, {:array, :map}, default: []
    end
  end
end
