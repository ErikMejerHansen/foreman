defmodule Foreman.Repo.Migrations.AddChromeUrlToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :chrome_url, :string
    end
  end
end
