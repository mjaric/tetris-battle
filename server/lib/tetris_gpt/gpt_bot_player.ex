defmodule TetrisGpt.GptBotPlayer do
  @moduledoc """
  GenServer that plays Tetris using a TetrisGpt Strategy.

  Mirrors the BotPlayer lifecycle:
    :waiting -> :thinking -> :executing -> :thinking -> ...

  Receives game state broadcasts from GameRoom, maintains
  strategy state, runs model inference to choose placements,
  and submits actions back to the room.
  """

  use GenServer
  require Logger

  alias Tetris.BotStrategy
  alias TetrisGame.GameRoom

  @action_interval 50

  defstruct [
    :bot_id,
    :nickname,
    :room_id,
    :room_ref,
    :strategy_module,
    :strategy_state,
    :phase,
    :action_queue,
    :last_piece_id
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    bot_id = Keyword.fetch!(opts, :bot_id)
    room_pid = Keyword.fetch!(opts, :room_pid)
    strategy_mod = Keyword.fetch!(opts, :strategy)
    strategy_opts = Keyword.get(opts, :strategy_opts, [])

    ref = Process.monitor(room_pid)

    state = %__MODULE__{
      bot_id: bot_id,
      nickname: Keyword.fetch!(opts, :nickname),
      room_id: Keyword.fetch!(opts, :room_id),
      room_ref: ref,
      strategy_module: strategy_mod,
      strategy_state: strategy_mod.init(strategy_opts),
      phase: :waiting,
      action_queue: [],
      last_piece_id: nil
    }

    Logger.debug("[GptBot] #{bot_id} started (#{strategy_mod.name()})")

    {:ok, state}
  end

  @impl true
  def handle_info(:game_started, state) do
    {:noreply, %{state | phase: :thinking}}
  end

  @impl true
  def handle_info({:game_state, payload}, state) do
    player = get_in(payload, [:players, state.bot_id])

    cond do
      player == nil ->
        {:noreply, state}

      not player.alive ->
        {:stop, :normal, state}

      payload.status == :finished ->
        {:stop, :normal, state}

      state.phase == :waiting ->
        {:noreply, state}

      true ->
        handle_piece_change(player, state)
    end
  end

  @impl true
  def handle_info(:think, state) do
    room = GameRoom.via(state.room_id)

    try do
      room_state = GameRoom.get_state(room)
      player = room_state.players[state.bot_id]
      do_think(state, player, room_state)
    catch
      :exit, _ -> {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info(:execute_action, state) do
    case state.action_queue do
      [] ->
        {:noreply, %{state | phase: :thinking}}

      [action | rest] ->
        room = GameRoom.via(state.room_id)

        try do
          GameRoom.input(room, state.bot_id, action)
        catch
          :exit, _ -> :ok
        end

        if rest != [] do
          Process.send_after(
            self(),
            :execute_action,
            @action_interval
          )
        end

        {:noreply, %{state | action_queue: rest}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{room_ref: ref} = state
      ) do
    Logger.debug("[GptBot] #{state.bot_id}: room down")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_piece_change(player, state) do
    piece_id = piece_identifier(player)

    cond do
      # Same piece, still working on it
      piece_id == state.last_piece_id ->
        {:noreply, state}

      # New piece arrived — think regardless of current phase
      true ->
        Process.send_after(self(), :think, 10)

        {:noreply,
         %{
           state
           | last_piece_id: piece_id,
             phase: :thinking,
             action_queue: []
         }}
    end
  end

  defp do_think(state, nil, _room_state),
    do: {:stop, :normal, state}

  defp do_think(state, player, _room_state)
       when not player.alive,
       do: {:stop, :normal, state}

  defp do_think(state, player, room_state) do
    context = build_context(player, room_state, state.bot_id)

    {placement, new_strategy_state} =
      state.strategy_module.predict(
        state.strategy_state,
        context
      )

    spawn_x = elem(player.position, 0)

    actions =
      BotStrategy.plan_actions(
        spawn_x,
        placement.rotation,
        placement.column
      )

    Process.send_after(self(), :execute_action, @action_interval)

    {:noreply,
     %{
       state
       | strategy_state: new_strategy_state,
         action_queue: actions,
         phase: :executing
     }}
  end

  defp build_context(player, room_state, bot_id) do
    opponents =
      room_state.players
      |> Enum.filter(fn {id, p} -> id != bot_id and p.alive end)

    opp_max_height =
      opponents
      |> Enum.map(fn {_id, p} -> max_height(p.board) end)
      |> Enum.max(fn -> 0 end)

    pending_count =
      case player.pending_garbage do
        count when is_integer(count) -> count
        list when is_list(list) -> length(list)
        _ -> 0
      end

    %{
      board: player.board,
      current_piece: player.current_piece.type,
      next_piece: player.next_piece.type,
      battle_context: %{
        pending_garbage_count: pending_count,
        own_max_height: max_height(player.board),
        opponent_max_height: opp_max_height,
        combo_count: Map.get(player, :combo_count, 0),
        lines: player.lines,
        score_diff: 0,
        opponent_count: length(opponents),
        alive: player.alive
      }
    }
  end

  defp max_height(board) do
    board
    |> Enum.with_index()
    |> Enum.find_value(0, fn {row, idx} ->
      if Enum.any?(row, &(&1 != nil)), do: 20 - idx
    end)
  end

  defp piece_identifier(player) do
    case player do
      %{current_piece: %{type: type}, pieces_placed: pp} ->
        {type, pp}

      _ ->
        nil
    end
  end
end
