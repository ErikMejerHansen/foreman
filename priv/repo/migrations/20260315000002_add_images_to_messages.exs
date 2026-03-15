defmodule Foreman.Repo.Migrations.AddImagesToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :images, {:array, :map}, default: []
    end
  end
end
