defmodule Foreman.Repo do
  use Ecto.Repo,
    otp_app: :foreman,
    adapter: Ecto.Adapters.Postgres
end
