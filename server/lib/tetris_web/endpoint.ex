defmodule TetrisWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :tetris

  socket "/socket", TetrisWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Corsica,
    origins: ["http://localhost:3000"],
    allow_headers: :all,
    allow_methods: :all

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug TetrisWeb.Router
end
