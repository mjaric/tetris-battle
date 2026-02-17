defmodule Tetris.BoardAnalysisTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.BoardAnalysis

  describe "evaluate/1" do
    test "empty board returns all zeros" do
      result = BoardAnalysis.evaluate(Board.new())

      assert result == %{
               aggregate_height: 0,
               holes: 0,
               bumpiness: 0,
               complete_lines: 0,
               max_height: 0,
               well_sum: 0
             }
    end

    test "single filled bottom row" do
      board =
        Board.new()
        |> List.update_at(19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.aggregate_height == 10
      assert result.max_height == 1
      assert result.holes == 0
      assert result.bumpiness == 0
      assert result.complete_lines == 1
      assert result.well_sum == 0
    end

    test "stacked cells give correct heights" do
      board =
        Board.new()
        |> List.update_at(19, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)
        |> List.update_at(18, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)
        |> List.update_at(17, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.aggregate_height == 3
      assert result.max_height == 3
    end

    test "detects hole below filled cell" do
      board =
        Board.new()
        |> List.update_at(18, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.holes == 1
      assert result.aggregate_height == 2
      assert result.max_height == 2
    end

    test "multiple holes in one column" do
      board =
        Board.new()
        |> List.update_at(16, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.holes == 3
      assert result.max_height == 4
    end

    test "flat surface has zero bumpiness" do
      board =
        Board.new()
        |> List.update_at(19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.bumpiness == 0
    end

    test "staircase has expected bumpiness" do
      board =
        Board.new()
        |> List.update_at(19, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)
        |> List.update_at(19, fn row ->
          List.replace_at(row, 1, "#ff0000")
        end)
        |> List.update_at(18, fn row ->
          List.replace_at(row, 1, "#ff0000")
        end)
        |> List.update_at(19, fn row ->
          List.replace_at(row, 2, "#ff0000")
        end)
        |> List.update_at(18, fn row ->
          List.replace_at(row, 2, "#ff0000")
        end)
        |> List.update_at(17, fn row ->
          List.replace_at(row, 2, "#ff0000")
        end)

      result = BoardAnalysis.evaluate(board)

      # heights: [1, 2, 3, 0, 0, ...] -> |1-2|+|2-3|+|3-0| = 1+1+3 = 5
      assert result.bumpiness == 5
    end

    test "well detection at edges and interior" do
      # Column 0 has height 0, columns 1-9 have height 1
      # Column 0 is a well of depth 1 (left wall=20, right=1, min=1, 1-0=1)
      board =
        Board.new()
        |> List.update_at(19, fn row ->
          row
          |> List.replace_at(1, "#ff0000")
          |> List.replace_at(2, "#ff0000")
          |> List.replace_at(3, "#ff0000")
          |> List.replace_at(4, "#ff0000")
          |> List.replace_at(5, "#ff0000")
          |> List.replace_at(6, "#ff0000")
          |> List.replace_at(7, "#ff0000")
          |> List.replace_at(8, "#ff0000")
          |> List.replace_at(9, "#ff0000")
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.well_sum == 1
    end

    test "returns consistent metrics for a known board" do
      board =
        Board.new()
        |> List.update_at(19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)
        |> List.update_at(18, fn row ->
          List.replace_at(row, 0, "#ff0000")
        end)

      result = BoardAnalysis.evaluate(board)

      assert result.aggregate_height > 0
      assert result.complete_lines == 1
      assert result.holes == 0
    end
  end
end
