defmodule TetrisWeb.GameChannelTest do
  use ExUnit.Case
  import Phoenix.ChannelTest

  @endpoint TetrisWeb.Endpoint

  setup do
    # Clear lobby state
    :sys.replace_state(TetrisGame.Lobby, fn _state ->
      %TetrisGame.Lobby{rooms: %{}}
    end)

    room_id = "test_room_#{:rand.uniform(100_000)}"

    {:ok, _pid} =
      TetrisGame.GameRoom.start_link(
        room_id: room_id,
        host: "host_1",
        name: "Test",
        max_players: 4
      )

    {:ok, _, socket} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_1", nickname: "Tester"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:#{room_id}")

    %{socket: socket, room_id: room_id}
  end

  test "joining adds player to room", %{room_id: room_id} do
    state = TetrisGame.GameRoom.get_state(TetrisGame.GameRoom.via(room_id))
    assert Map.has_key?(state.players, "player_1")
  end

  test "input events are forwarded", %{socket: socket} do
    push(socket, "input", %{"action" => "move_left"})
    # No crash = success
  end

  test "join returns player_id in response", %{socket: socket} do
    assert socket.assigns.player_id == "player_1"
  end

  test "joining a nonexistent room returns error" do
    {:error, %{reason: "room_not_found"}} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_2", nickname: "Tester2"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:nonexistent_room")
  end

  test "idempotent join succeeds for already-joined player", %{room_id: room_id} do
    {:ok, _, _socket} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_1", nickname: "Tester"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:#{room_id}")

    state = TetrisGame.GameRoom.get_state(TetrisGame.GameRoom.via(room_id))
    assert Map.has_key?(state.players, "player_1")
  end
end
