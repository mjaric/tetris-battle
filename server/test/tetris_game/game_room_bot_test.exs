defmodule TetrisGame.GameRoomBotTest do
  use ExUnit.Case

  alias TetrisGame.GameRoom

  setup do
    room_id = "bot_test_#{:rand.uniform(100_000)}"

    {:ok, pid} =
      GameRoom.start_link(
        room_id: room_id,
        host: "host_1",
        name: "Bot Test Room",
        max_players: 4
      )

    :ok = GameRoom.join(pid, "host_1", "Host")

    %{pid: pid, room_id: room_id}
  end

  describe "add_bot/2" do
    test "adds a bot to the room", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :easy)

      state = GameRoom.get_state(pid)
      assert Map.has_key?(state.players, bot_id)
      assert MapSet.member?(state.bot_ids, bot_id)
      assert Map.has_key?(state.bot_pids, bot_id)
      assert bot_id in state.player_order
    end

    test "bot gets a nickname from the name pool", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :medium)

      state = GameRoom.get_state(pid)
      nickname = state.players[bot_id].nickname
      assert nickname in TetrisGame.BotNames.all()
    end

    test "rejects adding bot when room is full", %{pid: pid} do
      :ok = GameRoom.join(pid, "p2", "Player2")
      :ok = GameRoom.join(pid, "p3", "Player3")
      {:ok, _} = GameRoom.add_bot(pid, :easy)

      assert {:error, :room_full} = GameRoom.add_bot(pid, :easy)
    end

    test "rejects adding bot when game in progress", %{pid: pid} do
      {:ok, _} = GameRoom.add_bot(pid, :easy)
      :ok = GameRoom.start_game(pid, "host_1")

      assert {:error, :game_in_progress} = GameRoom.add_bot(pid, :medium)
    end
  end

  describe "remove_bot/2" do
    test "removes a bot from the room", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :easy)
      :ok = GameRoom.remove_bot(pid, bot_id)

      state = GameRoom.get_state(pid)
      refute Map.has_key?(state.players, bot_id)
      refute MapSet.member?(state.bot_ids, bot_id)
      refute Map.has_key?(state.bot_pids, bot_id)
      refute bot_id in state.player_order
    end

    test "rejects removing non-bot player", %{pid: pid} do
      assert {:error, :not_a_bot} = GameRoom.remove_bot(pid, "host_1")
    end

    test "rejects removing bot during game", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :hard)
      :ok = GameRoom.start_game(pid, "host_1")

      assert {:error, :game_in_progress} = GameRoom.remove_bot(pid, bot_id)
    end
  end

  describe "start_game with bots" do
    test "game starts with human + bot", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :easy)
      :ok = GameRoom.start_game(pid, "host_1")

      state = GameRoom.get_state(pid)
      assert state.status == :playing
      assert Map.has_key?(state.players, bot_id)
      assert Map.has_key?(state.players, "host_1")
    end
  end

  describe "broadcast payload" do
    test "includes is_bot flag in player data", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :easy)

      state = GameRoom.get_state(pid)
      payload = GameRoom.build_broadcast_payload(state)

      assert payload.players[bot_id].is_bot == true
      assert payload.players["host_1"].is_bot == false
    end
  end

  describe "human-empty room cleanup" do
    test "room stops when last human leaves and only bots remain", %{pid: pid} do
      ref = Process.monitor(pid)
      {:ok, _bot_id} = GameRoom.add_bot(pid, :easy)

      :ok = GameRoom.leave(pid, "host_1")

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end
end
