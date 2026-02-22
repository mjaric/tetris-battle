defmodule PlatformWeb.MatchController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Platform.Auth.Token
  alias Platform.History

  def index(conn, params) do
    with {:ok, token} <- extract_token(conn),
         {:ok, user_id} <- Token.verify(token) do
      opts = [
        limit: min(to_int(params["limit"], 20), 100),
        offset: max(to_int(params["offset"], 0), 0)
      ]

      opts =
        if params["mode"],
          do: Keyword.put(opts, :mode, params["mode"]),
          else: opts

      matches = History.list_matches(user_id, opts)

      json(conn, %{
        matches: Enum.map(matches, &serialize_match/1)
      })
    else
      _ -> conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, token} <- extract_token(conn),
         {:ok, _user_id} <- Token.verify(token),
         {:ok, match} <- History.get_match(id) do
      json(conn, %{match: serialize_match(match)})
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "not found"})

      _ ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

  defp serialize_match(m) do
    %{
      id: m.id,
      mode: m.mode,
      game_type: m.game_type,
      player_count: m.player_count,
      started_at: m.started_at,
      ended_at: m.ended_at,
      inserted_at: m.inserted_at,
      players:
        Enum.map(m.match_players, fn mp ->
          %{
            id: mp.id,
            user_id: mp.user_id,
            placement: mp.placement,
            score: mp.score,
            lines_cleared: mp.lines_cleared,
            garbage_sent: mp.garbage_sent,
            garbage_received: mp.garbage_received,
            pieces_placed: mp.pieces_placed,
            duration_ms: mp.duration_ms
          }
        end)
    }
  end

  defp to_int(nil, default), do: default

  defp to_int(val, default) when is_binary(val) do
    String.to_integer(val)
  rescue
    _ -> default
  end

  defp to_int(val, _default) when is_integer(val), do: val
end
