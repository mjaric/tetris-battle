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

import_config "#{config_env()}.exs"
