defmodule TetrisWeb.GameChannelTest do
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
        provider_id: "game_#{System.unique_integer([:positive])}",
        display_name: "Tester"
      })

    room_id = "test_room_#{:rand.uniform(100_000)}"

    {:ok, _pid} =
      TetrisGame.GameRoom.start_link(
        room_id: room_id,
        host: user.id,
        name: "Test",
        max_players: 4
      )

    token = Token.sign(user.id)
    {:ok, socket} = connect(TetrisWeb.UserSocket, %{"token" => token})

    {:ok, _, socket} =
      subscribe_and_join(
        socket,
        TetrisWeb.GameChannel,
        "game:#{room_id}"
      )

    %{socket: socket, room_id: room_id, user: user}
  end

  test "joining adds player to room", %{room_id: room_id, user: user} do
    state =
      TetrisGame.GameRoom.get_state(TetrisGame.GameRoom.via(room_id))

    assert Map.has_key?(state.players, user.id)
  end

  test "input events are forwarded", %{socket: socket} do
    push(socket, "input", %{"action" => "move_left"})
  end

  test "join returns player_id", %{socket: socket, user: user} do
    assert socket.assigns.player_id == user.id
  end

  test "joining a nonexistent room returns error" do
    {:ok, user} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "game_noroom_#{System.unique_integer([:positive])}",
        display_name: "Tester2"
      })

    token = Token.sign(user.id)
    {:ok, socket} = connect(TetrisWeb.UserSocket, %{"token" => token})

    {:error, %{reason: "room_not_found"}} =
      subscribe_and_join(
        socket,
        TetrisWeb.GameChannel,
        "game:nonexistent_room"
      )
  end

  test "idempotent join succeeds for already-joined player",
       %{room_id: room_id, user: user} do
    token = Token.sign(user.id)
    {:ok, socket} = connect(TetrisWeb.UserSocket, %{"token" => token})

    {:ok, _, _socket} =
      subscribe_and_join(
        socket,
        TetrisWeb.GameChannel,
        "game:#{room_id}"
      )

    state =
      TetrisGame.GameRoom.get_state(TetrisGame.GameRoom.via(room_id))

    assert Map.has_key?(state.players, user.id)
  end
end
