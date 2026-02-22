defmodule PlatformWeb.MatchControllerTest do
  use PlatformWeb.ConnCase, async: true

  alias Platform.Accounts
  alias Platform.Auth.Token
  alias Platform.History

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "match_test",
        display_name: "Viewer"
      })

    token = Token.sign(user.id)

    History.record_match(%{
      mode: "solo",
      player_count: 1,
      players: [%{user_id: user.id, score: 3000, lines_cleared: 15}]
    })

    %{user: user, token: token}
  end

  test "lists matches for authenticated user", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/matches")

    assert %{"matches" => matches} = json_response(conn, 200)
    assert length(matches) == 1
    assert hd(matches)["mode"] == "solo"
  end

  test "filters by mode", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/matches", %{mode: "multiplayer"})

    assert %{"matches" => []} = json_response(conn, 200)
  end

  test "shows a match by id", %{conn: conn, token: token, user: user} do
    {:ok, match} =
      History.record_match(%{
        mode: "solo",
        player_count: 1,
        players: [%{user_id: user.id, score: 9000}]
      })

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/matches/#{match.id}")

    assert %{"match" => returned} = json_response(conn, 200)
    assert returned["id"] == match.id
    assert length(returned["players"]) == 1
  end

  test "returns 404 for missing match", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/matches/#{Ecto.UUID.generate()}")

    assert json_response(conn, 404)
  end

  test "returns 401 without token", %{conn: conn} do
    conn = get(conn, "/api/matches")
    assert json_response(conn, 401)
  end
end
