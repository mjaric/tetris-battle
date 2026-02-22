defmodule Platform.Streaming.StreamSetup do
  @moduledoc """
  Creates the GAME_EVENTS JetStream stream on startup.

  Returns `:ignore` when streaming is disabled.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] == false do
      :ignore
    else
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl true
  def init(_opts), do: {:ok, %{}, {:continue, :setup_streams}}

  @impl true
  def handle_continue(:setup_streams, state) do
    config = Application.get_env(:tetris, Platform.Streaming)
    stream_name = config[:stream_name] || "GAME_EVENTS"
    subjects = config[:stream_subjects] || ["game.>"]

    stream = %Gnat.Jetstream.API.Stream{
      name: stream_name,
      subjects: subjects,
      retention: :limits,
      max_age: 90 * 24 * 60 * 60 * 1_000_000_000,
      storage: :file
    }

    case Gnat.Jetstream.API.Stream.create(Platform.Streaming.NatsConnection, stream) do
      {:ok, _info} ->
        Logger.info("JetStream stream '#{stream_name}' created/verified")

      {:error, reason} ->
        Logger.warning("JetStream stream setup: #{inspect(reason)}")
    end

    {:noreply, state}
  end
end
