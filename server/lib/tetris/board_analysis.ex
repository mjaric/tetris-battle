defmodule Tetris.BoardAnalysis do
  @moduledoc """
  Pure Elixir board evaluation for bot decision-making.

  Computes heuristic metrics from a Tetris board (list of lists):
  aggregate height, holes, bumpiness, complete lines, max height,
  and well sum.
  """

  @width 10
  @height 20

  @doc """
  Evaluates a board and returns all metrics.

  Computes column heights in a single top-to-bottom pass,
  then derives all other metrics from those heights.
  """
  @spec evaluate([[nil | String.t()]]) :: %{
          aggregate_height: non_neg_integer(),
          holes: non_neg_integer(),
          bumpiness: non_neg_integer(),
          complete_lines: non_neg_integer(),
          max_height: non_neg_integer(),
          well_sum: non_neg_integer()
        }
  def evaluate(board) do
    {heights, holes, complete_lines} = scan_board(board)

    %{
      aggregate_height: sum(heights, 0, 0),
      holes: holes,
      bumpiness: bumpiness(heights),
      complete_lines: complete_lines,
      max_height: max_val(heights, 0, 0),
      well_sum: well_sum(heights)
    }
  end

  # Single top-to-bottom pass. Returns {heights_tuple, holes, lines}.
  # heights is a 10-element tuple of column heights.
  # holes counts empty cells below the topmost filled cell per column.
  # complete_lines counts fully filled rows.
  defp scan_board(board) do
    # Track per-column: {top_found?, height}
    # We compute holes in the same pass.
    init_cols = :erlang.make_tuple(@width, {false, 0})

    {cols, holes, lines} =
      board
      |> Enum.with_index()
      |> Enum.reduce({init_cols, 0, 0}, fn {row, row_idx}, {cols, h, ln} ->
        row_tuple = List.to_tuple(row)
        full_row? = row_full?(row_tuple, 0)
        new_ln = if full_row?, do: ln + 1, else: ln

        {new_cols, new_h} =
          scan_row(row_tuple, cols, h, row_idx, 0)

        {new_cols, new_h, new_ln}
      end)

    heights =
      :erlang.list_to_tuple(
        for i <- 0..(@width - 1) do
          {_, height} = :erlang.element(i + 1, cols)
          height
        end
      )

    {heights, holes, lines}
  end

  defp scan_row(_row, cols, holes, _row_idx, col) when col >= @width do
    {cols, holes}
  end

  defp scan_row(row, cols, holes, row_idx, col) do
    cell = :erlang.element(col + 1, row)
    {found, height} = :erlang.element(col + 1, cols)

    {new_col_state, new_holes} =
      if cell != nil do
        new_height = if found, do: height, else: @height - row_idx
        {{true, new_height}, holes}
      else
        if found do
          {{true, height}, holes + 1}
        else
          {{false, 0}, holes}
        end
      end

    new_cols = :erlang.setelement(col + 1, cols, new_col_state)
    scan_row(row, new_cols, new_holes, row_idx, col + 1)
  end

  defp row_full?(_row, col) when col >= @width, do: true

  defp row_full?(row, col) do
    if :erlang.element(col + 1, row) == nil do
      false
    else
      row_full?(row, col + 1)
    end
  end

  defp bumpiness(heights) do
    bumpiness(heights, 0, 0)
  end

  defp bumpiness(_heights, col, acc) when col >= @width - 1, do: acc

  defp bumpiness(heights, col, acc) do
    a = :erlang.element(col + 1, heights)
    b = :erlang.element(col + 2, heights)
    bumpiness(heights, col + 1, acc + abs(a - b))
  end

  defp well_sum(heights) do
    well_sum(heights, 0, 0)
  end

  defp well_sum(_heights, col, acc) when col >= @width, do: acc

  defp well_sum(heights, col, acc) do
    h = :erlang.element(col + 1, heights)

    left =
      if col == 0, do: @height, else: :erlang.element(col, heights)

    right =
      if col == @width - 1,
        do: @height,
        else: :erlang.element(col + 2, heights)

    depth = max(min(left, right) - h, 0)
    well_sum(heights, col + 1, acc + depth)
  end

  defp sum(_tuple, col, acc) when col >= @width, do: acc

  defp sum(tuple, col, acc) do
    sum(tuple, col + 1, acc + :erlang.element(col + 1, tuple))
  end

  defp max_val(_tuple, col, acc) when col >= @width, do: acc

  defp max_val(tuple, col, acc) do
    v = :erlang.element(col + 1, tuple)
    max_val(tuple, col + 1, if(v > acc, do: v, else: acc))
  end
end
