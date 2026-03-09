defmodule Foreman.Repo.Migrations.AddKnowledgeSharing do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :knowledge_sharing, :boolean, default: false, null: false
    end

    alter table(:tasks) do
      add :summary, :text
    end
  end
end
