defmodule TetrisGpt.Model.TokenizerTest do
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
    end
  end
end
