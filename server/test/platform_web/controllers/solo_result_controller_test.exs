defmodule PlatformWeb.SoloResultControllerTest do
  use PlatformWeb.ConnCase, async: true

  alias Platform.Accounts
  alias Platform.Auth.Token

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        provider: "test",
        provider_id: "solo_test",
        display_name: "Tester"
      })

    token = Token.sign(user.id)
    %{user: user, token: token}
  end

  test "creates solo result with valid token", %{
    conn: conn,
    token: token,
    user: user
  } do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/solo_results", %{
        score: 5000,
        lines_cleared: 20,
        pieces_placed: 80,
        duration_ms: 120_000
      })

    assert %{"match_id" => match_id} = json_response(conn, 201)
    assert {:ok, match} = Platform.History.get_match(match_id)
    assert match.mode == "solo"

    [player] = match.match_players
    assert player.user_id == user.id
    assert player.score == 5000
  end

  test "returns 401 without token", %{conn: conn} do
    conn = post(conn, "/api/solo_results", %{score: 1000})
    assert json_response(conn, 401)
  end

  test "returns 401 with invalid token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer invalid.token.here")
      |> post("/api/solo_results", %{score: 1000})

    assert json_response(conn, 401)
  end
end
