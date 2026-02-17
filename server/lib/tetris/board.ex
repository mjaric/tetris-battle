defmodule Tetris.Board do
  @moduledoc """
  Core board operations for a Tetris game.

  The board is a 20x10 grid represented as a list of lists.
  Each cell is either nil (empty) or a color string (occupied).
  """

  @width 10
  @height 20

  @doc """
  Returns the board width (10).
  """
  @spec width() :: pos_integer()
  def width, do: @width

  @doc """
  Returns the board height (20).
  """
  @spec height() :: pos_integer()
  def height, do: @height

  @doc """
  Creates a new empty 20x10 board filled with nil.
  """
  @spec new() :: [[nil]]
  def new do
    for _row <- 1..@height do
      List.duplicate(nil, @width)
    end
  end

  @doc """
  Checks if a piece shape fits at the given position on the board.

  A cell is valid if:
  - x is in bounds (0..9)
  - y < 20 (y can be negative for spawn above the board)
  - the board cell is nil (empty)

  Only cells where the shape has a 1 are checked.
  """
  @spec valid_position?([[integer()]], [[integer()]], {integer(), integer()}) :: boolean()
  def valid_position?(board, shape, {px, py}) do
    shape
    |> Enum.with_index()
    |> Enum.all?(fn {row, sy} ->
      row
      |> Enum.with_index()
      |> Enum.all?(fn {cell, sx} ->
        cell_valid?(board, cell, px + sx, py + sy)
      end)
    end)
  end

  # x must be in bounds; y must be below ceiling.
  # If y is negative (above board), it's valid (spawn area).
  defp cell_valid?(_board, 0, _bx, _by), do: true

  defp cell_valid?(board, _cell, bx, by) do
    bx >= 0 and bx < @width and by < @height and (by < 0 or cell_empty?(board, bx, by))
  end

  @doc """
  Places a piece shape on the board with the given color string.

  Only cells where the shape has a 1 are set. Cells above the board
  (negative y) are ignored.
  """
  @spec place_piece([[nil | String.t()]], [[integer()]], String.t(), {integer(), integer()}) ::
          [[nil | String.t()]]
  def place_piece(board, shape, color, {px, py}) do
    shape
    |> Enum.with_index()
    |> Enum.reduce(board, fn {row, sy}, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, sx}, acc2 ->
        set_board_cell(acc2, cell, px + sx, py + sy, color)
      end)
    end)
  end

  defp set_board_cell(board, 0, _bx, _by, _color), do: board

  defp set_board_cell(board, _cell, bx, by, color) do
    if by >= 0 and by < @height and bx >= 0 and bx < @width do
      List.update_at(board, by, &List.replace_at(&1, bx, color))
    else
      board
    end
  end

  @doc """
  Removes full rows (no nil cells) and adds empty rows at the top.

  Returns `{new_board, lines_cleared_count}`.
  """
  @spec clear_lines([[nil | String.t()]]) :: {[[nil | String.t()]], non_neg_integer()}
  def clear_lines(board) do
    remaining = Enum.reject(board, fn row -> Enum.all?(row, &(&1 != nil)) end)
    lines_cleared = @height - length(remaining)

    if lines_cleared == 0 do
      {board, 0}
    else
      empty_rows = for _i <- 1..lines_cleared, do: List.duplicate(nil, @width)
      {empty_rows ++ remaining, lines_cleared}
    end
  end

  @doc """
  Adds garbage rows at the bottom, pushing existing rows up.

  Returns `{new_board, overflow}` where overflow is true if any non-nil
  cell was pushed off the top.
  """
  @spec add_garbage([[nil | String.t()]], [[nil | String.t()]]) ::
          {[[nil | String.t()]], boolean()}
  def add_garbage(board, garbage_rows) do
    num_garbage = length(garbage_rows)

    # Rows that would be pushed off the top
    pushed_off = Enum.take(board, num_garbage)

    overflow =
      Enum.any?(pushed_off, fn row ->
        Enum.any?(row, &(&1 != nil))
      end)

    # Remove top rows and append garbage at bottom
    new_board = Enum.drop(board, num_garbage) ++ garbage_rows

    {new_board, overflow}
  end

  @doc """
  Finds the lowest valid y position for the piece shape (ghost/hard-drop).

  Returns `{px, lowest_y}`.
  """
  @spec ghost_position([[nil | String.t()]], [[integer()]], {integer(), integer()}) ::
          {integer(), integer()}
  def ghost_position(board, shape, {px, py}) do
    lowest_y = drop_down(board, shape, px, py)
    {px, lowest_y}
  end

  @doc """
  Generates a garbage row: a full row of "#808080" with one random nil gap.
  """
  @spec generate_garbage_row() :: [nil | String.t()]
  def generate_garbage_row do
    gap_index = :rand.uniform(@width) - 1

    for i <- 0..(@width - 1) do
      if i == gap_index, do: nil, else: "#808080"
    end
  end

  # -- Private helpers --

  defp cell_empty?(board, x, y) do
    board
    |> Enum.at(y)
    |> Enum.at(x)
    |> is_nil()
  end

  defp drop_down(board, shape, px, py) do
    if valid_position?(board, shape, {px, py + 1}) do
      drop_down(board, shape, px, py + 1)
    else
      py
    end
  end
end
