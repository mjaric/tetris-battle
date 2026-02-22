defmodule Platform.Streaming.EventPublisher do
  @moduledoc """
  Publishes game events to NATS JetStream.

  When streaming is disabled (test env), all calls are no-ops.
  """

  def publish(room_id, event) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] != false do
      subject = "game.#{room_id}.events"
      payload = Jason.encode!(event)

      case Gnat.pub(Platform.Streaming.NatsConnection, subject, payload) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  def publish_batch(room_id, events) when is_list(events) do
    Enum.each(events, &publish(room_id, &1))
  end
end
