defmodule TetrisGame.BotPlayerTest do
  use ExUnit.Case

  alias TetrisGame.GameRoom
  alias TetrisGame.BotPlayer
  alias Tetris.Board

  setup do
    room_id = "bot_exec_#{:rand.uniform(100_000)}"

    {:ok, pid} =
      GameRoom.start_link(
        room_id: room_id,
        host: "host_1",
        name: "Bot Exec Test",
        max_players: 4
      )

    :ok = GameRoom.join(pid, "host_1", "Host")

    %{pid: pid, room_id: room_id}
  end

  describe "bot execution" do
    test "bot places pieces at varied positions", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :hard)
      :ok = GameRoom.start_game(pid, "host_1")

      # Let the bot run for enough ticks to place several pieces
      Process.sleep(3000)

      state = GameRoom.get_state(pid)
      bot = state.players[bot_id]

      assert bot.alive,
        "bot should still be alive after 3 seconds"

      assert bot.pieces_placed > 3,
        "bot should have placed multiple pieces, got #{bot.pieces_placed}"

      # The bot board should have blocks in varied columns,
      # not just stacked in the center
      occupied_columns =
        bot.board
        |> Enum.flat_map(fn row ->
          row
          |> Enum.with_index()
          |> Enum.filter(fn {cell, _} -> cell != nil end)
          |> Enum.map(fn {_, col} -> col end)
        end)
        |> Enum.uniq()

      assert length(occupied_columns) >= 3,
        "bot should place pieces in at least 3 different columns, " <>
          "got #{inspect(occupied_columns)}"
    end

    test "bot clears lines during gameplay", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :hard)
      :ok = GameRoom.start_game(pid, "host_1")

      # Let the bot play long enough to clear some lines
      Process.sleep(8000)

      state = GameRoom.get_state(pid)
      bot = state.players[bot_id]

      if bot.alive do
        assert bot.lines > 0,
          "hard bot should clear at least 1 line in 8 seconds, " <>
            "got #{bot.lines} lines, #{bot.pieces_placed} pieces placed"
      end
    end
  end

  describe "build_battle_context/3" do
    test "extracts correct values from player state" do
      bot_board = Board.new()

      bot_player = %{
        board: bot_board,
        alive: true,
        score: 100,
        pending_garbage: [
          List.duplicate("#808080", 10),
          List.duplicate("#808080", 10)
        ]
      }

      # Create a board with some height - fill bottom 8 rows
      opp1_board =
        Enum.reduce(12..19, Board.new(), fn row_idx, b ->
          List.update_at(b, row_idx, fn _ ->
            List.duplicate("#ff0000", 10)
          end)
        end)

      opp2_board =
        Enum.reduce(5..19, Board.new(), fn row_idx, b ->
          List.update_at(b, row_idx, fn _ ->
            List.duplicate("#00ff00", 10)
          end)
        end)

      opponent1 = %{board: opp1_board, alive: true, score: 200}
      opponent2 = %{board: opp2_board, alive: true, score: 50}
      dead_opp = %{board: Board.new(), alive: false, score: 10}

      players = %{
        "bot1" => bot_player,
        "p1" => opponent1,
        "p2" => opponent2,
        "p3" => dead_opp
      }

      ctx = BotPlayer.build_battle_context("bot1", bot_player, players)

      assert ctx.pending_garbage_count == 2
      assert ctx.own_max_height == 0
      assert ctx.opponent_count == 2
      assert length(ctx.opponent_max_heights) == 2
      assert 8 in ctx.opponent_max_heights
      assert 15 in ctx.opponent_max_heights
      assert ctx.leading_opponent_score == 200
    end

    test "handles no alive opponents" do
      bot_player = %{
        board: Board.new(),
        alive: true,
        score: 100,
        pending_garbage: []
      }

      dead = %{board: Board.new(), alive: false, score: 50}

      players = %{
        "bot1" => bot_player,
        "p1" => dead
      }

      ctx = BotPlayer.build_battle_context("bot1", bot_player, players)

      assert ctx.opponent_count == 0
      assert ctx.opponent_max_heights == []
      assert ctx.leading_opponent_score == 0
    end

    test "handles integer pending_garbage count" do
      bot_player = %{
        board: Board.new(),
        alive: true,
        score: 100,
        pending_garbage: 5
      }

      players = %{"bot1" => bot_player}

      ctx = BotPlayer.build_battle_context("bot1", bot_player, players)
      assert ctx.pending_garbage_count == 5
    end
  end

  describe "battle bot execution" do
    test "battle bot plays and targets opponents", %{pid: pid} do
      {:ok, bot_id} = GameRoom.add_bot(pid, :battle)
      :ok = GameRoom.start_game(pid, "host_1")

      Process.sleep(3000)

      state = GameRoom.get_state(pid)
      bot = state.players[bot_id]

      assert bot.alive,
        "battle bot should still be alive after 3 seconds"

      assert bot.pieces_placed > 3,
        "battle bot should have placed multiple pieces, " <>
          "got #{bot.pieces_placed}"
    end
  end
end
