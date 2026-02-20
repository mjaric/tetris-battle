defmodule Platform.Repo do
  use Ecto.Repo,
    otp_app: :tetris,
    adapter: Ecto.Adapters.Postgres
end
