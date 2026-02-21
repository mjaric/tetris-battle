defmodule TetrisWeb.LobbyChannelTest do
  use TetrisWeb.ChannelCase

  alias Platform.Accounts
  alias Platform.Auth.Token

  setup do
    :sys.replace_state(TetrisGame.Lobby, fn _state ->
      %TetrisGame.Lobby{rooms: %{}}
    end)

    {:ok, user} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "lobby_#{System.unique_integer([:positive])}",
        display_name: "Tester"
      })

    token = Token.sign(user.id)
    {:ok, socket} = connect(TetrisWeb.UserSocket, %{"token" => token})

    {:ok, _, socket} =
      subscribe_and_join(socket, TetrisWeb.LobbyChannel, "lobby:main")

    %{socket: socket, user: user}
  end

  test "join returns player_id", %{socket: socket, user: user} do
    assert socket.assigns.player_id == user.id
  end

  test "list_rooms returns rooms list", %{socket: socket} do
    ref = push(socket, "list_rooms", %{})
    assert_reply(ref, :ok, %{rooms: rooms})
    assert is_list(rooms)
  end

  test "create_room creates a room and broadcasts", %{socket: socket} do
    ref =
      push(socket, "create_room", %{
        "name" => "My Room",
        "max_players" => 4
      })

    assert_reply(ref, :ok, %{room_id: room_id})
    assert is_binary(room_id)

    assert_broadcast("room_created", %{
      room_id: ^room_id,
      name: "My Room"
    })
  end

  test "list_rooms returns created rooms", %{socket: socket} do
    ref =
      push(socket, "create_room", %{
        "name" => "Listed Room",
        "max_players" => 2
      })

    assert_reply(ref, :ok, %{room_id: _room_id})

    ref = push(socket, "list_rooms", %{})
    assert_reply(ref, :ok, %{rooms: rooms})
    assert rooms != []
  end
end
