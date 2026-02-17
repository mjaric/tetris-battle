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
      {:tidewave, "~> 0.5", only: :dev},
      {:phoenix, "~> 1.8.3"},
      {:jason, "~> 1.4.4"},
      {:plug_cowboy, "~> 2.8.0"},
      {:corsica, "~> 2.1.3"},
      {:telemetry, "~> 1.3.0"},
      {:phoenix_pubsub, "~> 2.2.0"},
      {:phoenix_template, "~> 1.0.4"},
      {:plug_crypto, "~> 2.1.1"},
      {:cowboy_telemetry, "~> 0.4.0"},
      {:telemetry_poller, "~> 1.3.0"},
      {:telemetry_metrics, "~> 1.1.0"},
      {:websock_adapter, "~> 0.5.9"},
      {:mime, "~> 2.0.7"},
      {:castore, "~> 1.0.17"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
