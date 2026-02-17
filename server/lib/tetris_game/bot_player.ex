defmodule TetrisGame.BotPlayer do
  @moduledoc """
  GenServer representing a single bot player in a game room.

  Receives game state updates from the GameRoom, computes
  placements using BotStrategy, and sends input actions back.
  """

  use GenServer
  require Logger

  alias Tetris.BotStrategy
  alias TetrisGame.GameRoom

  @timing %{
    easy: %{think_min: 800, think_max: 1200, action_interval: 200},
    medium: %{think_min: 300, think_max: 500, action_interval: 100},
    hard: %{think_min: 50, think_max: 100, action_interval: 50}
  }

  defstruct [
    :bot_id,
    :nickname,
    :room_id,
    :room_ref,
    :difficulty,
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
    nickname = Keyword.fetch!(opts, :nickname)
    room_id = Keyword.fetch!(opts, :room_id)
    difficulty = Keyword.fetch!(opts, :difficulty)
    room_pid = Keyword.fetch!(opts, :room_pid)

    room_ref = Process.monitor(room_pid)

    state = %__MODULE__{
      bot_id: bot_id,
      nickname: nickname,
      room_id: room_id,
      room_ref: room_ref,
      difficulty: difficulty,
      phase: :waiting,
      action_queue: [],
      last_piece_id: nil
    }

    Logger.debug(
      "[Bot] #{nickname} (#{difficulty}) initialized in room #{room_id}"
    )

    {:ok, state}
  end

  @impl true
  def handle_info(:game_started, state) do
    Logger.debug("[Bot] #{state.nickname} game started")
    {:noreply, %{state | phase: :thinking}}
  end

  def handle_info({:game_state, payload}, state) do
    handle_game_state(payload, state)
  end

  def handle_info(:think, state) do
    do_think(state)
  end

  def handle_info(:execute_action, state) do
    do_execute_action(state)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{room_ref: ref} = state) do
    Logger.debug("[Bot] #{state.nickname} room went down, exiting")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp handle_game_state(payload, state) do
    player_data = get_in(payload, [:players, state.bot_id])

    cond do
      player_data == nil ->
        {:noreply, state}

      not player_data.alive ->
        Logger.debug("[Bot] #{state.nickname} eliminated, exiting")
        {:stop, :normal, state}

      payload.status == :finished ->
        Logger.debug("[Bot] #{state.nickname} game finished, exiting")
        {:stop, :normal, state}

      state.phase == :waiting ->
        {:noreply, state}

      true ->
        piece_id = piece_identifier(player_data)
        handle_piece_change(piece_id, player_data, payload, state)
    end
  end

  defp handle_piece_change(piece_id, _player_data, _payload, %{last_piece_id: last} = state)
       when piece_id == last and state.phase == :executing do
    {:noreply, state}
  end

  defp handle_piece_change(piece_id, _player_data, _payload, %{last_piece_id: last} = state)
       when piece_id == last and state.phase == :thinking do
    {:noreply, state}
  end

  defp handle_piece_change(piece_id, _player_data, _payload, state) do
    timing = @timing[state.difficulty]
    delay = Enum.random(timing.think_min..timing.think_max)
    Process.send_after(self(), :think, delay)

    {:noreply, %{state | phase: :thinking, last_piece_id: piece_id, action_queue: []}}
  end

  defp do_think(state) do
    room = GameRoom.via(state.room_id)

    try do
      room_state = GameRoom.get_state(room)
      player = room_state.players[state.bot_id]

      if player == nil or not player.alive do
        {:stop, :normal, state}
      else
        {_rot, _x, actions} =
          BotStrategy.best_placement(
            player.board,
            player.current_piece,
            player.position,
            player.next_piece,
            state.difficulty
          )

        maybe_set_target(room, room_state, state)

        timing = @timing[state.difficulty]
        Process.send_after(self(), :execute_action, timing.action_interval)

        {:noreply, %{state | phase: :executing, action_queue: actions}}
      end
    catch
      :exit, _ ->
        {:stop, :normal, state}
    end
  end

  defp do_execute_action(%{action_queue: []} = state) do
    {:noreply, %{state | phase: :thinking}}
  end

  defp do_execute_action(%{action_queue: [action | rest]} = state) do
    room = GameRoom.via(state.room_id)

    try do
      GameRoom.input(room, state.bot_id, action)
    catch
      :exit, _ -> :ok
    end

    if rest != [] do
      timing = @timing[state.difficulty]
      Process.send_after(self(), :execute_action, timing.action_interval)
    end

    {:noreply, %{state | action_queue: rest}}
  end

  defp maybe_set_target(room, room_state, state) do
    alive_opponents =
      room_state.players
      |> Enum.filter(fn {id, p} -> id != state.bot_id and p.alive end)
      |> Enum.map(fn {id, p} -> {id, p} end)

    if alive_opponents != [] do
      target =
        case state.difficulty do
          :hard ->
            {id, _} = Enum.max_by(alive_opponents, fn {_, p} -> p.score end)
            id

          _ ->
            {id, _} = Enum.random(alive_opponents)
            id
        end

      try do
        GameRoom.set_target(room, state.bot_id, target)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp piece_identifier(player_data) do
    case player_data do
      %{current_piece: %{type: type}, pieces_placed: pp} ->
        {type, pp}

      _ ->
        nil
    end
  end
end
