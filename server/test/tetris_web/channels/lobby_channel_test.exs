defmodule TetrisWeb.LobbyChannelTest do
  use ExUnit.Case
  import Phoenix.ChannelTest

  @endpoint TetrisWeb.Endpoint

  setup do
    # Clear lobby state before each test
    :sys.replace_state(TetrisGame.Lobby, fn _state ->
      %TetrisGame.Lobby{rooms: %{}}
    end)

    {:ok, _, socket} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "test_player", nickname: "Tester"})
      |> subscribe_and_join(TetrisWeb.LobbyChannel, "lobby:main")

    %{socket: socket}
  end

  test "join returns player_id", %{socket: socket} do
    assert socket.assigns.player_id == "test_player"
  end

  test "list_rooms returns rooms list", %{socket: socket} do
    ref = push(socket, "list_rooms", %{})
    assert_reply(ref, :ok, %{rooms: rooms})
    assert is_list(rooms)
  end

  test "create_room creates a room and broadcasts", %{socket: socket} do
    ref = push(socket, "create_room", %{"name" => "My Room", "max_players" => 4})
    assert_reply(ref, :ok, %{room_id: room_id})
    assert is_binary(room_id)

    assert_broadcast("room_created", %{room_id: ^room_id, name: "My Room"})
  end

  test "list_rooms returns created rooms", %{socket: socket} do
    ref = push(socket, "create_room", %{"name" => "Listed Room", "max_players" => 2})
    assert_reply(ref, :ok, %{room_id: _room_id})

    ref = push(socket, "list_rooms", %{})
    assert_reply(ref, :ok, %{rooms: rooms})
    assert rooms != []
  end
end
