defmodule PlatformWeb.AuthControllerTest do
  use PlatformWeb.ConnCase, async: true

  alias Platform.Accounts
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
    test "redirects to client with JWT for existing user", %{conn: conn} do
      Accounts.register_user(%{
        provider: "google",
        provider_id: "google_test_uid",
        display_name: "Test User",
        nickname: "TestExisting"
      })

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

  describe "GET /auth/:provider/callback (new user)" do
    test "redirects with registration_token for new user", %{conn: conn} do
      auth = %Ueberauth.Auth{
        uid: "brand_new_uid",
        provider: :google,
        info: %Ueberauth.Auth.Info{
          name: "Brand New User",
          email: "brandnew@example.com",
          image: "https://example.com/new.jpg"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get("/auth/google/callback")

      location = redirected_to(conn)
      assert location =~ "registration_token="
      refute location =~ "#token="
    end
  end

  describe "POST /api/auth/register" do
    test "creates user from registration token", %{conn: conn} do
      reg_token =
        Token.sign_registration(%{
          provider: "google",
          provider_id: "register_test_1",
          name: "Reg User",
          email: "reg@example.com",
          avatar_url: nil
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", %{
          "registration_token" => reg_token,
          "nickname" => "RegPlayer",
          "display_name" => "Reg User"
        })

      body = json_response(conn, 200)
      assert body["token"]
      assert body["user"]["nickname"] == "RegPlayer"
      assert body["user"]["display_name"] == "Reg User"

      assert {:ok, user_id} = Token.verify(body["token"])
      user = Accounts.get_user(user_id)
      assert user.nickname == "RegPlayer"
    end

    test "upgrades guest user when guest_token provided", %{conn: conn} do
      guest_conn = post(conn, "/api/auth/guest")
      %{"token" => guest_token} = json_response(guest_conn, 200)

      reg_token =
        Token.sign_registration(%{
          provider: "github",
          provider_id: "guest_upgrade_1",
          name: "Upgraded User",
          email: "upgraded@example.com",
          avatar_url: nil
        })

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", %{
          "registration_token" => reg_token,
          "nickname" => "UpgradedPlayer",
          "display_name" => "Upgraded User",
          "guest_token" => guest_token
        })

      body = json_response(conn, 200)
      assert body["token"]
      assert body["user"]["nickname"] == "UpgradedPlayer"

      {:ok, guest_id} = Token.verify(guest_token)
      {:ok, new_id} = Token.verify(body["token"])
      assert new_id == guest_id
    end

    test "returns 401 for invalid registration token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", %{
          "registration_token" => "invalid",
          "nickname" => "Test",
          "display_name" => "Test"
        })

      assert json_response(conn, 401)["error"]
    end

    test "returns 422 for invalid nickname", %{conn: conn} do
      reg_token =
        Token.sign_registration(%{
          provider: "google",
          provider_id: "bad_nick_test",
          name: "Test",
          email: nil,
          avatar_url: nil
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", %{
          "registration_token" => reg_token,
          "nickname" => "1bad",
          "display_name" => "Test"
        })

      assert json_response(conn, 422)["errors"]
    end

    test "returns 422 for duplicate nickname", %{conn: conn} do
      Accounts.register_user(%{
        provider: "google",
        provider_id: "dup_nick_existing",
        display_name: "Existing",
        nickname: "DupNick"
      })

      reg_token =
        Token.sign_registration(%{
          provider: "google",
          provider_id: "dup_nick_new",
          name: "New",
          email: nil,
          avatar_url: nil
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/register", %{
          "registration_token" => reg_token,
          "nickname" => "DupNick",
          "display_name" => "New"
        })

      assert json_response(conn, 422)["errors"]
    end
  end

  describe "GET /api/auth/check-nickname/:nickname" do
    test "returns available for unused nickname", %{conn: conn} do
      conn = get(conn, "/api/auth/check-nickname/FreshNick")
      body = json_response(conn, 200)
      assert body["available"] == true
      assert body["nickname"] == "FreshNick"
    end

    test "returns unavailable for taken nickname", %{conn: conn} do
      Accounts.register_user(%{
        provider: "google",
        provider_id: "check_taken_1",
        display_name: "Taken",
        nickname: "TakenCheck"
      })

      conn = get(conn, "/api/auth/check-nickname/TakenCheck")
      body = json_response(conn, 200)
      assert body["available"] == false
      assert body["reason"] == "taken"
    end

    test "returns unavailable for invalid format", %{conn: conn} do
      conn = get(conn, "/api/auth/check-nickname/1bad")
      body = json_response(conn, 200)
      assert body["available"] == false
      assert body["reason"] == "invalid_format"
    end
  end
end
