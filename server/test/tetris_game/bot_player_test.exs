defmodule TetrisGame.BotPlayerTest do
  use ExUnit.Case

  alias TetrisGame.GameRoom

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
end
