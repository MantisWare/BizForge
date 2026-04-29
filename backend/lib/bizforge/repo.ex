defmodule Bizforge.Repo do
  use Ecto.Repo,
    otp_app: :bizforge,
    adapter: Ecto.Adapters.Postgres
end
