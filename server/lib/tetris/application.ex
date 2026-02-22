defmodule Tetris.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TetrisWeb.Telemetry,
      {Phoenix.PubSub, name: Tetris.PubSub},
      Platform.Repo,
      {Registry, keys: :unique, name: TetrisGame.RoomRegistry},
      TetrisGame.RoomSupervisor,
      TetrisGame.BotSupervisor,
      TetrisGame.Lobby,
      Platform.Streaming.NatsConnection,
      Platform.Streaming.StreamSetup,
      Platform.Streaming.MatchProjector,
      Platform.Streaming.KeyMomentDetector,
      TetrisWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Tetris.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TetrisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
