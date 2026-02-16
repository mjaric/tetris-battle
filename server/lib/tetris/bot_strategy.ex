defmodule Tetris.BotStrategy do
  @moduledoc """
  Heuristic placement engine for bot players.

  Takes a board, current piece, and difficulty level, evaluates
  all possible placements, and returns the best action sequence.
  """

  alias Tetris.Board
  alias Tetris.BoardAnalysis
  alias Tetris.Piece

  @type difficulty :: :easy | :medium | :hard

  @weights %{
    easy: %{height: 0.30, holes: 0.50, bumpiness: 0.20, lines: 0.50},
    medium: %{height: 0.51, holes: 0.36, bumpiness: 0.18, lines: 0.76},
    hard: %{height: 0.51, holes: 0.36, bumpiness: 0.18, lines: 0.76}
  }

  @noise %{easy: 0.20, medium: 0.05, hard: 0.0}

  @doc """
  Finds the best placement for the current piece.

  Returns `{target_rotation, target_x, actions}` where actions
  is a list of input strings ending with "hard_drop".

  For Hard difficulty, uses 2-piece lookahead (current + next).
  """
  @spec best_placement(
          [[nil | String.t()]],
          Piece.t(),
          {integer(), integer()},
          Piece.t() | nil,
          difficulty()
        ) :: {non_neg_integer(), integer(), [String.t()]}
  def best_placement(board, piece, {spawn_x, _spawn_y}, next_piece, diff) do
    placements = enumerate_placements(board, piece)

    scored =
      if diff == :hard and next_piece != nil do
        score_with_lookahead(placements, next_piece, diff)
      else
        Enum.map(placements, fn pl ->
          score = score_placement(pl.metrics, @weights[diff])
          {score, pl}
        end)
      end

    chosen = pick_placement(scored, diff)

    actions =
      plan_actions(
        piece.rotation,
        spawn_x,
        chosen.rotation_count,
        chosen.target_x
      )

    {chosen.rotation_count, chosen.target_x, actions}
  end

  @doc """
  Scores a placement using weighted heuristics.

  Higher score = better placement.
  """
  @spec score_placement(map(), map()) :: float()
  def score_placement(metrics, weights) do
    -weights.height * metrics.aggregate_height -
      weights.holes * metrics.holes -
      weights.bumpiness * metrics.bumpiness +
      weights.lines * metrics.complete_lines
  end

  @doc """
  Converts a target placement into a sequence of input actions.

  Produces rotate actions, then horizontal moves, then "hard_drop".
  """
  @spec plan_actions(
          non_neg_integer(),
          integer(),
          non_neg_integer(),
          integer()
        ) :: [String.t()]
  def plan_actions(current_rotation, spawn_x, target_rotation, target_x) do
    rotations = rem(target_rotation - current_rotation + 4, 4)
    rotate_actions = List.duplicate("rotate", rotations)

    dx = target_x - spawn_x

    move_actions =
      cond do
        dx > 0 -> List.duplicate("move_right", dx)
        dx < 0 -> List.duplicate("move_left", abs(dx))
        true -> []
      end

    rotate_actions ++ move_actions ++ ["hard_drop"]
  end

  @doc """
  Enumerates all valid placements for a piece on the board.

  For each rotation (0-3) and valid x position, simulates
  hard-drop placement and evaluates the resulting board.
  """
  @spec enumerate_placements([[nil | String.t()]], Piece.t()) :: [map()]
  def enumerate_placements(board, piece) do
    0..3
    |> Enum.flat_map(fn rot_count ->
      rotated = apply_rotations(piece, rot_count)
      piece_width = shape_width(rotated.shape)
      max_x = Board.width() - piece_width

      0..max_x
      |> Enum.filter(fn x ->
        Board.valid_position?(board, rotated.shape, {x, 0})
      end)
      |> Enum.map(fn x ->
        {_gx, gy} = Board.ghost_position(board, rotated.shape, {x, 0})
        placed = Board.place_piece(board, rotated.shape, rotated.color, {x, gy})
        {cleared_board, lines} = Board.clear_lines(placed)
        metrics = BoardAnalysis.evaluate(cleared_board)
        metrics = Map.put(metrics, :complete_lines, lines)

        %{
          rotation_count: rot_count,
          target_x: x,
          resulting_board: cleared_board,
          metrics: metrics
        }
      end)
    end)
  end

  defp score_with_lookahead(placements, next_piece, diff) do
    Enum.map(placements, fn pl ->
      next_placements = enumerate_placements(pl.resulting_board, next_piece)

      best_next_score =
        if next_placements == [] do
          -1_000_000.0
        else
          next_placements
          |> Enum.map(fn np ->
            score_placement(np.metrics, @weights[diff])
          end)
          |> Enum.max()
        end

      current_score = score_placement(pl.metrics, @weights[diff])
      {current_score + best_next_score, pl}
    end)
  end

  defp pick_placement(scored, diff) do
    noise_pct = @noise[diff]
    sorted = Enum.sort_by(scored, fn {score, _} -> score end, :desc)

    if noise_pct > 0.0 and :rand.uniform() < noise_pct do
      top_half_count = max(1, div(length(sorted), 2))
      candidates = Enum.take(sorted, top_half_count)
      {_, chosen} = Enum.random(candidates)
      chosen
    else
      {_, chosen} = hd(sorted)
      chosen
    end
  end

  defp apply_rotations(piece, 0), do: piece

  defp apply_rotations(piece, n) when n > 0 do
    apply_rotations(Piece.rotate(piece), n - 1)
  end

  defp shape_width(shape) do
    shape
    |> Enum.map(fn row ->
      row
      |> Enum.with_index()
      |> Enum.filter(fn {cell, _} -> cell == 1 end)
      |> Enum.map(fn {_, idx} -> idx end)
    end)
    |> List.flatten()
    |> then(fn
      [] -> 0
      indices -> Enum.max(indices) - Enum.min(indices) + 1
    end)
  end
end
