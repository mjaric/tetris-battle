import Config

config :tetris, TetrisWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: TetrisWeb.ErrorJSON], layout: false],
  pubsub_server: Tetris.PubSub,
  server: true

config :tetris, Platform.Repo,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

config :tetris, ecto_repos: [Platform.Repo]

config :tetris, :generators, migration: false

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :ueberauth, Ueberauth,
  base_path: "/auth",
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]},
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify email"]}
  ]

config :tetris, :client_url, "http://localhost:4000"

config :tetris, Platform.Streaming,
  nats_url: "nats://localhost:4222",
  stream_name: "GAME_EVENTS",
  stream_subjects: ["game.>"]

# Nx: use EXLA backend for JIT-compiled tensor operations.
# NOTE: startup on first request is slow due the fact it needs to compile
# on start, so give dummy input on init so it warms up.
config :nx, :default_backend, EXLA.Backend

import_config "#{config_env()}.exs"
