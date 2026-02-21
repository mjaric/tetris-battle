import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing."

  config :tetris, Platform.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      """

  host = System.get_env("PHX_HOST") || raise "environment variable PHX_HOST is missing."

  config :tetris, TetrisWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: secret_key_base,
    url: [host: host, port: 443, scheme: "https"]

  cors_origins =
    case System.get_env("CORS_ORIGINS") do
      nil -> ["http://localhost:3000"]
      raw -> String.split(raw, ",", trim: true)
    end

  config :tetris, cors_origins: cors_origins

  client_url =
    System.get_env("CLIENT_URL") ||
      raise "environment variable CLIENT_URL is missing."

  config :tetris, :client_url, client_url

end

# OAuth provider credentials (all environments).
# In dev, set these env vars or leave unset (guest login still works).
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_CLIENT_SECRET")
