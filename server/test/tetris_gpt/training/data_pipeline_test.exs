defmodule TetrisGpt.Training.DataPipelineTest do
  use ExUnit.Case, async: true

  alias TetrisGpt.Training.DataPipeline

  defp make_timestep(n) do
    %{
      timestep: n,
      board: List.duplicate(List.duplicate(nil, 10), 20),
      current_piece: Enum.random([:I, :O, :T, :S, :Z, :J, :L]),
      next_piece: Enum.random([:I, :O, :T, :S, :Z, :J, :L]),
      battle_context: %{
        pending_garbage_count: 0,
        own_max_height: n,
        opponent_max_height: 5,
        combo_count: 0,
        lines: n * 2,
        score_diff: 0,
        opponent_count: 3,
        alive: true
      },
      placement: %{rotation: rem(n, 4), column: rem(n, 10)}
    }
  end

  describe "replay_to_sequences/2" do
    test "generates sliding windows from player timelines" do
      timeline = Enum.map(0..9, &make_timestep/1)
      replay = %{players: %{0 => timeline}}

      sequences =
        DataPipeline.replay_to_sequences(replay, seq_len: 4)

      # 10 timesteps, seq_len=4 -> 7 windows (10 - 4 + 1)
      assert length(sequences) == 7
    end

    test "each sequence has correct structured tensor shapes" do
      timeline = Enum.map(0..7, &make_timestep/1)
      replay = %{players: %{0 => timeline}}

      sequences =
        DataPipeline.replay_to_sequences(replay, seq_len: 4)

      [{input_map, target, mask} | _] = sequences

      assert Nx.shape(input_map["board"]) == {4, 200}
      assert Nx.shape(input_map["current_piece"]) == {4}
      assert Nx.shape(input_map["next_piece"]) == {4}
      assert Nx.shape(input_map["battle_context"]) == {4, 8}
      assert Nx.shape(input_map["placement"]) == {4}
      assert Nx.shape(target) == {4}
      assert Nx.shape(mask) == {4}
    end

    test "filters out short timelines" do
      short = Enum.map(0..2, &make_timestep/1)
      replay = %{players: %{0 => short}}

      sequences =
        DataPipeline.replay_to_sequences(replay,
          seq_len: 4,
          min_length: 4
        )

      assert sequences == []
    end
  end

  describe "batch_sequences/2" do
    test "groups sequences into batched structured tensors" do
      timeline = Enum.map(0..19, &make_timestep/1)
      replay = %{players: %{0 => timeline}}

      sequences =
        DataPipeline.replay_to_sequences(replay, seq_len: 4)

      batches =
        DataPipeline.batch_sequences(sequences, batch_size: 4)

      assert batches != []

      [{input_batch, target_batch, mask_batch} | _] = batches
      assert Nx.shape(input_batch["board"]) == {4, 4, 200}
      assert Nx.shape(input_batch["current_piece"]) == {4, 4}
      assert Nx.shape(input_batch["next_piece"]) == {4, 4}
      assert Nx.shape(input_batch["battle_context"]) == {4, 4, 8}
      assert Nx.shape(input_batch["placement"]) == {4, 4}
      assert Nx.shape(target_batch) == {4, 4}
      assert Nx.shape(mask_batch) == {4, 4}
    end
  end
end
