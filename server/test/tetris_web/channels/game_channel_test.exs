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

  test "password-protected room requires auth" do
    room_id = "pw_room_#{:rand.uniform(100_000)}"

    {:ok, _pid} =
      TetrisGame.GameRoom.start_link(
        room_id: room_id,
        host: "host_2",
        name: "Secret Room",
        max_players: 4,
        password: "secret123"
      )

    {:error, %{reason: "auth_required", nonce: nonce}} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_3", nickname: "Tester3"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:#{room_id}", %{})

    assert is_binary(nonce)
  end

  test "password-protected room accepts valid hmac" do
    room_id = "pw_room_valid_#{:rand.uniform(100_000)}"
    password = "secret456"

    {:ok, _pid} =
      TetrisGame.GameRoom.start_link(
        room_id: room_id,
        host: "host_3",
        name: "Secret Room 2",
        max_players: 4,
        password: password
      )

    # Generate a valid challenge-response
    nonce = :crypto.strong_rand_bytes(32) |> Base.encode64()
    hmac = :crypto.mac(:hmac, :sha256, password, Base.decode64!(nonce)) |> Base.encode64()

    {:ok, _, _socket} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_4", nickname: "Tester4"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:#{room_id}", %{
        "nonce" => nonce,
        "hmac" => hmac
      })
  end

  test "password-protected room rejects invalid hmac" do
    room_id = "pw_room_invalid_#{:rand.uniform(100_000)}"

    {:ok, _pid} =
      TetrisGame.GameRoom.start_link(
        room_id: room_id,
        host: "host_4",
        name: "Secret Room 3",
        max_players: 4,
        password: "correct_password"
      )

    nonce = :crypto.strong_rand_bytes(32) |> Base.encode64()
    # Use wrong password for HMAC
    hmac = :crypto.mac(:hmac, :sha256, "wrong_password", Base.decode64!(nonce)) |> Base.encode64()

    {:error, %{reason: "invalid_password"}} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_5", nickname: "Tester5"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:#{room_id}", %{
        "nonce" => nonce,
        "hmac" => hmac
      })
  end
end
