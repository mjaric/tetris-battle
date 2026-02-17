defmodule TetrisWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tetris

  socket("/socket", TetrisWeb.UserSocket,
    websocket: true,
    longpoll: false
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end

  plug TetrisWeb.CorsPlug

  plug Plug.Static,
    at: "/",
    from: {:tetris, "priv/static"},
    gzip: true

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(TetrisWeb.Router)
end
