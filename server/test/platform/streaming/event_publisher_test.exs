defmodule Platform.Streaming.EventPublisherTest do
  use ExUnit.Case, async: true

  alias Platform.Streaming.EventPublisher

  test "publish returns :ok when NATS is disabled" do
    assert :ok =
             EventPublisher.publish("room_123", %{
               tick: 1,
               type: "piece_lock",
               player_id: "p1",
               data: %{}
             })
  end

  test "publish_batch returns :ok when NATS is disabled" do
    events = [
      %{tick: 1, type: "line_clear", player_id: "p1", data: %{count: 2}},
      %{
        tick: 1,
        type: "garbage_sent",
        player_id: "p1",
        data: %{target: "p2", count: 1}
      }
    ]

    assert :ok = EventPublisher.publish_batch("room_123", events)
  end
end
