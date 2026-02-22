defmodule Platform.Streaming.KeyMomentDetector do
  @moduledoc """
  Detects key moments from game events and publishes to game.{room_id}.moments.

  Currently detected: tetris, back_to_back, garbage_surge, elimination.
  Deferred (need board state): perfect_clear, near_death_survival, comeback.
  """

  use GenServer
  require Logger

  alias Gnat.Jetstream.API.Consumer

  @stream_name "GAME_EVENTS"
  @consumer_name "key_moment_detector"
  @deliver_subject "_deliver.key_moment_detector"
  @garbage_surge_threshold 3

  def start_link(opts \\ []) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] == false do
      :ignore
    else
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @doc """
  Detects key moments from a single event given game state.
  Returns `{moments, new_game_state}`. Public for unit testing.
  """
  def detect_moments(event, game_state) do
    player_id = event["player_id"]
    tick = event["tick"]

    {moments, new_state} = detect_by_type(event, game_state, player_id, tick)
    new_state = maybe_reset_garbage_streak(new_state, event["type"], player_id)

    {moments, new_state}
  end

  defp detect_by_type(event, state, player_id, tick) do
    case event["type"] do
      "line_clear" -> detect_line_clear(event, state, player_id, tick)
      "b2b_tetris" -> detect_b2b(state, player_id, tick)
      "garbage_sent" -> detect_garbage_surge(event, state, player_id, tick)
      "elimination" -> {[%{type: "elimination", player_id: player_id, tick: tick}], state}
      "game_end" -> {[], :cleanup}
      _ -> {[], state}
    end
  end

  defp maybe_reset_garbage_streak(:cleanup, _type, _pid), do: :cleanup
  defp maybe_reset_garbage_streak(state, "garbage_sent", _pid), do: state
  defp maybe_reset_garbage_streak(state, _type, nil), do: state

  defp maybe_reset_garbage_streak(state, _type, player_id) do
    put_in(state, [:garbage_streak, Access.key(player_id, 0)], 0)
  end

  def new_game_state do
    %{last_bonus_clear: %{}, garbage_streak: %{}}
  end

  # -- Detection helpers --

  defp detect_line_clear(event, state, player_id, tick) do
    count = event["count"] || get_in(event, ["data", "count"]) || 0

    if count == 4 do
      tetris = %{
        type: "tetris",
        player_id: player_id,
        tick: tick,
        lines: count
      }

      last = get_in(state, [:last_bonus_clear, player_id])

      b2b =
        if last in [:tetris, :b2b_tetris],
          do: [%{type: "back_to_back", player_id: player_id, tick: tick}],
          else: []

      new_state = put_in(state, [:last_bonus_clear, player_id], :tetris)
      {[tetris | b2b], new_state}
    else
      new_state = put_in(state, [:last_bonus_clear, player_id], nil)
      {[], new_state}
    end
  end

  defp detect_b2b(state, player_id, tick) do
    last = get_in(state, [:last_bonus_clear, player_id])

    moments =
      if last in [:tetris, :b2b_tetris],
        do: [%{type: "back_to_back", player_id: player_id, tick: tick}],
        else: []

    new_state = put_in(state, [:last_bonus_clear, player_id], :b2b_tetris)
    {moments, new_state}
  end

  defp detect_garbage_surge(event, state, player_id, tick) do
    streak =
      get_in(state, [:garbage_streak, Access.key(player_id, 0)]) + 1

    new_state = put_in(state, [:garbage_streak, player_id], streak)
    count = event["count"] || get_in(event, ["data", "count"]) || 0

    moments =
      if streak >= @garbage_surge_threshold,
        do: [
          %{
            type: "garbage_surge",
            player_id: player_id,
            tick: tick,
            streak: streak,
            count: count
          }
        ],
        else: []

    {moments, new_state}
  end

  # -- GenServer callbacks --

  @impl true
  def init(_opts) do
    case setup_consumer() do
      :ok -> {:ok, %{games: %{}}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_info(
        {:msg, %{body: body, topic: topic, reply_to: reply_to}},
        state
      ) do
    room_id = extract_room_id(topic)

    state =
      case Jason.decode(body) do
        {:ok, event} ->
          game_state = Map.get(state.games, room_id, new_game_state())
          {moments, new_game_state} = detect_moments(event, game_state)

          Enum.each(moments, fn moment ->
            payload = Jason.encode!(moment)
            Gnat.pub(Platform.Streaming.NatsConnection, "game.#{room_id}.moments", payload)
          end)

          case new_game_state do
            :cleanup ->
              %{state | games: Map.delete(state.games, room_id)}

            updated ->
              %{state | games: Map.put(state.games, room_id, updated)}
          end

        {:error, _} ->
          state
      end

    ack(reply_to)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp setup_consumer do
    conn = Platform.Streaming.NatsConnection

    consumer = %Consumer{
      stream_name: @stream_name,
      durable_name: @consumer_name,
      filter_subject: "game.*.events",
      deliver_subject: @deliver_subject,
      ack_policy: :explicit,
      deliver_policy: :new
    }

    with {:ok, _} <- Consumer.create(conn, consumer),
         {:ok, _} <- Gnat.sub(conn, self(), @deliver_subject) do
      :ok
    end
  end

  defp ack(nil), do: :ok

  defp ack(reply_to) do
    Gnat.pub(Platform.Streaming.NatsConnection, reply_to, "")
  end

  defp extract_room_id(topic) do
    case String.split(topic, ".") do
      ["game", room_id, "events"] -> room_id
      _ -> "unknown"
    end
  end
end
