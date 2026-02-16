defmodule Tetris.BoardAnalysisTest do
  use ExUnit.Case, async: true

  alias Tetris.Board
  alias Tetris.BoardAnalysis

  describe "board_to_tensor/1" do
    test "converts empty board to all-zeros tensor" do
      board = Board.new()
      tensor = BoardAnalysis.board_to_tensor(board)

      assert Nx.shape(tensor) == {20, 10}
      assert Nx.type(tensor) == {:u, 8}
      assert Nx.to_number(Nx.sum(tensor)) == 0
    end

    test "converts filled cells to 1s" do
      board = Board.new()

      board =
        List.update_at(board, 19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)

      tensor = BoardAnalysis.board_to_tensor(board)
      assert Nx.to_number(Nx.sum(tensor)) == 10
    end
  end

  describe "column_heights/1" do
    test "empty board has all zero heights" do
      tensor = BoardAnalysis.board_to_tensor(Board.new())
      heights = BoardAnalysis.column_heights(tensor)
      assert Nx.to_flat_list(heights) == List.duplicate(0, 10)
    end

    test "single filled bottom row gives height 1 for all columns" do
      board = Board.new()

      board =
        List.update_at(board, 19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)

      tensor = BoardAnalysis.board_to_tensor(board)
      heights = BoardAnalysis.column_heights(tensor)
      assert Nx.to_flat_list(heights) == List.duplicate(1, 10)
    end

    test "stacked cells give correct heights" do
      board = Board.new()

      board =
        board
        |> List.update_at(19, fn row -> List.replace_at(row, 0, "#ff0000") end)
        |> List.update_at(18, fn row -> List.replace_at(row, 0, "#ff0000") end)
        |> List.update_at(17, fn row -> List.replace_at(row, 0, "#ff0000") end)

      tensor = BoardAnalysis.board_to_tensor(board)
      heights = BoardAnalysis.column_heights(tensor)
      flat = Nx.to_flat_list(heights)
      assert hd(flat) == 3
      assert Enum.sum(tl(flat)) == 0
    end
  end

  describe "hole_count/1" do
    test "no holes on empty board" do
      tensor = BoardAnalysis.board_to_tensor(Board.new())
      assert Nx.to_number(BoardAnalysis.hole_count(tensor)) == 0
    end

    test "detects hole below filled cell" do
      board = Board.new()

      board =
        board
        |> List.update_at(18, fn row -> List.replace_at(row, 0, "#ff0000") end)

      tensor = BoardAnalysis.board_to_tensor(board)
      assert Nx.to_number(BoardAnalysis.hole_count(tensor)) == 1
    end

    test "multiple holes in one column" do
      board = Board.new()

      board =
        board
        |> List.update_at(16, fn row -> List.replace_at(row, 0, "#ff0000") end)

      tensor = BoardAnalysis.board_to_tensor(board)
      assert Nx.to_number(BoardAnalysis.hole_count(tensor)) == 3
    end
  end

  describe "bumpiness/1" do
    test "flat surface has zero bumpiness" do
      board = Board.new()

      board =
        List.update_at(board, 19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)

      tensor = BoardAnalysis.board_to_tensor(board)
      heights = BoardAnalysis.column_heights(tensor)
      assert Nx.to_number(BoardAnalysis.bumpiness(heights)) == 0
    end

    test "staircase has expected bumpiness" do
      board = Board.new()

      # Build heights: [1, 2, 3, 0, 0, ...]
      board =
        board
        |> List.update_at(19, fn row -> List.replace_at(row, 0, "#ff0000") end)
        |> List.update_at(19, fn row -> List.replace_at(row, 1, "#ff0000") end)
        |> List.update_at(18, fn row -> List.replace_at(row, 1, "#ff0000") end)
        |> List.update_at(19, fn row -> List.replace_at(row, 2, "#ff0000") end)
        |> List.update_at(18, fn row -> List.replace_at(row, 2, "#ff0000") end)
        |> List.update_at(17, fn row -> List.replace_at(row, 2, "#ff0000") end)

      tensor = BoardAnalysis.board_to_tensor(board)
      heights = BoardAnalysis.column_heights(tensor)
      bump = Nx.to_number(BoardAnalysis.bumpiness(heights))
      # heights: [1, 2, 3, 0, 0, ...] -> |1-2| + |2-3| + |3-0| = 1 + 1 + 3 = 5
      assert bump == 5
    end
  end

  describe "complete_lines/1" do
    test "no complete lines on empty board" do
      tensor = BoardAnalysis.board_to_tensor(Board.new())
      assert Nx.to_number(BoardAnalysis.complete_lines(tensor)) == 0
    end

    test "detects a fully filled row" do
      board = Board.new()

      board =
        List.update_at(board, 19, fn _row ->
          List.duplicate("#ff0000", 10)
        end)

      tensor = BoardAnalysis.board_to_tensor(board)
      assert Nx.to_number(BoardAnalysis.complete_lines(tensor)) == 1
    end
  end

  describe "evaluate/1" do
    test "empty board returns all zeros" do
      result = BoardAnalysis.evaluate(Board.new())

      assert result == %{
               aggregate_height: 0,
               holes: 0,
               bumpiness: 0,
               complete_lines: 0
             }
    end

    test "returns consistent metrics for a known board" do
      board = Board.new()

      board =
        board
        |> List.update_at(19, fn _row -> List.duplicate("#ff0000", 10) end)
        |> List.update_at(18, fn row -> List.replace_at(row, 0, "#ff0000") end)

      result = BoardAnalysis.evaluate(board)

      assert result.aggregate_height > 0
      assert result.complete_lines == 1
      assert result.holes == 0
    end
  end
end
