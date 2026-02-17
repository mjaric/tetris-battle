defmodule TetrisWeb.CorsPlug do
  @moduledoc "Reads CORS origins from application env at request time for runtime configurability."

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    origins = Application.get_env(:tetris, :cors_origins, ["http://localhost:3000"])

    conn
    |> Corsica.call(Corsica.init(origins: origins, allow_headers: :all, allow_methods: :all))
  end
end
