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
  watchers: []

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {System, :get_env, ["GOOGLE_CLIENT_ID"]},
  client_secret: {System, :get_env, ["GOOGLE_CLIENT_SECRET"]}

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: {System, :get_env, ["GITHUB_CLIENT_ID"]},
  client_secret: {System, :get_env, ["GITHUB_CLIENT_SECRET"]}

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: {System, :get_env, ["DISCORD_CLIENT_ID"]},
  client_secret: {System, :get_env, ["DISCORD_CLIENT_SECRET"]}
