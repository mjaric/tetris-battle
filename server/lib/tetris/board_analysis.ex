defmodule Tetris.BoardAnalysis do
  @moduledoc """
  Nx tensor-based board evaluation for bot decision-making.

  Converts a Tetris board to a tensor and computes heuristic
  metrics: aggregate height, holes, bumpiness, and complete lines.
  """

  import Nx.Defn

  @doc """
  Converts a 20x10 board (list of lists, nil/string) to a
  `{20, 10}` u8 tensor where 0 = empty and 1 = filled.
  """
  @spec board_to_tensor([[nil | String.t()]]) :: Nx.Tensor.t()
  def board_to_tensor(board) do
    board
    |> Enum.map(fn row ->
      Enum.map(row, fn
        nil -> 0
        _color -> 1
      end)
    end)
    |> Nx.tensor(type: :u8)
  end

  @doc """
  Computes column heights as a `{10}` tensor.

  Height of a column is the number of rows from the topmost
  filled cell to the bottom.
  """
  defn column_heights(tensor) do
    rows = Nx.axis_size(tensor, 0)

    filled_mask = Nx.cumulative_max(tensor, axis: 0)
    heights = Nx.sum(filled_mask, axes: [0])

    Nx.min(heights, rows)
  end

  @doc """
  Counts holes: empty cells below at least one filled cell.
  """
  defn hole_count(tensor) do
    filled_mask = Nx.cumulative_max(tensor, axis: 0)
    holes = Nx.subtract(filled_mask, tensor)
    Nx.sum(holes)
  end

  @doc """
  Sum of absolute differences between adjacent column heights.
  """
  defn bumpiness(heights) do
    h = Nx.as_type(heights, :s32)
    left = h[0..-2//1]
    right = h[1..-1//1]
    Nx.sum(Nx.abs(Nx.subtract(left, right)))
  end

  @doc """
  Sum of all column heights.
  """
  defn aggregate_height(heights) do
    Nx.sum(heights)
  end

  @doc """
  Count of completely filled rows.
  """
  defn complete_lines(tensor) do
    cols = Nx.axis_size(tensor, 1)
    row_sums = Nx.sum(tensor, axes: [1])
    Nx.sum(Nx.equal(row_sums, cols))
  end

  @doc """
  Evaluates a board and returns all metrics in one pass.

  Returns `%{aggregate_height: n, holes: n, bumpiness: n, complete_lines: n}`.
  """
  @spec evaluate([[nil | String.t()]]) :: %{
          aggregate_height: number(),
          holes: number(),
          bumpiness: number(),
          complete_lines: number()
        }
  def evaluate(board) do
    tensor = board_to_tensor(board)
    heights = column_heights(tensor)

    %{
      aggregate_height: Nx.to_number(aggregate_height(heights)),
      holes: Nx.to_number(hole_count(tensor)),
      bumpiness: Nx.to_number(bumpiness(heights)),
      complete_lines: Nx.to_number(complete_lines(tensor))
    }
  end
end
