defmodule Foreman.Repo.Migrations.AddCacheTokensToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :cache_creation_input_tokens, :integer
      add :cache_read_input_tokens, :integer
    end
  end
end
