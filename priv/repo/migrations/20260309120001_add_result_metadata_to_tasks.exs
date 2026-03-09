defmodule Foreman.Repo.Migrations.AddResultMetadataToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :total_cost_usd, :float
      add :total_input_tokens, :integer
      add :total_output_tokens, :integer
      add :num_turns, :integer
      add :duration_ms, :integer
    end
  end
end
