defmodule TetrisGpt.Training.GameRecorderTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Training.GameRecorder

  describe "record_game/1" do
    test "returns replay with 4 player timelines" do
      replay = GameRecorder.record_game(difficulty: :hard)

      assert is_map(replay)
      assert map_size(replay.players) == 4
    end

    test "each player timeline contains timestep maps" do
      replay = GameRecorder.record_game(difficulty: :hard)

      Enum.each(replay.players, fn {_id, timeline} ->
        assert is_list(timeline)
        assert timeline != []

        first = hd(timeline)
        assert Map.has_key?(first, :board)
        assert Map.has_key?(first, :current_piece)
        assert Map.has_key?(first, :next_piece)
        assert Map.has_key?(first, :placement)
        assert Map.has_key?(first, :battle_context)
        assert first.placement.rotation in 0..3
        assert first.placement.column in 0..9
      end)
    end

    test "timesteps are ordered by placement number" do
      replay = GameRecorder.record_game(difficulty: :hard)

      Enum.each(replay.players, fn {_id, timeline} ->
        timestep_indices = Enum.map(timeline, & &1.timestep)
        assert timestep_indices == Enum.sort(timestep_indices)
      end)
    end
  end

  describe "record_games/2" do
    test "records multiple games" do
      replays = GameRecorder.record_games(3, difficulty: :hard)
      assert length(replays) == 3
    end
  end
end
