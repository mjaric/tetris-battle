defmodule Platform.Streaming.MatchProjector do
  @moduledoc """
  Consumes game_end events from NATS JetStream and projects match
  results to Postgres via the History context.

  Idempotent via room_id + started_at unique constraint.
  Returns `:ignore` when streaming is disabled (test env).
  """

  use GenServer
  require Logger

  alias Gnat.Jetstream.API.Consumer

  @stream_name "GAME_EVENTS"
  @consumer_name "match_projector"
  @deliver_subject "_deliver.match_projector"

  def start_link(opts \\ []) do
    config = Application.get_env(:tetris, Platform.Streaming)

    if config[:enabled] == false do
      :ignore
    else
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @doc """
  Projects a decoded game_end event to Postgres. Idempotent via room_id + started_at.
  Public for unit testing.
  """
  def project_game_end(%{"type" => "game_end", "data" => data}) do
    room_id = data["room_id"]
    started_at_str = data["started_at"]

    with {:ok, started_at, _} <- DateTime.from_iso8601(started_at_str || ""),
         false <- Platform.History.match_exists?(room_id, started_at) do
      ended_at =
        case DateTime.from_iso8601(data["ended_at"] || "") do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      attrs = %{
        mode: data["mode"],
        room_id: room_id,
        player_count: data["player_count"],
        started_at: started_at,
        ended_at: ended_at,
        players:
          Enum.map(data["players"] || [], fn p ->
            %{
              user_id: p["user_id"],
              placement: p["placement"],
              score: p["score"],
              lines_cleared: p["lines_cleared"],
              garbage_sent: p["garbage_sent"],
              garbage_received: p["garbage_received"],
              pieces_placed: p["pieces_placed"],
              duration_ms: p["duration_ms"]
            }
          end)
      }

      case Platform.History.record_match(attrs) do
        {:ok, _match} ->
          Logger.info("[MatchProjector] recorded match for room=#{room_id}")
          :ok

        {:error, reason} ->
          Logger.error("[MatchProjector] failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      true ->
        Logger.debug("[MatchProjector] duplicate for room=#{room_id}, skipping")

        :ok

      {:error, reason} ->
        Logger.warning("[MatchProjector] bad started_at: #{inspect(reason)}")
        :ok
    end
  end

  def project_game_end(_event), do: :ok

  @impl true
  def init(_opts) do
    case setup_consumer() do
      :ok ->
        Logger.info("[MatchProjector] started")
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("[MatchProjector] setup failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:msg, %{body: body, reply_to: reply_to}}, state) do
    with {:ok, %{"type" => "game_end"} = event} <- Jason.decode(body) do
      project_game_end(event)
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
end
