defmodule Tetris.BotStrategy do
  @moduledoc """
  Heuristic placement engine for bot players.

  Takes a board, current piece, and difficulty level, evaluates
  all possible placements, and returns the best action sequence.
  """

  alias Tetris.Board
  alias Tetris.BoardAnalysis
  alias Tetris.Piece

  @type difficulty :: :easy | :medium | :hard | :battle

  @board_height 20

  @battle_weight_keys [
    :height, :holes, :bumpiness, :lines, :max_height, :wells,
    :garbage_incoming, :garbage_send, :tetris_bonus,
    :opponent_danger, :survival, :line_efficiency
  ]

  @default_weights %{
    easy: %{
      height: 0.30, holes: 0.50, bumpiness: 0.20,
      lines: 0.50, max_height: 0.0, wells: 0.0
    },
    medium: %{
      height: 0.51, holes: 0.36, bumpiness: 0.18,
      lines: 0.76, max_height: 0.0, wells: 0.0
    },
    hard: %{
      height: 0.51, holes: 0.36, bumpiness: 0.18,
      lines: 0.76, max_height: 0.0, wells: 0.0
    }
  }

  @noise %{easy: 0.20, medium: 0.05, hard: 0.0, battle: 0.0}

  @doc """
  Returns heuristic weights for the given difficulty.

  For `:hard`, loads evolved weights from `priv/bot_weights.json`
  if the file exists. Easy/Medium use hardcoded defaults.
  """
  @spec weights_for(difficulty()) :: map()
  def weights_for(:hard) do
    case load_evolved_weights() do
      {:ok, weights} -> weights
      :error -> @default_weights[:hard]
    end
  end

  def weights_for(:battle) do
    case load_battle_weights() do
      {:ok, weights} -> weights
      :error -> default_battle_weights()
    end
  end

  def weights_for(diff), do: @default_weights[diff]

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
          score = score_placement(pl.metrics, weights_for(diff))
          {score, pl}
        end)
      end

    chosen = pick_placement(scored, diff)

    actions =
      plan_actions(
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
      weights.lines * metrics.complete_lines -
      Map.get(weights, :max_height, 0.0) * Map.get(metrics, :max_height, 0) -
      Map.get(weights, :wells, 0.0) * Map.get(metrics, :well_sum, 0)
  end

  @doc """
  Scores a placement for battle mode with multiplayer context.

  Extends `score_placement/2` with garbage awareness, attack
  incentives, survival pressure, and line-clear efficiency.
  """
  @spec score_battle_placement(map(), map(), map()) :: float()
  def score_battle_placement(metrics, weights, battle_ctx) do
    base = score_placement(metrics, weights)

    own_height_ratio =
      battle_ctx.own_max_height / @board_height

    avg_opp_height_ratio =
      case battle_ctx.opponent_max_heights do
        [] -> 0.0
        heights ->
          Enum.sum(heights) / (length(heights) * @board_height)
      end

    lines = metrics.complete_lines
    sends_garbage = if lines >= 2, do: 1.0, else: 0.0
    is_tetris = if lines == 4, do: 1.0, else: 0.0

    garbage_in = weights.garbage_incoming * battle_ctx.pending_garbage_count * own_height_ratio
    garbage_out = weights.garbage_send * lines * sends_garbage
    tetris = weights.tetris_bonus * is_tetris
    opp_danger = weights.opponent_danger * avg_opp_height_ratio
    surv = weights.survival * own_height_ratio * own_height_ratio
    line_eff = weights.line_efficiency * lines * lines

    base - garbage_in + garbage_out + tetris + opp_danger - surv + line_eff
  end

  @doc """
  Converts a target placement into a sequence of input actions.

  `rotations_needed` is the number of additional clockwise rotations
  (as returned by `enumerate_placements`), not an absolute rotation index.

  Produces rotate actions, then horizontal moves, then "hard_drop".
  """
  @spec plan_actions(integer(), non_neg_integer(), integer()) ::
          [String.t()]
  def plan_actions(spawn_x, rotations_needed, target_x) do
    rotate_actions = List.duplicate("rotate", rotations_needed)

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
            score_placement(np.metrics, weights_for(diff))
          end)
          |> Enum.max()
        end

      current_score = score_placement(pl.metrics, weights_for(diff))
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

  defp default_battle_weights do
    %{
      height: 0.15, holes: 0.15, bumpiness: 0.08,
      lines: 0.10, max_height: 0.05, wells: 0.05,
      garbage_incoming: 0.10, garbage_send: 0.08,
      tetris_bonus: 0.08, opponent_danger: 0.06,
      survival: 0.06, line_efficiency: 0.04
    }
  end

  defp load_battle_weights do
    path =
      :code.priv_dir(:tetris)
      |> to_string()
      |> Path.join("battle_weights.json")

    with {:ok, contents} <- File.read(path),
         {:ok, data} <- Jason.decode(contents),
         %{"weights" => w} <- data do
      {:ok,
       Map.new(@battle_weight_keys, fn key ->
         {key, w[Atom.to_string(key)] || 0.0}
       end)}
    else
      _ -> :error
    end
  end

  defp load_evolved_weights do
    path =
      :code.priv_dir(:tetris)
      |> to_string()
      |> Path.join("bot_weights.json")

    with {:ok, contents} <- File.read(path),
         {:ok, data} <- Jason.decode(contents),
         %{"weights" => w} <- data do
      {:ok,
       %{
         height: w["height"] || 0.0,
         holes: w["holes"] || 0.0,
         bumpiness: w["bumpiness"] || 0.0,
         lines: w["lines"] || 0.0,
         max_height: w["max_height"] || 0.0,
         wells: w["wells"] || 0.0
       }}
    else
      _ -> :error
    end
  end
end
