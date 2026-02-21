import Config

config :tetris, Platform.Repo,
  username: "postgres",
  password: "password",
  hostname: "localhost",
  database: "tetris_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :tetris, TetrisWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_accept_it_as_valid",
  watchers: [
    npx: [
      "vite",
      "build",
      "--watch",
      "--outDir",
      "../server/priv/static",
      "--sourcemap",
      cd: Path.expand("../../client", __DIR__)
    ]
  ]

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
