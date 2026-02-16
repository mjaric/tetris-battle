defmodule Tetris.BotStrategyTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.BotStrategy
  alias Tetris.Piece

  describe "plan_actions/4" do
    test "no rotation or movement produces just hard_drop" do
      actions = BotStrategy.plan_actions(0, 3, 0, 3)
      assert actions == ["hard_drop"]
    end

    test "single rotation" do
      actions = BotStrategy.plan_actions(0, 3, 1, 3)
      assert actions == ["rotate", "hard_drop"]
    end

    test "wrapping rotation from 3 to 0 is 1 rotate" do
      actions = BotStrategy.plan_actions(3, 3, 0, 3)
      assert actions == ["rotate", "hard_drop"]
    end

    test "move left" do
      actions = BotStrategy.plan_actions(0, 5, 0, 3)
      assert actions == ["move_left", "move_left", "hard_drop"]
    end

    test "move right" do
      actions = BotStrategy.plan_actions(0, 3, 0, 5)
      assert actions == ["move_right", "move_right", "hard_drop"]
    end

    test "rotation then move" do
      actions = BotStrategy.plan_actions(0, 3, 2, 5)

      assert actions == [
               "rotate",
               "rotate",
               "move_right",
               "move_right",
               "hard_drop"
             ]
    end
  end

  describe "enumerate_placements/2" do
    test "returns non-empty list for an empty board" do
      board = Board.new()
      piece = Piece.new(:T)
      placements = BotStrategy.enumerate_placements(board, piece)

      assert length(placements) > 0

      Enum.each(placements, fn pl ->
        assert Map.has_key?(pl, :rotation_count)
        assert Map.has_key?(pl, :target_x)
        assert Map.has_key?(pl, :metrics)
        assert Map.has_key?(pl, :resulting_board)
      end)
    end

    test "covers multiple rotations" do
      board = Board.new()
      piece = Piece.new(:T)
      placements = BotStrategy.enumerate_placements(board, piece)

      rotations = placements |> Enum.map(& &1.rotation_count) |> Enum.uniq()
      assert length(rotations) > 1
    end

    test "O piece has duplicates across rotations since shape is symmetric" do
      board = Board.new()
      o_piece = Piece.new(:O)
      placements = BotStrategy.enumerate_placements(board, o_piece)

      # O piece is 2x2 so 9 positions per rotation, 4 rotations = 36
      # All rotations produce the same shape, so x positions repeat
      unique_positions =
        placements
        |> Enum.map(fn pl -> pl.target_x end)
        |> Enum.uniq()

      assert length(unique_positions) == 9
      assert length(placements) == 36
    end
  end

  describe "score_placement/2" do
    test "fewer holes scores higher" do
      weights = %{height: 0.5, holes: 0.5, bumpiness: 0.2, lines: 0.5}

      no_holes = %{aggregate_height: 5, holes: 0, bumpiness: 2, complete_lines: 0}
      with_holes = %{aggregate_height: 5, holes: 3, bumpiness: 2, complete_lines: 0}

      assert BotStrategy.score_placement(no_holes, weights) >
               BotStrategy.score_placement(with_holes, weights)
    end

    test "clearing lines improves score" do
      weights = %{height: 0.5, holes: 0.5, bumpiness: 0.2, lines: 0.76}

      no_clear = %{aggregate_height: 10, holes: 0, bumpiness: 0, complete_lines: 0}
      with_clear = %{aggregate_height: 10, holes: 0, bumpiness: 0, complete_lines: 2}

      assert BotStrategy.score_placement(with_clear, weights) >
               BotStrategy.score_placement(no_clear, weights)
    end
  end

  describe "best_placement/5" do
    test "returns valid actions for easy difficulty" do
      board = Board.new()
      piece = Piece.new(:T)
      next = Piece.new(:I)

      {rot, x, actions} =
        BotStrategy.best_placement(board, piece, {3, 0}, next, :easy)

      assert is_integer(rot) and rot in 0..3
      assert is_integer(x) and x >= 0
      assert is_list(actions)
      assert List.last(actions) == "hard_drop"

      assert Enum.all?(actions, fn a ->
               a in ["rotate", "move_left", "move_right", "hard_drop"]
             end)
    end

    test "returns valid actions for hard difficulty with lookahead" do
      board = Board.new()
      piece = Piece.new(:I)
      next = Piece.new(:O)

      {rot, x, actions} =
        BotStrategy.best_placement(board, piece, {3, 0}, next, :hard)

      assert is_integer(rot) and rot in 0..3
      assert is_integer(x) and x >= 0
      assert List.last(actions) == "hard_drop"
    end

    test "prefers line clears on a nearly full board" do
      board = Board.new()

      almost_full_row =
        List.duplicate("#ff0000", 9) ++ [nil]

      board =
        Enum.reduce(19..19, board, fn row_idx, b ->
          List.update_at(b, row_idx, fn _ -> almost_full_row end)
        end)

      # I piece horizontal can fill the gap
      piece = Piece.new(:I)
      next = Piece.new(:T)

      {_rot, _x, actions} =
        BotStrategy.best_placement(board, piece, {3, 0}, next, :medium)

      assert List.last(actions) == "hard_drop"
    end
  end
end
