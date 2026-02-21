defmodule PlatformWeb.AuthControllerTest do
  use PlatformWeb.ConnCase, async: true

  alias Platform.Auth.Token

  describe "POST /api/auth/guest" do
    test "creates an anonymous user and returns a JWT", %{conn: conn} do
      conn = post(conn, "/api/auth/guest")
      body = json_response(conn, 200)

      assert body["token"]
      assert {:ok, user_id} = Token.verify(body["token"])
      assert body["user"]["id"] == user_id
      assert body["user"]["display_name"]
    end
  end

  describe "POST /api/auth/refresh" do
    test "returns a new JWT for valid token", %{conn: conn} do
      conn1 = post(conn, "/api/auth/guest")
      %{"token" => token} = json_response(conn1, 200)

      # Wait so the new token gets a different iat/exp
      Process.sleep(1_100)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/auth/refresh")

      body = json_response(conn2, 200)
      assert body["token"]
      assert body["token"] != token
    end

    test "returns 401 for invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> post("/api/auth/refresh")

      assert json_response(conn, 401)["error"]
    end

    test "returns 401 for missing token", %{conn: conn} do
      conn = post(conn, "/api/auth/refresh")
      assert json_response(conn, 401)["error"]
    end
  end

  describe "GET /auth/:provider/callback" do
    test "redirects to client with JWT on success", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "google_test_uid",
        provider: :google,
        info: %Ueberauth.Auth.Info{
          name: "Test User",
          email: "test@example.com",
          image: "https://example.com/photo.jpg"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      assert redirected_to(conn) =~
               "http://localhost:4000/oauth/callback#token="
    end

    test "redirects to client with error on failure", %{conn: conn} do
      failure = %Ueberauth.Failure{
        provider: :google,
        errors: [
          %Ueberauth.Failure.Error{message: "access_denied"}
        ]
      }

      conn =
        conn
        |> assign(:ueberauth_failure, failure)
        |> get("/auth/google/callback")

      assert redirected_to(conn) =~ "error="
    end
  end
end
