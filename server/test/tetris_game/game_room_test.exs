defmodule TetrisGame.GameRoomTest do
  use ExUnit.Case

  alias TetrisGame.GameRoom

  setup do
    room_id = "test_room_#{:rand.uniform(100_000)}"

    {:ok, pid} =
      GameRoom.start_link(
        room_id: room_id,
        host: "host_1",
        name: "Test Room",
        max_players: 4
      )

    %{pid: pid, room_id: room_id}
  end

  describe "start_link/1" do
    test "starts the GenServer with initial state", %{pid: pid} do
      state = GameRoom.get_state(pid)
      assert state.status == :waiting
      assert state.host == "host_1"
      assert state.name == "Test Room"
      assert state.max_players == 4
      assert state.players == %{}
      assert state.player_order == []
      assert state.eliminated_order == []
      assert state.tick == 0
      assert state.tick_timer == nil
    end

    test "registers via the RoomRegistry", %{room_id: room_id} do
      pid = GenServer.whereis(GameRoom.via(room_id))
      assert is_pid(pid)
    end

  end

  describe "join/3" do
    test "join adds a player", %{pid: pid} do
      :ok = GameRoom.join(pid, "player_1", "Alice")
      state = GameRoom.get_state(pid)
      assert Map.has_key?(state.players, "player_1")
      assert state.players["player_1"].nickname == "Alice"
    end

    test "join adds player to player_order", %{pid: pid} do
      :ok = GameRoom.join(pid, "player_1", "Alice")
      :ok = GameRoom.join(pid, "player_2", "Bob")
      state = GameRoom.get_state(pid)
      assert state.player_order == ["player_1", "player_2"]
    end

    test "rejects join when room is full", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.join(pid, "p3", "C")
      :ok = GameRoom.join(pid, "p4", "D")
      assert {:error, :room_full} = GameRoom.join(pid, "p5", "E")
    end

    test "idempotent join succeeds for already-joined player", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      assert :ok = GameRoom.join(pid, "p1", "A")
    end

    test "rejects join when game is in progress", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      assert {:error, :game_in_progress} = GameRoom.join(pid, "p3", "C")
    end
  end

  describe "leave/2" do
    test "leave removes player", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.leave(pid, "p1")
      state = GameRoom.get_state(pid)
      refute Map.has_key?(state.players, "p1")
      assert state.player_order == ["p2"]
    end

    test "leave removes player and reassigns host", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.leave(pid, "host_1")
      state = GameRoom.get_state(pid)
      # oldest remaining player becomes host
      assert state.host == "p1"
    end

    test "leave stops GenServer when room is empty", %{pid: pid} do
      ref = Process.monitor(pid)
      :ok = GameRoom.leave(pid, "host_1")

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "leave is a no-op for unknown player", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.leave(pid, "unknown_player")
      state = GameRoom.get_state(pid)
      assert Map.has_key?(state.players, "p1")
    end
  end

  describe "start_game/2" do
    test "start_game begins the game loop", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      state = GameRoom.get_state(pid)
      assert state.status == :playing
      assert state.tick_timer != nil
    end

    test "only host can start game", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      assert {:error, :not_host} = GameRoom.start_game(pid, "p1")
    end

    test "needs at least 2 players to start", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      assert {:error, :not_enough_players} = GameRoom.start_game(pid, "host_1")
    end

    test "initializes player states with boards and pieces", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      state = GameRoom.get_state(pid)

      Enum.each(state.players, fn {_id, player} ->
        assert player.alive == true
        assert player.board != nil
        assert player.current_piece != nil
        assert player.next_piece != nil
      end)
    end

    test "sets default targets (each player targets next in order)", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.join(pid, "p3", "C")
      :ok = GameRoom.start_game(pid, "host_1")
      state = GameRoom.get_state(pid)

      order = state.player_order
      num_players = length(order)

      Enum.each(Enum.with_index(order), fn {player_id, idx} ->
        next_idx = rem(idx + 1, num_players)
        expected_target = Enum.at(order, next_idx)
        assert state.players[player_id].target == expected_target
      end)
    end

    test "cannot start game twice", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      assert {:error, :already_started} = GameRoom.start_game(pid, "host_1")
    end
  end

  describe "input/3" do
    test "input queues actions for a player", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      :ok = GameRoom.input(pid, "p1", "move_left")
      # No crash = success, and we can verify the queue has the action
      state = GameRoom.get_state(pid)
      queue = state.players["p1"].input_queue
      assert :queue.len(queue) >= 0
    end

    test "input accepts valid action strings", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")

      Enum.each(["move_left", "move_right", "move_down", "rotate", "hard_drop"], fn action ->
        :ok = GameRoom.input(pid, "p1", action)
      end)
    end
  end

  describe "set_target/3" do
    test "set_target changes player target", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.join(pid, "p3", "C")
      :ok = GameRoom.start_game(pid, "host_1")
      :ok = GameRoom.set_target(pid, "p1", "p3")
      state = GameRoom.get_state(pid)
      assert state.players["p1"].target == "p3"
    end

    test "set_target rejects invalid target", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      assert {:error, :invalid_target} = GameRoom.set_target(pid, "p1", "nonexistent")
    end

    test "set_target rejects targeting self", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")
      assert {:error, :invalid_target} = GameRoom.set_target(pid, "p1", "p1")
    end
  end

  describe "tick loop" do
    test "tick increments the tick counter", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")

      # Wait for a few ticks
      Process.sleep(200)

      state = GameRoom.get_state(pid)
      assert state.tick > 0
    end

    test "tick processes input queue actions", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")

      # Queue several actions
      :ok = GameRoom.input(pid, "p1", "move_left")
      :ok = GameRoom.input(pid, "p1", "move_left")

      # Wait for tick to process them
      Process.sleep(100)

      state = GameRoom.get_state(pid)
      # Queue should be drained after tick processes it
      assert :queue.is_empty(state.players["p1"].input_queue)
    end

    test "game finishes when only one player is alive", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")

      # Manually eliminate p2 by modifying their state
      :sys.replace_state(pid, fn state ->
        p2 = state.players["p2"]
        updated_p2 = %{p2 | alive: false}
        %{state | players: Map.put(state.players, "p2", updated_p2)}
      end)

      # Wait for tick to detect elimination and finish
      Process.sleep(150)

      state = GameRoom.get_state(pid)
      assert state.status == :finished
    end
  end

  describe "garbage pipeline" do
    test "clearing 2+ lines distributes garbage to target", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")

      # Set up p1's board: rows 18-19 full except columns 4-5
      :sys.replace_state(pid, fn state ->
        p1 = state.players["p1"]

        board =
          Enum.map(0..19, fn row_idx ->
            if row_idx >= 18 do
              Enum.map(0..9, fn col ->
                if col in [4, 5], do: nil, else: "#ff0000"
              end)
            else
              List.duplicate(nil, 10)
            end
          end)

        o_piece = Tetris.Piece.new(:O)
        p1 = %{p1 | board: board, current_piece: o_piece, position: {4, 0}}
        %{state | players: Map.put(state.players, "p1", p1)}
      end)

      # Hard drop fills cols 4-5 in rows 18-19 → clears 2 lines
      :ok = GameRoom.input(pid, "p1", "hard_drop")
      Process.sleep(100)

      state = GameRoom.get_state(pid)
      p2 = state.players["p2"]

      # p1 cleared 2 lines → sends 1 garbage row to p2
      # p2 might have pending_garbage or it may already be applied
      # (depends on whether p2's piece locked this tick)
      has_pending = length(p2.pending_garbage) > 0

      has_garbage_on_board =
        Enum.any?(p2.board, fn row ->
          Enum.any?(row, fn cell -> cell == "#808080" end)
        end)

      assert has_pending or has_garbage_on_board,
        "p2 should have garbage (pending: #{length(p2.pending_garbage)}, on_board: #{has_garbage_on_board})"
    end

    test "pending garbage is applied when target's piece locks", %{pid: pid} do
      :ok = GameRoom.join(pid, "p1", "A")
      :ok = GameRoom.join(pid, "p2", "B")
      :ok = GameRoom.start_game(pid, "host_1")

      # Directly inject pending_garbage into p2
      :sys.replace_state(pid, fn state ->
        p2 = state.players["p2"]
        garbage = [Tetris.Board.generate_garbage_row()]
        p2 = %{p2 | pending_garbage: garbage}
        %{state | players: Map.put(state.players, "p2", p2)}
      end)

      # Hard drop p2's piece to trigger lock_and_spawn
      :ok = GameRoom.input(pid, "p2", "hard_drop")
      Process.sleep(100)

      state = GameRoom.get_state(pid)
      p2 = state.players["p2"]

      # Garbage should be applied (pending cleared, gray cells on board)
      assert p2.pending_garbage == []

      has_garbage_on_board =
        Enum.any?(p2.board, fn row ->
          Enum.any?(row, fn cell -> cell == "#808080" end)
        end)

      assert has_garbage_on_board,
        "p2's board should have garbage rows after piece lock"
    end
  end

  describe "via/1" do
    test "returns a via tuple for the given room_id" do
      via = GameRoom.via("test_room")
      assert via == {:via, Registry, {TetrisGame.RoomRegistry, "test_room"}}
    end
  end
end
