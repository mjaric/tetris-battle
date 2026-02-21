import Config

config :tetris, Platform.Repo,
  username: "postgres",
  password: "password",
  hostname: "localhost",
  database: "tetris_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :tetris, TetrisWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_to_accept_it_as_valid",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, []},
    github: {Ueberauth.Strategy.Github, []},
    discord: {Ueberauth.Strategy.Discord, []}
  ]
