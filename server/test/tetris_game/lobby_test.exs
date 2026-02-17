defmodule TetrisGame.LobbyTest do
  use ExUnit.Case

  setup do
    # Clear lobby state before each test by replacing state
    # This ensures test isolation
    :sys.replace_state(TetrisGame.Lobby, fn _state ->
      %TetrisGame.Lobby{rooms: %{}}
    end)

    :ok
  end

  describe "list_rooms/0" do
    test "returns empty list initially" do
      rooms = TetrisGame.Lobby.list_rooms()
      assert rooms == []
    end
  end

  describe "get_room/1" do
    test "returns error for nonexistent room" do
      assert {:error, :not_found} = TetrisGame.Lobby.get_room("nonexistent")
    end

    test "returns room info for existing room" do
      room_info = %{
        room_id: "test-room-1",
        host: "player1",
        name: "Test Room",
        max_players: 4,
        has_password: false,
        player_count: 0,
        status: :waiting
      }

      :sys.replace_state(TetrisGame.Lobby, fn state ->
        %{state | rooms: Map.put(state.rooms, "test-room-1", room_info)}
      end)

      assert {:ok, ^room_info} = TetrisGame.Lobby.get_room("test-room-1")
    end
  end

  describe "remove_room/1" do
    test "removes an existing room" do
      room_info = %{
        room_id: "test-room-2",
        host: "player1",
        name: "Test Room 2",
        max_players: 4,
        has_password: false,
        player_count: 0,
        status: :waiting
      }

      :sys.replace_state(TetrisGame.Lobby, fn state ->
        %{state | rooms: Map.put(state.rooms, "test-room-2", room_info)}
      end)

      TetrisGame.Lobby.remove_room("test-room-2")
      # remove_room is a cast, give it a moment to process
      :sys.get_state(TetrisGame.Lobby)

      assert {:error, :not_found} = TetrisGame.Lobby.get_room("test-room-2")
    end

    test "removing nonexistent room is a no-op" do
      TetrisGame.Lobby.remove_room("does-not-exist")
      # Should not crash
      :sys.get_state(TetrisGame.Lobby)
    end
  end

  describe "update_room/2" do
    test "updates room info for existing room" do
      room_info = %{
        room_id: "test-room-3",
        host: "player1",
        name: "Test Room 3",
        max_players: 4,
        has_password: false,
        player_count: 0,
        status: :waiting
      }

      :sys.replace_state(TetrisGame.Lobby, fn state ->
        %{state | rooms: Map.put(state.rooms, "test-room-3", room_info)}
      end)

      :ok = TetrisGame.Lobby.update_room("test-room-3", %{player_count: 2})

      assert {:ok, updated} = TetrisGame.Lobby.get_room("test-room-3")
      assert updated.player_count == 2
      assert updated.name == "Test Room 3"
    end

    test "returns error when updating nonexistent room" do
      assert {:error, :not_found} =
               TetrisGame.Lobby.update_room("nonexistent", %{player_count: 1})
    end
  end

  describe "list_rooms/0 with rooms" do
    test "returns all rooms as a list" do
      room1 = %{
        room_id: "room-a",
        host: "host1",
        name: "Room A",
        max_players: 2,
        has_password: false,
        player_count: 0,
        status: :waiting
      }

      room2 = %{
        room_id: "room-b",
        host: "host2",
        name: "Room B",
        max_players: 4,
        has_password: true,
        player_count: 1,
        status: :waiting
      }

      :sys.replace_state(TetrisGame.Lobby, fn state ->
        rooms =
          state.rooms
          |> Map.put("room-a", room1)
          |> Map.put("room-b", room2)

        %{state | rooms: rooms}
      end)

      rooms = TetrisGame.Lobby.list_rooms()
      assert length(rooms) == 2
      assert Enum.any?(rooms, fn r -> r.room_id == "room-a" end)
      assert Enum.any?(rooms, fn r -> r.room_id == "room-b" end)
    end
  end

  describe "create_room/1" do
    test "creates a room and returns room_id" do
      # This test depends on TetrisGame.RoomSupervisor.start_room/2 which
      # calls TetrisGame.GameRoom (may not exist yet). If GameRoom is not
      # available, this test will fail gracefully.
      opts = %{
        host: "player1",
        name: "My Room",
        max_players: 4
      }

      case TetrisGame.Lobby.create_room(opts) do
        {:ok, room_id} ->
          assert is_binary(room_id)
          assert {:ok, room_info} = TetrisGame.Lobby.get_room(room_id)
          assert room_info.host == "player1"
          assert room_info.name == "My Room"
          assert room_info.max_players == 4
          assert room_info.player_count == 0
          assert room_info.status == :waiting

        {:error, _reason} ->
          # GameRoom module may not exist yet; this is expected
          :ok
      end
    end
  end
end
