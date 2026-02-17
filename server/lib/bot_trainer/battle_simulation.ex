defmodule BotTrainer.BattleSimulation do
  @moduledoc """
  Headless N-player Tetris battle simulation for bot weight evaluation.

  Runs complete multiplayer games without timing or GenServer overhead.
  Each player takes turns placing pieces, garbage is distributed between
  players, and players are eliminated when their boards overflow.
  """

  alias Tetris.Board
  alias Tetris.BotStrategy
  alias Tetris.Piece

  @line_points %{1 => 100, 2 => 300, 3 => 500, 4 => 800}
  @board_height 20

  @doc """
  Simulates a full N-player battle.

  Player 0 uses `genome` weights with battle-aware scoring.
  Players 1..N use `opponent_weights` with solo scoring.

  Returns placement, lines cleared, pieces placed, and total players.
  """
  @spec simulate_battle(map(), [map()], keyword()) :: %{
          placement: pos_integer(),
          lines_cleared: non_neg_integer(),
          pieces_placed: non_neg_integer(),
          total_players: pos_integer()
        }
  def simulate_battle(genome, opponent_weights, opts \\ []) do
    lookahead = Keyword.get(opts, :lookahead, true)
    total = 1 + length(opponent_weights)

    players = init_players(genome, opponent_weights)
    battle_loop(players, [], total, lookahead)
  end

  @doc """
  Runs N battles and returns a fitness score.

  Fitness combines placement rank (70%) with lines cleared (30%).
  """
  @spec evaluate(map(), [map()], pos_integer(), keyword()) :: float()
  def evaluate(genome, opponents, num_battles, opts \\ []) do
    results =
      Enum.map(1..num_battles, fn _ ->
        simulate_battle(genome, opponents, opts)
      end)

    total_players = hd(results).total_players

    avg_placement =
      results
      |> Enum.map(& &1.placement)
      |> Enum.sum()
      |> Kernel./(num_battles)

    avg_lines =
      results
      |> Enum.map(& &1.lines_cleared)
      |> Enum.sum()
      |> Kernel./(num_battles)

    placement_score =
      if total_players <= 1 do
        1.0
      else
        (total_players - avg_placement) / (total_players - 1)
      end

    placement_score * 70.0 + avg_lines * 0.3
  end

  # -- Battle loop --

  defp battle_loop(players, elimination_order, total, lookahead) do
    alive_ids = alive_player_ids(players)

    if length(alive_ids) <= 1 do
      finish_battle(players, elimination_order, total)
    else
      {updated, new_eliminations} =
        tick(players, alive_ids, lookahead)

      updated = retarget_dead(updated)

      battle_loop(
        updated,
        elimination_order ++ new_eliminations,
        total,
        lookahead
      )
    end
  end

  # -- Tick: one round for all alive players --

  defp tick(players, alive_ids, lookahead) do
    Enum.reduce(alive_ids, {players, []}, fn id, {ps, elims} ->
      player = ps[id]

      if not player.alive do
        {ps, elims}
      else
        tick_player(ps, id, player, elims, lookahead)
      end
    end)
  end

  defp tick_player(players, id, player, elims, lookahead) do
    {player, overflow} = apply_garbage(player)

    if overflow do
      players = Map.put(players, id, %{player | alive: false})
      {players, elims ++ [id]}
    else
      place_and_advance(players, id, player, elims, lookahead)
    end
  end

  defp place_and_advance(players, id, player, elims, lookahead) do
    placements =
      BotStrategy.enumerate_placements(player.board, player.current_piece)

    if placements == [] do
      player = %{player | alive: false}
      players = Map.put(players, id, player)
      {players, elims ++ [id]}
    else
      best = pick_best(player, placements, players, lookahead)
      player = apply_placement(player, best)
      lines = best.metrics.complete_lines

      players = Map.put(players, id, player)

      players =
        if lines >= 2 do
          send_garbage(players, id, lines - 1)
        else
          players
        end

      {player, spawn_ok} = spawn_next(players[id])
      players = Map.put(players, id, player)

      if not spawn_ok do
        player = %{player | alive: false}
        players = Map.put(players, id, player)
        {players, elims ++ [id]}
      else
        player = update_target(player, players)
        players = Map.put(players, id, player)
        {players, elims}
      end
    end
  end

  # -- Placement selection --

  defp pick_best(player, placements, all_players, lookahead) do
    case player.mode do
      :battle ->
        pick_battle(player, placements, all_players, lookahead)

      :solo ->
        pick_solo(player, placements, lookahead)
    end
  end

  defp pick_battle(player, placements, all_players, true) do
    ctx = build_context(player, all_players)

    scored =
      Enum.map(placements, fn pl ->
        {BotStrategy.score_battle_placement(pl.metrics, player.weights, ctx), pl}
      end)

    top_k =
      scored
      |> Enum.sort_by(fn {s, _} -> s end, :desc)
      |> Enum.take(5)

    {_score, best} =
      Enum.max_by(top_k, fn {greedy_score, pl} ->
        greedy_score +
          best_next_battle_score(
            pl.resulting_board,
            player.next_piece,
            player.weights,
            ctx
          )
      end)

    best
  end

  defp pick_battle(player, placements, all_players, false) do
    ctx = build_context(player, all_players)

    {_score, best} =
      Enum.max_by(
        Enum.map(placements, fn pl ->
          {BotStrategy.score_battle_placement(pl.metrics, player.weights, ctx), pl}
        end),
        fn {s, _} -> s end
      )

    best
  end

  defp pick_solo(player, placements, true) do
    scored =
      Enum.map(placements, fn pl ->
        {BotStrategy.score_placement(pl.metrics, player.weights), pl}
      end)

    top_k =
      scored
      |> Enum.sort_by(fn {s, _} -> s end, :desc)
      |> Enum.take(5)

    {_score, best} =
      Enum.max_by(top_k, fn {greedy_score, pl} ->
        greedy_score +
          best_next_solo_score(
            pl.resulting_board,
            player.next_piece,
            player.weights
          )
      end)

    best
  end

  defp pick_solo(player, placements, false) do
    Enum.max_by(placements, fn pl ->
      BotStrategy.score_placement(pl.metrics, player.weights)
    end)
  end

  defp best_next_battle_score(board, next_piece, weights, ctx) do
    case BotStrategy.enumerate_placements(board, next_piece) do
      [] ->
        -1_000_000.0

      pls ->
        pls
        |> Enum.map(fn np ->
          BotStrategy.score_battle_placement(np.metrics, weights, ctx)
        end)
        |> Enum.max()
    end
  end

  defp best_next_solo_score(board, next_piece, weights) do
    case BotStrategy.enumerate_placements(board, next_piece) do
      [] ->
        -1_000_000.0

      pls ->
        pls
        |> Enum.map(fn np ->
          BotStrategy.score_placement(np.metrics, weights)
        end)
        |> Enum.max()
    end
  end

  # -- Battle context (mirrors BotPlayer.build_battle_context/3) --

  defp build_context(player, all_players) do
    alive_opponents =
      all_players
      |> Enum.filter(fn {id, p} -> id != player.id and p.alive end)
      |> Enum.map(fn {_id, p} -> p end)

    opp_heights =
      Enum.map(alive_opponents, &max_height_from_board(&1.board))

    leading_score =
      case alive_opponents do
        [] -> 0
        opps -> opps |> Enum.map(& &1.score) |> Enum.max()
      end

    %{
      pending_garbage_count: player.pending_garbage,
      own_max_height: max_height_from_board(player.board),
      opponent_max_heights: opp_heights,
      opponent_count: length(alive_opponents),
      leading_opponent_score: leading_score
    }
  end

  # -- Garbage --

  defp apply_garbage(%{pending_garbage: 0} = player) do
    {player, false}
  end

  defp apply_garbage(player) do
    rows =
      Enum.map(1..player.pending_garbage, fn _ ->
        Board.generate_garbage_row()
      end)

    {new_board, overflow} = Board.add_garbage(player.board, rows)

    player = %{player | board: new_board, pending_garbage: 0}
    {player, overflow}
  end

  defp send_garbage(players, sender_id, count) do
    sender = players[sender_id]
    target_id = sender.target

    if target_id != nil and players[target_id] != nil and players[target_id].alive do
      target = players[target_id]
      target = %{target | pending_garbage: target.pending_garbage + count}
      Map.put(players, target_id, target)
    else
      players
    end
  end

  # -- Placement application --

  defp apply_placement(player, placement) do
    rotated =
      apply_rotations(player.current_piece, placement.rotation_count)

    {_gx, gy} =
      Board.ghost_position(
        player.board,
        rotated.shape,
        {placement.target_x, 0}
      )

    placed =
      Board.place_piece(
        player.board,
        rotated.shape,
        rotated.color,
        {placement.target_x, gy}
      )

    {cleared_board, lines_cleared} = Board.clear_lines(placed)

    line_score =
      Map.get(@line_points, lines_cleared, 0) * player.level

    new_lines = player.lines + lines_cleared
    new_level = div(new_lines, 10) + 1

    %{
      player
      | board: cleared_board,
        score: player.score + line_score,
        lines: new_lines,
        level: new_level,
        pieces_placed: player.pieces_placed + 1
    }
  end

  # -- Piece spawning --

  defp spawn_next(player) do
    new_piece = player.next_piece
    spawn_x = spawn_x(new_piece)

    if Board.valid_position?(player.board, new_piece.shape, {spawn_x, 0}) do
      player = %{
        player
        | current_piece: new_piece,
          next_piece: Piece.random()
      }

      {player, true}
    else
      {player, false}
    end
  end

  # -- Targeting --

  defp update_target(player, all_players) do
    alive_opponents =
      all_players
      |> Enum.filter(fn {id, p} -> id != player.id and p.alive end)

    case alive_opponents do
      [] ->
        %{player | target: nil}

      opponents ->
        target_id =
          case player.mode do
            :battle ->
              {id, _} =
                Enum.max_by(opponents, fn {_, p} ->
                  max_height_from_board(p.board)
                end)

              id

            :solo ->
              {id, _} =
                Enum.max_by(opponents, fn {_, p} -> p.score end)

              id
          end

        %{player | target: target_id}
    end
  end

  defp retarget_dead(players) do
    Map.new(players, fn {id, player} ->
      if player.alive and
           (player.target == nil or
              not Map.get(players[player.target] || %{}, :alive, false)) do
        player = update_target(player, players)
        {id, player}
      else
        {id, player}
      end
    end)
  end

  # -- Finish --

  defp finish_battle(players, elimination_order, total) do
    alive_ids = alive_player_ids(players)

    # Build ranking: winner first, then reverse elimination order
    ranking = alive_ids ++ Enum.reverse(elimination_order)

    player_0_pos =
      Enum.find_index(ranking, fn id -> id == 0 end)

    placement = player_0_pos + 1
    player_0 = players[0]

    %{
      placement: placement,
      lines_cleared: player_0.lines,
      pieces_placed: player_0.pieces_placed,
      total_players: total
    }
  end

  # -- Player initialization --

  defp init_players(genome, opponent_weights) do
    total = 1 + length(opponent_weights)

    battle_player = new_player(0, genome, :battle)

    opponents =
      opponent_weights
      |> Enum.with_index(1)
      |> Enum.map(fn {weights, idx} ->
        {idx, new_player(idx, weights, :solo)}
      end)

    players = Map.new([{0, battle_player} | opponents])
    assign_initial_targets(players, total)
  end

  defp new_player(id, weights, mode) do
    current = Piece.random()
    next = Piece.random()

    %{
      id: id,
      mode: mode,
      weights: weights,
      board: Board.new(),
      current_piece: current,
      next_piece: next,
      score: 0,
      lines: 0,
      level: 1,
      pieces_placed: 0,
      pending_garbage: 0,
      target: nil,
      alive: true
    }
  end

  defp assign_initial_targets(players, total) do
    Map.new(players, fn {id, player} ->
      target = rem(id + 1, total)
      {id, %{player | target: target}}
    end)
  end

  # -- Helpers --

  defp alive_player_ids(players) do
    players
    |> Enum.filter(fn {_id, p} -> p.alive end)
    |> Enum.map(fn {id, _} -> id end)
    |> Enum.sort()
  end

  defp max_height_from_board(board) do
    board
    |> Enum.with_index()
    |> Enum.find_value(0, fn {row, idx} ->
      if Enum.any?(row, &(&1 != nil)), do: @board_height - idx
    end)
  end

  defp spawn_x(piece) do
    shape_width = length(Enum.at(piece.shape, 0))
    div(Board.width() - shape_width, 2)
  end

  defp apply_rotations(piece, 0), do: piece

  defp apply_rotations(piece, n) when n > 0 do
    apply_rotations(Piece.rotate(piece), n - 1)
  end
end
