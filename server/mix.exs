defmodule Tetris.MixProject do
  use Mix.Project

  def project do
    [
      app: :tetris,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :crypto],
      mod: {Tetris.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, git: "https://github.com/phoenixframework/phoenix.git", tag: "v1.7.20", override: true},
      {:jason, git: "https://github.com/michalmuskala/jason.git", tag: "v1.4.4", override: true},
      {:plug_cowboy, git: "https://github.com/elixir-plug/plug_cowboy.git", tag: "v2.7.3", override: true},
      {:corsica, git: "https://github.com/whatyouhide/corsica.git", tag: "v2.1.3", override: true},
      {:telemetry, git: "https://github.com/beam-telemetry/telemetry.git", tag: "v1.3.0", override: true},
      {:phoenix_pubsub, git: "https://github.com/phoenixframework/phoenix_pubsub.git", tag: "v2.1.3", override: true},
      {:phoenix_template, git: "https://github.com/phoenixframework/phoenix_template.git", tag: "v1.0.4", override: true},
      {:plug, git: "https://github.com/elixir-plug/plug.git", tag: "v1.16.1", override: true},
      {:plug_crypto, git: "https://github.com/elixir-plug/plug_crypto.git", tag: "v2.1.0", override: true},
      {:cowboy, git: "https://github.com/ninenines/cowboy.git", tag: "2.12.0", override: true},
      {:cowlib, git: "https://github.com/ninenines/cowlib.git", tag: "2.13.0", override: true},
      {:ranch, git: "https://github.com/ninenines/ranch.git", tag: "1.8.1", override: true},
      {:cowboy_telemetry, git: "https://github.com/beam-telemetry/cowboy_telemetry.git", tag: "v0.4.0", override: true},
      {:telemetry_poller, git: "https://github.com/beam-telemetry/telemetry_poller.git", tag: "v1.1.0", override: true},
      {:telemetry_metrics, git: "https://github.com/beam-telemetry/telemetry_metrics.git", tag: "v1.1.0", override: true},
      {:websock_adapter, git: "https://github.com/phoenixframework/websock_adapter.git", tag: "0.5.8", override: true},
      {:websock, git: "https://github.com/phoenixframework/websock.git", tag: "0.5.3", override: true},
      {:mime, git: "https://github.com/elixir-plug/mime.git", tag: "v2.0.6", override: true},
      {:castore, git: "https://github.com/elixir-mint/castore.git", tag: "v1.0.17", override: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
