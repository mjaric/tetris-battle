defmodule Platform.Streaming.NatsConnection do
  @moduledoc """
  Manages the NATS connection for event streaming.

  Starts a Gnat connection when streaming is enabled. Returns `:ignore`
  when streaming is disabled (e.g., in test environment).
  """

  def start_link(_opts) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] == false do
      :ignore
    else
      connection_settings = parse_url(config[:nats_url] || "nats://localhost:4222")
      Gnat.start_link(connection_settings, name: __MODULE__)
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  defp parse_url(url) do
    uri = URI.parse(url)
    %{host: uri.host || "localhost", port: uri.port || 4222}
  end
end
