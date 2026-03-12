defmodule Foreman.Repo.Migrations.RemoveKnowledgeSharing do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      remove :knowledge_sharing
    end

    alter table(:tasks) do
      remove :summary
    end
  end
end
