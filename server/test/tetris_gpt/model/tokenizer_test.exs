defmodule TetrisGpt.Model.TokenizerTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias TetrisGpt.Model.Tokenizer

  describe "encode_board/1" do
    test "converts empty board to zero tensor" do
      board = List.duplicate(List.duplicate(nil, 10), 20)
      tensor = Tokenizer.encode_board(board)

      # this is size of the board
      assert Nx.shape(tensor) == {200}
      # since it is empty, result is 0
      assert Nx.sum(tensor) |> Nx.to_number() == 0.0
    end

    test "converts filled cells to 1.0" do
      # in our board non nil item is color. We don't care, tho,
      # we just care if it is nil or something else.
      board =
        List.duplicate(List.duplicate(nil, 10), 19) ++
          [List.duplicate("#ff0000", 10)]

      tensor = Tokenizer.encode_board(board)
      # board shape is 10x20, meaning we have 200 cells
      assert Nx.shape(tensor) == {200}
      # Last 10 cells should be 1.0, since it locks from bottom to up
      bottom_row = Nx.slice(tensor, [190], [10])
      # if we summ all items from this 1D matrix, we get 10.0
      assert Nx.sum(bottom_row) |> Nx.to_number() == 10.0
      # the velue of item can only be 1.0 or 0.0
      assert Nx.to_list(bottom_row) == List.duplicate(1.0, 10)
    end
  end

  describe "piece_index/1" do
    test "maps all 7 piece types to unique indices 0-6" do
      indices =
        [:I, :O, :T, :S, :Z, :J, :L]
        |> Enum.map(&Tokenizer.piece_index/1)
        |> Enum.sort()

      assert indices == [0, 1, 2, 3, 4, 5, 6]
    end

    test "do not map other than 7 piece types to unique indices 0-6" do
      assert_raise FunctionClauseError, fn ->
        _ = Tokenizer.piece_index(:K)
      end
    end
  end

  describe "placement_index/2" do
    test "encodes rotation and column into 0-39 range" do
      assert Tokenizer.placement_index(0, 0) == 0
      assert Tokenizer.placement_index(0, 9) == 9
      assert Tokenizer.placement_index(1, 0) == 10
      assert Tokenizer.placement_index(3, 9) == 39
    end
  end

  describe "encode_battle_context/1" do
    test "returns 8-element normalized tensor" do
      ctx = %{
        pending_garbage_count: 6,
        own_max_height: 10,
        opponent_max_height: 15,
        combo_count: 3,
        lines: 50,
        score_diff: 500,
        opponent_count: 2,
        alive: true
      }

      tensor = Tokenizer.encode_battle_context(ctx)
      assert Nx.shape(tensor) == {8}
      # All values should be in roughly [-1, 1] range
      max_val = Nx.reduce_max(tensor) |> Nx.to_number()
      min_val = Nx.reduce_min(tensor) |> Nx.to_number()
      assert max_val <= 1.1
      assert min_val >= -1.1
    end
  end

  defp make_timestep(piece \\ :T, next \\ :I, rotation \\ 0, col \\ 5) do
    %{
      board: List.duplicate(List.duplicate(nil, 10), 20),
      current_piece: piece,
      next_piece: next,
      battle_context: %{
        pending_garbage_count: 0,
        own_max_height: 0,
        opponent_max_height: 0,
        combo_count: 0,
        lines: 0,
        score_diff: 0,
        opponent_count: 3,
        alive: true
      },
      placement: %{rotation: rotation, column: col}
    }
  end

  describe "encode_structured_sequence/2" do
    test "pads short sequences and returns structured tensor map" do
      result =
        Tokenizer.encode_structured_sequence(
          [make_timestep()],
          seq_len: 4
        )

      assert Nx.shape(result[:board]) == {4, 200}
      assert Nx.shape(result[:current_piece]) == {4}
      assert Nx.shape(result[:next_piece]) == {4}
      assert Nx.shape(result[:battle_context]) == {4, 8}
      assert Nx.shape(result[:placement]) == {4}
      assert Nx.shape(result[:mask]) == {4}

      # Only last position should be unmasked
      assert Nx.to_flat_list(result[:mask]) == [0.0, 0.0, 0.0, 1.0]
    end

    test "truncates long sequences to seq_len" do
      timesteps = List.duplicate(make_timestep(), 10)

      result =
        Tokenizer.encode_structured_sequence(
          timesteps,
          seq_len: 4
        )

      assert Nx.shape(result[:board]) == {4, 200}
      assert Nx.shape(result[:current_piece]) == {4}
      # All positions should be unmasked (no padding needed)
      assert Nx.to_flat_list(result[:mask]) == [1.0, 1.0, 1.0, 1.0]
    end

    test "piece and placement indices are correct" do
      result =
        Tokenizer.encode_structured_sequence(
          [make_timestep(:S, :Z, 2, 7)],
          seq_len: 1
        )

      assert Nx.to_number(result[:current_piece][0]) ==
               Tokenizer.piece_index(:S)

      assert Nx.to_number(result[:next_piece][0]) ==
               Tokenizer.piece_index(:Z)

      assert Nx.to_number(result[:placement][0]) ==
               Tokenizer.placement_index(2, 7)
    end
  end
end
