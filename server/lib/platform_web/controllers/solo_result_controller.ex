defmodule PlatformWeb.SoloResultController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Platform.Accounts
  alias Platform.Auth.Token
  alias Platform.History

  def create(conn, params) do
    with {:ok, token} <- extract_token(conn),
         {:ok, user_id} <- Token.verify(token),
         %{} = _user <- Accounts.get_user(user_id) do
      attrs = %{
        mode: "solo",
        player_count: 1,
        players: [
          %{
            user_id: user_id,
            score: params["score"],
            lines_cleared: params["lines_cleared"],
            pieces_placed: params["pieces_placed"],
            duration_ms: params["duration_ms"],
            placement: 1
          }
        ]
      }

      case History.record_match(attrs) do
        {:ok, match} ->
          conn |> put_status(201) |> json(%{match_id: match.id})

        {:error, _reason} ->
          conn |> put_status(422) |> json(%{error: "invalid data"})
      end
    else
      nil -> conn |> put_status(401) |> json(%{error: "user not found"})
      _ -> conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end
end
