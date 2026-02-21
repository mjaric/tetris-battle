# Auth & Registration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add custom OAuth authentication (Google, GitHub, Discord) with guest play and JWT-based session management to the existing tetris-battle app.

**Architecture:** Ueberauth handles OAuth provider flows via HTTP redirects. JOSE signs/verifies HS256 JWTs derived from Phoenix's `secret_key_base`. PostgreSQL via Ecto stores user records. The client has no external auth SDK — login buttons link to server-side OAuth routes, and the server redirects back with a JWT. Guest login is a simple POST endpoint.

**Tech Stack:** Ecto + Postgrex (PostgreSQL), JOSE (JWT), Ueberauth + strategies (OAuth), React context (client auth state)

**Design doc:** `docs/plans/2026-02-20-auth-registration-design.md`

**Depends on:** Nothing (this is the foundation plan)

---

## Task 1: Add Ecto and PostgreSQL to the Server

**Files:**
- Modify: `server/mix.exs`
- Create: `server/lib/platform/repo.ex`
- Modify: `server/lib/tetris/application.ex`
- Modify: `server/config/config.exs`
- Modify: `server/config/dev.exs`
- Modify: `server/config/test.exs`
- Modify: `server/config/runtime.exs`
- Modify: `server/test/test_helper.exs`
- Create: `server/test/support/data_case.ex`
- Create: `server/test/support/conn_case.ex`

**Step 1: Add dependencies to mix.exs**

In `server/mix.exs`, add to the `deps` function:

```elixir
{:ecto_sql, "~> 3.12"},
{:postgrex, "~> 0.20"},
```

Update the `aliases` function:

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup"],
    "ecto.setup": ["ecto.create", "ecto.migrate"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
  ]
end
```

**Step 2: Create the Ecto Repo module**

Create `server/lib/platform/repo.ex`:

```elixir
defmodule Platform.Repo do
  use Ecto.Repo,
    otp_app: :tetris,
    adapter: Ecto.Adapters.Postgres
end
```

**Step 3: Add Repo to supervision tree**

In `server/lib/tetris/application.ex`, add `Platform.Repo` before
`{Registry, ...}`:

```elixir
children = [
  TetrisWeb.Telemetry,
  {Phoenix.PubSub, name: Tetris.PubSub},
  Platform.Repo,
  {Registry, keys: :unique, name: TetrisGame.RoomRegistry},
  TetrisGame.RoomSupervisor,
  TetrisGame.BotSupervisor,
  TetrisGame.Lobby,
  TetrisWeb.Endpoint
]
```

**Step 4: Configure Ecto in config files**

In `server/config/config.exs`, add before the `import_config` line:

```elixir
config :tetris, Platform.Repo,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime]

config :tetris, ecto_repos: [Platform.Repo]
```

In `server/config/dev.exs`, add:

```elixir
config :tetris, Platform.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tetris_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

In `server/config/test.exs`, add:

```elixir
config :tetris, Platform.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "tetris_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
```

In `server/config/runtime.exs`, add inside the `if config_env() == :prod`
block:

```elixir
database_url =
  System.get_env("DATABASE_URL") ||
    raise "environment variable DATABASE_URL is missing."

config :tetris, Platform.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
```

**Step 5: Update test_helper.exs**

Replace `server/test/test_helper.exs` with:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Platform.Repo, :manual)
```

**Step 6: Create DataCase test helper**

Create `server/test/support/data_case.ex`:

```elixir
defmodule Platform.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Platform.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Platform.DataCase
    end
  end

  setup tags do
    Platform.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(
      Platform.Repo,
      shared: !tags[:async]
    )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
  end
end
```

**Step 7: Create ConnCase test helper**

Create `server/test/support/conn_case.ex`:

```elixir
defmodule PlatformWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import PlatformWeb.ConnCase

      @endpoint TetrisWeb.Endpoint
    end
  end

  setup tags do
    Platform.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
```

**Step 8: Fetch deps, create database, verify**

Run:
```bash
cd server && mix deps.get
cd server && mix ecto.create
cd server && mix test
```

Expected: All existing tests still pass. Database `tetris_test` created.

**Step 9: Commit**

```bash
git add server/mix.exs server/mix.lock server/lib/platform/repo.ex \
  server/lib/tetris/application.ex server/config/ \
  server/test/test_helper.exs server/test/support/data_case.ex \
  server/test/support/conn_case.ex
git commit -m "feat: add Ecto and PostgreSQL to server"
```

---

## Task 2: Users Migration and Schema

**Files:**
- Create: `server/priv/repo/migrations/*_create_users.exs`
- Create: `server/lib/platform/accounts/user.ex`
- Create: `server/lib/platform/accounts.ex`
- Create: `server/test/platform/accounts_test.exs`

**Step 1: Generate migration**

Run:
```bash
cd server && mix ecto.gen.migration create_users
```

**Step 2: Write the users migration**

Edit the generated migration file in `server/priv/repo/migrations/`:

```elixir
defmodule Platform.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :text
      add :provider_id, :text, null: false
      add :email, :text
      add :display_name, :text, null: false
      add :avatar_url, :text
      add :is_anonymous, :boolean, default: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:provider, :provider_id])
    create index(:users, [:display_name])
  end
end
```

**Step 3: Write the failing tests**

Create `server/test/platform/accounts_test.exs`:

```elixir
defmodule Platform.AccountsTest do
  use Platform.DataCase, async: true

  alias Platform.Accounts
  alias Platform.Accounts.User

  describe "create_user/1" do
    test "creates a user with valid attrs" do
      attrs = %{
        provider: "google",
        provider_id: "google_123",
        display_name: "TestUser",
        email: "test@example.com"
      }

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.provider == "google"
      assert user.provider_id == "google_123"
      assert user.display_name == "TestUser"
      assert user.is_anonymous == false
    end

    test "fails without required fields" do
      assert {:error, changeset} = Accounts.create_user(%{})
      errors = errors_on(changeset)
      assert errors[:provider_id]
      assert errors[:display_name]
    end

    test "fails on duplicate provider + provider_id" do
      attrs = %{
        provider: "google",
        provider_id: "dup_id",
        display_name: "User1"
      }

      assert {:ok, _} = Accounts.create_user(attrs)

      assert {:error, changeset} =
               Accounts.create_user(%{attrs | display_name: "User2"})

      assert %{provider_id: _} = errors_on(changeset)
    end
  end

  describe "find_or_create_user/1" do
    test "creates new user when not found" do
      attrs = %{
        provider: "github",
        provider_id: "new_uid",
        display_name: "NewUser"
      }

      assert {:ok, %User{}} = Accounts.find_or_create_user(attrs)
    end

    test "returns existing user when found" do
      attrs = %{
        provider: "github",
        provider_id: "existing_uid",
        display_name: "Existing"
      }

      {:ok, original} = Accounts.create_user(attrs)
      {:ok, found} = Accounts.find_or_create_user(attrs)
      assert found.id == original.id
    end
  end

  describe "get_user/1" do
    test "returns user by id" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "google",
          provider_id: "get_test",
          display_name: "GetTest"
        })

      assert %User{} = Accounts.get_user(user.id)
    end

    test "returns nil for nonexistent id" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "upgrade_anonymous_user/2" do
    test "upgrades anonymous user in-place" do
      {:ok, anon} =
        Accounts.create_user(%{
          provider: "anonymous",
          provider_id: Ecto.UUID.generate(),
          display_name: "Guest_abc",
          is_anonymous: true
        })

      upgrade_attrs = %{
        provider: "google",
        provider_id: "google_456",
        display_name: "RealUser",
        email: "real@example.com",
        is_anonymous: false
      }

      assert {:ok, upgraded} =
               Accounts.upgrade_anonymous_user(anon, upgrade_attrs)

      assert upgraded.id == anon.id
      assert upgraded.provider == "google"
      assert upgraded.provider_id == "google_456"
      assert upgraded.is_anonymous == false
    end

    test "no-op for non-anonymous user" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "google",
          provider_id: "already_real",
          display_name: "Already"
        })

      assert {:ok, same} =
               Accounts.upgrade_anonymous_user(user, %{provider: "github"})

      assert same.id == user.id
      assert same.provider == "google"
    end
  end

  describe "search_users_by_name/2" do
    test "finds users by partial name match" do
      Accounts.create_user(%{
        provider: "a",
        provider_id: "u1",
        display_name: "AliceSmith"
      })

      Accounts.create_user(%{
        provider: "a",
        provider_id: "u2",
        display_name: "BobAlice"
      })

      Accounts.create_user(%{
        provider: "a",
        provider_id: "u3",
        display_name: "Charlie"
      })

      results = Accounts.search_users_by_name("Alice")
      assert length(results) == 2
    end

    test "excludes anonymous users" do
      Accounts.create_user(%{
        provider: "anonymous",
        provider_id: "anon1",
        display_name: "Alice",
        is_anonymous: true
      })

      assert Accounts.search_users_by_name("Alice") == []
    end

    test "sanitizes ILIKE special characters" do
      Accounts.create_user(%{
        provider: "a",
        provider_id: "u4",
        display_name: "Normal"
      })

      # These should not act as SQL wildcards
      assert Accounts.search_users_by_name("100%") == []
      assert Accounts.search_users_by_name("a_b") == []
    end
  end
end
```

**Step 4: Run tests to verify they fail**

Run:
```bash
cd server && mix ecto.migrate
cd server && mix test test/platform/accounts_test.exs -v
```

Expected: FAIL — modules not defined.

**Step 5: Write the User Ecto schema**

Create `server/lib/platform/accounts/user.ex`:

```elixir
defmodule Platform.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :provider, :string
    field :provider_id, :string
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
    field :is_anonymous, :boolean, default: false
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields [:provider_id, :display_name]
  @optional_fields [
    :provider,
    :email,
    :avatar_url,
    :is_anonymous,
    :settings
  ]

  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:provider, :provider_id])
  end
end
```

**Step 6: Write the Accounts context**

Create `server/lib/platform/accounts.ex`:

```elixir
defmodule Platform.Accounts do
  import Ecto.Query
  alias Platform.Repo
  alias Platform.Accounts.User

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_provider(provider, provider_id) do
    Repo.get_by(User, provider: provider, provider_id: provider_id)
  end

  def find_or_create_user(attrs) do
    changeset = User.changeset(%User{}, attrs)

    Repo.insert(
      changeset,
      on_conflict: :nothing,
      conflict_target: [:provider, :provider_id]
    )
    |> case do
      {:ok, %User{id: nil}} ->
        # on_conflict: :nothing returns struct with nil id
        user =
          get_user_by_provider(attrs[:provider] || attrs.provider, attrs[:provider_id] || attrs.provider_id)

        {:ok, user}

      result ->
        result
    end
  end

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def upgrade_anonymous_user(%User{is_anonymous: true} = user, attrs) do
    update_user(user, attrs)
  end

  def upgrade_anonymous_user(%User{is_anonymous: false} = user, _attrs) do
    {:ok, user}
  end

  def search_users_by_name(query_string, limit \\ 20) do
    sanitized =
      query_string
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    pattern = "%#{sanitized}%"

    User
    |> where([u], ilike(u.display_name, ^pattern))
    |> where([u], u.is_anonymous == false)
    |> limit(^limit)
    |> Repo.all()
  end
end
```

**Step 7: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform/accounts_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 8: Commit**

```bash
git add server/priv/repo/migrations/ server/lib/platform/accounts/ \
  server/lib/platform/accounts.ex server/test/platform/
git commit -m "feat: add users schema and accounts context"
```

---

## Task 3: JWT Token Module

**Files:**
- Modify: `server/mix.exs` (add `jose` dependency)
- Create: `server/lib/platform/auth/token.ex`
- Create: `server/test/platform/auth/token_test.exs`

**Step 1: Add JOSE dependency**

Add to deps in `server/mix.exs`:

```elixir
{:jose, "~> 1.11"},
```

Run: `cd server && mix deps.get`

**Step 2: Write the failing tests**

Create `server/test/platform/auth/token_test.exs`:

```elixir
defmodule Platform.Auth.TokenTest do
  use ExUnit.Case, async: true

  alias Platform.Auth.Token

  @test_user_id "550e8400-e29b-41d4-a716-446655440000"

  describe "sign/1 and verify/1" do
    test "round-trips a user_id" do
      token = Token.sign(@test_user_id)
      assert {:ok, @test_user_id} = Token.verify(token)
    end

    test "rejects a tampered token" do
      token = Token.sign(@test_user_id)
      tampered = token <> "x"
      assert {:error, :invalid_token} = Token.verify(tampered)
    end

    test "rejects a completely invalid string" do
      assert {:error, :invalid_token} = Token.verify("not.a.jwt")
    end

    test "rejects nil" do
      assert {:error, :invalid_token} = Token.verify(nil)
    end
  end

  describe "sign/2 with custom ttl" do
    test "rejects an expired token" do
      # Sign with ttl of -1 second (already expired)
      token = Token.sign(@test_user_id, ttl: -1)
      assert {:error, :token_expired} = Token.verify(token)
    end
  end
end
```

**Step 3: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/platform/auth/token_test.exs -v
```

Expected: FAIL — module not defined.

**Step 4: Write the Token module**

Create `server/lib/platform/auth/token.ex`:

```elixir
defmodule Platform.Auth.Token do
  @default_ttl 3600

  def sign(user_id, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    now = System.system_time(:second)

    claims = %{
      "sub" => user_id,
      "iat" => now,
      "exp" => now + ttl
    }

    jwk = signing_key()
    jws = JOSE.JWS.from_map(%{"alg" => "HS256"})
    jwt = JOSE.JWT.from_map(claims)
    {_, token} = JOSE.JWT.sign(jwk, jws, jwt) |> JOSE.JWS.compact()
    token
  end

  def verify(token) when is_binary(token) do
    jwk = signing_key()

    case JOSE.JWT.verify(jwk, token) do
      {true, %JOSE.JWT{fields: claims}, _} ->
        validate_expiry(claims)

      _ ->
        {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  def verify(_), do: {:error, :invalid_token}

  defp validate_expiry(claims) do
    now = System.system_time(:second)
    exp = Map.get(claims, "exp", 0)

    if exp > now do
      {:ok, claims["sub"]}
    else
      {:error, :token_expired}
    end
  end

  defp signing_key do
    secret =
      Application.get_env(:tetris, TetrisWeb.Endpoint)[:secret_key_base]

    derived =
      :crypto.mac(:hmac, :sha256, secret, "platform_jwt_signing")

    JOSE.JWK.from_oct(derived)
  end
end
```

**Step 5: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform/auth/token_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 6: Commit**

```bash
git add server/mix.exs server/mix.lock \
  server/lib/platform/auth/token.ex \
  server/test/platform/auth/
git commit -m "feat: add JWT token signing and verification"
```

---

## Task 4: Ueberauth and Auth Controller

**Files:**
- Modify: `server/mix.exs` (add ueberauth deps)
- Modify: `server/config/config.exs`
- Modify: `server/config/dev.exs`
- Modify: `server/config/test.exs`
- Modify: `server/config/runtime.exs`
- Modify: `server/lib/tetris_web/endpoint.ex` (add Plug.Session)
- Modify: `server/lib/tetris_web/router.ex` (add auth routes)
- Create: `server/lib/platform_web/controllers/auth_controller.ex`
- Create: `server/test/platform_web/controllers/auth_controller_test.exs`

**Step 1: Add Ueberauth dependencies**

Add to deps in `server/mix.exs`:

```elixir
{:ueberauth, "~> 0.10"},
{:ueberauth_google, "~> 0.12"},
{:ueberauth_github, "~> 0.8"},
{:ueberauth_discord, "~> 0.7"},
```

Run: `cd server && mix deps.get`

**Step 2: Configure Ueberauth providers**

In `server/config/config.exs`, add before the `import_config` line:

```elixir
config :ueberauth, Ueberauth,
  base_path: "/auth",
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]},
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email"]},
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify email"]}
  ]

config :tetris, :client_url, "http://localhost:3000"
```

In `server/config/dev.exs`, add:

```elixir
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: {System, :get_env, ["GOOGLE_CLIENT_ID"]},
  client_secret: {System, :get_env, ["GOOGLE_CLIENT_SECRET"]}

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: {System, :get_env, ["GITHUB_CLIENT_ID"]},
  client_secret: {System, :get_env, ["GITHUB_CLIENT_SECRET"]}

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: {System, :get_env, ["DISCORD_CLIENT_ID"]},
  client_secret: {System, :get_env, ["DISCORD_CLIENT_SECRET"]}
```

In `server/config/test.exs`, add:

```elixir
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, []},
    github: {Ueberauth.Strategy.Github, []},
    discord: {Ueberauth.Strategy.Discord, []}
  ]
```

In `server/config/runtime.exs`, add inside the `if config_env() == :prod`
block:

```elixir
client_url =
  System.get_env("CLIENT_URL") ||
    raise "environment variable CLIENT_URL is missing."

config :tetris, :client_url, client_url

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
  client_id: System.get_env("DISCORD_CLIENT_ID"),
  client_secret: System.get_env("DISCORD_CLIENT_SECRET")
```

**Step 3: Add Plug.Session to endpoint**

In `server/lib/tetris_web/endpoint.ex`, add after the
`plug(Plug.MethodOverride)` line:

```elixir
plug(Plug.Session,
  store: :cookie,
  key: "_tetris_session",
  signing_salt: "auth_session"
)
```

**Step 4: Add auth routes to router**

Replace `server/lib/tetris_web/router.ex` with:

```elixir
defmodule TetrisWeb.Router do
  use Phoenix.Router
  import Plug.Conn

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/auth", PlatformWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/api/auth", PlatformWeb do
    pipe_through :api

    post "/guest", AuthController, :guest
    post "/refresh", AuthController, :refresh
  end

  scope "/api", TetrisWeb do
    pipe_through(:api)
  end

  scope "/", TetrisWeb do
    get("/*path", PageController, :index)
  end
end
```

**Step 5: Write the failing tests**

Create `server/test/platform_web/controllers/auth_controller_test.exs`:

```elixir
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
      # Create a user first
      conn1 = post(conn, "/api/auth/guest")
      %{"token" => token} = json_response(conn1, 200)

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

      assert redirected_to(conn) =~ "http://localhost:3000/auth/callback#token="
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
```

**Step 6: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/platform_web/controllers/auth_controller_test.exs -v
```

Expected: FAIL — controller module not defined.

**Step 7: Write the AuthController**

Create `server/lib/platform_web/controllers/auth_controller.ex`:

```elixir
defmodule PlatformWeb.AuthController do
  use Phoenix.Controller
  plug Ueberauth when action in [:request, :callback]

  alias Platform.Accounts
  alias Platform.Auth.Token

  def callback(
        %{assigns: %{ueberauth_auth: auth}} = conn,
        _params
      ) do
    user_attrs = %{
      provider: to_string(auth.provider),
      provider_id: auth.uid,
      email: auth.info.email,
      display_name:
        auth.info.name || auth.info.email || "Player",
      avatar_url: auth.info.image
    }

    {:ok, user} = Accounts.find_or_create_user(user_attrs)
    token = Token.sign(user.id)
    client_url = Application.get_env(:tetris, :client_url)
    redirect(conn, external: "#{client_url}/auth/callback#token=#{token}")
  end

  def callback(
        %{assigns: %{ueberauth_failure: failure}} = conn,
        _params
      ) do
    reason =
      failure.errors
      |> Enum.map(& &1.message)
      |> Enum.join(", ")

    client_url = Application.get_env(:tetris, :client_url)

    redirect(conn,
      external: "#{client_url}/auth/callback?error=#{URI.encode(reason)}"
    )
  end

  def guest(conn, _params) do
    guest_id = Ecto.UUID.generate()

    {:ok, user} =
      Accounts.create_user(%{
        provider: "anonymous",
        provider_id: guest_id,
        display_name: "Guest_#{String.slice(guest_id, 0..5)}",
        is_anonymous: true
      })

    token = Token.sign(user.id)

    json(conn, %{
      token: token,
      user: %{id: user.id, display_name: user.display_name}
    })
  end

  def refresh(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user_id} <- Token.verify(token),
         %Accounts.User{} <- Accounts.get_user(user_id) do
      new_token = Token.sign(user_id)
      json(conn, %{token: new_token})
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_token"})
    end
  end
end
```

**Step 8: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/platform_web/controllers/auth_controller_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 9: Commit**

```bash
git add server/mix.exs server/mix.lock server/config/ \
  server/lib/tetris_web/endpoint.ex server/lib/tetris_web/router.ex \
  server/lib/platform_web/ server/test/platform_web/
git commit -m "feat: add Ueberauth OAuth and auth controller"
```

---

## Task 5: Socket Auth Integration

**Files:**
- Modify: `server/lib/tetris_web/channels/user_socket.ex`
- Modify: `server/test/support/channel_case.ex`
- Create: `server/test/tetris_web/channels/user_socket_test.exs`

**Step 1: Write the failing tests**

Create `server/test/tetris_web/channels/user_socket_test.exs`:

```elixir
defmodule TetrisWeb.UserSocketTest do
  use Platform.DataCase, async: true

  alias TetrisWeb.UserSocket
  alias Platform.Accounts
  alias Platform.Auth.Token

  describe "connect/3" do
    test "connects with a valid JWT" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "google",
          provider_id: "socket_test",
          display_name: "SocketUser"
        })

      token = Token.sign(user.id)

      assert {:ok, socket} =
               UserSocket.connect(%{"token" => token}, %Phoenix.Socket{})

      assert socket.assigns.user_id == user.id
      assert socket.assigns.player_id == user.id
      assert socket.assigns.nickname == "SocketUser"
    end

    test "rejects invalid token" do
      assert :error =
               UserSocket.connect(
                 %{"token" => "bad_token"},
                 %Phoenix.Socket{}
               )
    end

    test "rejects missing token" do
      assert :error =
               UserSocket.connect(%{}, %Phoenix.Socket{})
    end

    test "rejects token for deleted user" do
      token = Token.sign(Ecto.UUID.generate())

      assert :error =
               UserSocket.connect(
                 %{"token" => token},
                 %Phoenix.Socket{}
               )
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
cd server && mix test test/tetris_web/channels/user_socket_test.exs -v
```

Expected: FAIL — existing `connect` clause matches `%{"nickname" => ...}`
instead of `%{"token" => ...}`.

**Step 3: Modify UserSocket**

Replace `server/lib/tetris_web/channels/user_socket.ex`:

```elixir
defmodule TetrisWeb.UserSocket do
  use Phoenix.Socket

  alias Platform.Auth.Token
  alias Platform.Accounts

  channel("lobby:*", TetrisWeb.LobbyChannel)
  channel("game:*", TetrisWeb.GameChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    with {:ok, user_id} <- Token.verify(token),
         %Accounts.User{} = user <- Accounts.get_user(user_id) do
      socket =
        socket
        |> assign(:user_id, user.id)
        |> assign(:player_id, user.id)
        |> assign(:nickname, user.display_name)

      {:ok, socket}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
```

**Step 4: Update ChannelCase for Ecto sandbox**

Replace `server/test/support/channel_case.ex`:

```elixir
defmodule TetrisWeb.ChannelCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      @endpoint TetrisWeb.Endpoint
    end
  end

  setup tags do
    Platform.DataCase.setup_sandbox(tags)
    :ok
  end
end
```

**Step 5: Run tests to verify they pass**

Run:
```bash
cd server && mix test test/tetris_web/channels/user_socket_test.exs -v
cd server && mix test
```

Expected: New socket tests pass. Existing channel tests may need updating
if they relied on nickname-based connect — check output and fix any
failures by creating a test user and using a JWT in test setup.

**Step 6: Fix existing channel tests (if needed)**

Existing tests in `server/test/tetris_web/channels/` that use
`socket(TetrisWeb.UserSocket, ...)` or connect with `%{"nickname" => ...}`
must be updated to create a user, sign a JWT, and connect with
`%{"token" => token}`.

Look for any tests matching `connect(TetrisWeb.UserSocket, %{"nickname"` and update
them to:

```elixir
{:ok, user} =
  Platform.Accounts.create_user(%{
    provider: "test",
    provider_id: "test_#{System.unique_integer([:positive])}",
    display_name: "TestPlayer"
  })

token = Platform.Auth.Token.sign(user.id)
{:ok, socket} = connect(TetrisWeb.UserSocket, %{"token" => token})
```

**Step 7: Run full test suite**

Run:
```bash
cd server && mix test
```

Expected: All tests pass.

**Step 8: Commit**

```bash
git add server/lib/tetris_web/channels/user_socket.ex \
  server/test/support/channel_case.ex \
  server/test/tetris_web/
git commit -m "feat: add JWT auth to UserSocket, remove nickname-only connect"
```

---

## Task 6: Client — Auth Provider and Login Screen

**Files:**
- Create: `client/src/platform/auth/AuthProvider.tsx`
- Create: `client/src/platform/auth/useAuth.ts`
- Create: `client/src/platform/auth/LoginScreen.tsx`
- Create: `client/src/platform/auth/AuthCallback.tsx`

**Step 1: Create AuthProvider context**

Create `client/src/platform/auth/AuthProvider.tsx`:

```tsx
import {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';
const TOKEN_KEY = 'tetris_auth_token';

interface AuthUser {
  id: string;
  displayName: string;
}

interface AuthContextValue {
  user: AuthUser | null;
  token: string | null;
  loading: boolean;
  isAuthenticated: boolean;
  setToken: (token: string | null) => void;
  logout: () => void;
  refreshToken: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const payload = parts[1];
  if (!payload) return null;
  const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
  return JSON.parse(json) as Record<string, unknown>;
}

function isTokenExpired(token: string): boolean {
  const payload = decodeJwtPayload(token);
  if (!payload || typeof payload['exp'] !== 'number') return true;
  return payload['exp'] * 1000 < Date.now();
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setTokenState] = useState<string | null>(null);
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);

  const setToken = useCallback((newToken: string | null) => {
    if (newToken) {
      localStorage.setItem(TOKEN_KEY, newToken);
      setTokenState(newToken);
    } else {
      localStorage.removeItem(TOKEN_KEY);
      setTokenState(null);
      setUser(null);
    }
  }, []);

  const logout = useCallback(() => {
    setToken(null);
  }, [setToken]);

  const refreshToken = useCallback(async () => {
    if (!token) return;

    const resp = await fetch(`${API_URL}/api/auth/refresh`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
    });

    if (resp.ok) {
      const data = (await resp.json()) as { token: string };
      setToken(data.token);
    } else {
      logout();
    }
  }, [token, setToken, logout]);

  useEffect(() => {
    const stored = localStorage.getItem(TOKEN_KEY);
    if (stored && !isTokenExpired(stored)) {
      setTokenState(stored);
    } else if (stored) {
      localStorage.removeItem(TOKEN_KEY);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    if (!token) {
      setUser(null);
      return;
    }

    const payload = decodeJwtPayload(token);
    if (payload && typeof payload['sub'] === 'string') {
      setUser({
        id: payload['sub'],
        displayName: (payload['name'] as string) ?? 'Player',
      });
    }
  }, [token]);

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      token,
      loading,
      isAuthenticated: !!token && !!user,
      setToken,
      logout,
      refreshToken,
    }),
    [user, token, loading, setToken, logout, refreshToken],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuthContext(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error('useAuthContext must be used within AuthProvider');
  }
  return ctx;
}
```

**Step 2: Create useAuth hook**

Create `client/src/platform/auth/useAuth.ts`:

```typescript
import { useCallback } from 'react';
import { useAuthContext } from './AuthProvider.tsx';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';

interface UseAuthResult {
  user: { id: string; displayName: string } | null;
  token: string | null;
  loading: boolean;
  isAuthenticated: boolean;
  loginWithGoogle: () => void;
  loginWithGithub: () => void;
  loginWithDiscord: () => void;
  loginAsGuest: () => Promise<void>;
  logout: () => void;
}

export function useAuth(): UseAuthResult {
  const { user, token, loading, isAuthenticated, setToken, logout } =
    useAuthContext();

  const loginWithGoogle = useCallback(() => {
    window.location.href = `${API_URL}/auth/google`;
  }, []);

  const loginWithGithub = useCallback(() => {
    window.location.href = `${API_URL}/auth/github`;
  }, []);

  const loginWithDiscord = useCallback(() => {
    window.location.href = `${API_URL}/auth/discord`;
  }, []);

  const loginAsGuest = useCallback(async () => {
    const resp = await fetch(`${API_URL}/api/auth/guest`, {
      method: 'POST',
    });

    if (resp.ok) {
      const data = (await resp.json()) as { token: string };
      setToken(data.token);
    }
  }, [setToken]);

  return {
    user,
    token,
    loading,
    isAuthenticated,
    loginWithGoogle,
    loginWithGithub,
    loginWithDiscord,
    loginAsGuest,
    logout,
  };
}
```

**Step 3: Create LoginScreen**

Create `client/src/platform/auth/LoginScreen.tsx`:

```tsx
import { useAuth } from './useAuth.ts';

export default function LoginScreen() {
  const { loginWithGoogle, loginWithGithub, loginWithDiscord, loginAsGuest } =
    useAuth();

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-12 text-5xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris
      </h1>

      <div className="w-full max-w-sm space-y-4">
        <button
          onClick={loginWithGoogle}
          className="w-full cursor-pointer rounded-lg bg-white px-4 py-3 font-medium text-gray-800 hover:bg-gray-100"
        >
          Continue with Google
        </button>
        <button
          onClick={loginWithGithub}
          className="w-full cursor-pointer rounded-lg bg-gray-700 px-4 py-3 font-medium text-white hover:bg-gray-600"
        >
          Continue with GitHub
        </button>
        <button
          onClick={loginWithDiscord}
          className="w-full cursor-pointer rounded-lg bg-indigo-600 px-4 py-3 font-medium text-white hover:bg-indigo-500"
        >
          Continue with Discord
        </button>

        <div className="relative py-2">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-border" />
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="bg-bg-primary px-2 text-gray-500">or</span>
          </div>
        </div>

        <button
          onClick={() => void loginAsGuest()}
          className="w-full cursor-pointer rounded-lg border border-border px-4 py-3 font-medium text-gray-400 hover:bg-bg-tertiary"
        >
          Play as Guest
        </button>
        <p className="text-center text-xs text-gray-600">
          Guest accounts can be upgraded later
        </p>
      </div>
    </div>
  );
}
```

**Step 4: Create AuthCallback page**

Create `client/src/platform/auth/AuthCallback.tsx`:

```tsx
import { useEffect } from 'react';
import { useNavigate } from 'react-router';
import { useAuthContext } from './AuthProvider.tsx';

export default function AuthCallback() {
  const navigate = useNavigate();
  const { setToken } = useAuthContext();

  useEffect(() => {
    const hash = window.location.hash;
    const params = new URLSearchParams(window.location.search);

    if (hash.startsWith('#token=')) {
      const token = hash.slice('#token='.length);
      setToken(token);
      window.history.replaceState(null, '', '/auth/callback');
      navigate('/', { replace: true });
      return;
    }

    const error = params.get('error');
    if (error) {
      // eslint-disable-next-line no-console
      console.error('Auth error:', error);
    }

    navigate('/login', { replace: true });
  }, [navigate, setToken]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-primary">
      <p className="text-gray-400">Signing in...</p>
    </div>
  );
}
```

**Step 5: Verify build**

Run:
```bash
cd client && npm run build
```

Expected: Build succeeds (components exist but aren't wired into App.tsx
yet).

**Step 6: Commit**

```bash
git add client/src/platform/
git commit -m "feat: add auth provider, login screen, and OAuth callback"
```

---

## Task 7: Client — App Integration

**Files:**
- Modify: `client/src/App.tsx`
- Modify: `client/src/hooks/useSocket.ts`
- Modify: `client/src/context/GameContext.tsx`
- Modify: `client/src/components/MainMenu.tsx`

**Step 1: Modify useSocket to accept token**

Replace `client/src/hooks/useSocket.ts`:

```typescript
import { useState, useEffect, useRef } from 'react';
import { Socket, type Channel } from 'phoenix';

const SOCKET_URL =
  import.meta.env['VITE_SOCKET_URL'] ?? 'ws://localhost:4000/socket';

interface UseSocketResult {
  socket: Socket | null;
  connected: boolean;
  playerId: string | null;
  lobbyChannel: Channel | null;
}

export function useSocket(token: string | null): UseSocketResult {
  const [socket, setSocket] = useState<Socket | null>(null);
  const [connected, setConnected] = useState(false);
  const [playerId, setPlayerId] = useState<string | null>(null);
  const [lobbyChannel, setLobbyChannel] = useState<Channel | null>(null);
  const socketRef = useRef<Socket | null>(null);
  const lobbyRef = useRef<Channel | null>(null);

  useEffect(() => {
    if (!token) return;

    const s = new Socket(SOCKET_URL, { params: { token } });
    s.connect();
    s.onOpen(() => setConnected(true));
    s.onClose(() => setConnected(false));
    socketRef.current = s;
    setSocket(s);

    const lobby = s.channel('lobby:main', {});
    lobby.join().receive('ok', (resp: { player_id: string }) => {
      setPlayerId(resp.player_id);
    });
    lobbyRef.current = lobby;
    setLobbyChannel(lobby);

    return () => {
      lobby.leave();
      lobbyRef.current = null;
      setLobbyChannel(null);
      s.disconnect();
      socketRef.current = null;
      setSocket(null);
      setConnected(false);
      setPlayerId(null);
    };
  }, [token]);

  return { socket, connected, playerId, lobbyChannel };
}
```

**Step 2: Modify GameContext to use auth token**

Replace `client/src/context/GameContext.tsx`:

```typescript
import { createContext, useContext, useMemo, type ReactNode } from 'react';
import type { Socket, Channel } from 'phoenix';
import { useSocket } from '../hooks/useSocket.ts';
import { useAuthContext } from '../platform/auth/AuthProvider.tsx';

interface GameContextValue {
  nickname: string | null;
  socket: Socket | null;
  connected: boolean;
  playerId: string | null;
  lobbyChannel: Channel | null;
}

const GameContext = createContext<GameContextValue | null>(null);

export function GameProvider({ children }: { children: ReactNode }) {
  const { token, user } = useAuthContext();
  const { socket, connected, playerId, lobbyChannel } = useSocket(token);
  const nickname = user?.displayName ?? null;

  const value = useMemo<GameContextValue>(
    () => ({
      nickname,
      socket,
      connected,
      playerId,
      lobbyChannel,
    }),
    [nickname, socket, connected, playerId, lobbyChannel],
  );

  return <GameContext.Provider value={value}>{children}</GameContext.Provider>;
}

export function useGameContext(): GameContextValue {
  const ctx = useContext(GameContext);
  if (!ctx) {
    throw new Error('useGameContext must be used within GameProvider');
  }
  return ctx;
}
```

**Step 3: Modify MainMenu to show user info**

Replace `client/src/components/MainMenu.tsx`:

```tsx
import { useNavigate } from 'react-router';
import { useAuth } from '../platform/auth/useAuth.ts';

export default function MainMenu() {
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      {user && (
        <div className="absolute top-6 right-6 flex items-center gap-3">
          <span className="text-sm text-gray-400">{user.displayName}</span>
          <button
            onClick={logout}
            className="cursor-pointer rounded border border-border px-3 py-1 text-xs text-gray-500 hover:text-white"
          >
            Logout
          </button>
        </div>
      )}

      <h1 className="mb-12 text-5xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris
      </h1>
      <button
        onClick={() => navigate('/solo')}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-accent px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Solo
      </button>
      <button
        onClick={() => navigate('/lobby')}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-green px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Multiplayer
      </button>
    </div>
  );
}
```

**Step 4: Modify App.tsx**

Replace `client/src/App.tsx`:

```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router';
import { AuthProvider, useAuthContext } from './platform/auth/AuthProvider.tsx';
import { GameProvider, useGameContext } from './context/GameContext.tsx';
import LoginScreen from './platform/auth/LoginScreen.tsx';
import AuthCallback from './platform/auth/AuthCallback.tsx';
import MainMenu from './components/MainMenu.tsx';
import SoloGame from './components/SoloGame.tsx';
import Lobby from './components/Lobby.tsx';
import GameSession from './components/GameSession.tsx';
import type { ReactNode } from 'react';

function RequireAuth({ children }: { children: ReactNode }) {
  const { isAuthenticated, loading } = useAuthContext();
  if (loading) return null;
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function RequireSocket({ children }: { children: ReactNode }) {
  const { connected } = useGameContext();
  if (!connected) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-bg-primary">
        <p className="text-gray-400">Connecting...</p>
      </div>
    );
  }
  return <>{children}</>;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginScreen />} />
      <Route path="/auth/callback" element={<AuthCallback />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <MainMenu />
          </RequireAuth>
        }
      />
      <Route path="/solo" element={<SoloGame />} />
      <Route
        path="/lobby"
        element={
          <RequireAuth>
            <RequireSocket>
              <Lobby />
            </RequireSocket>
          </RequireAuth>
        }
      />
      <Route
        path="/room/:roomId"
        element={
          <RequireAuth>
            <RequireSocket>
              <GameSession />
            </RequireSocket>
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <GameProvider>
          <AppRoutes />
        </GameProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
```

**Step 5: Verify client builds and lints**

Run:
```bash
cd client && npm run build
cd client && npm run lint
```

Expected: Build succeeds, lint passes. Fix any warnings.

**Step 6: Commit**

```bash
git add client/src/
git commit -m "feat: integrate auth into app routing and socket connection"
```

---

## Task 8: Clean Up Unused Files

**Files:**
- Delete: `client/src/components/NicknameForm.tsx`

**Step 1: Remove NicknameForm**

`NicknameForm` is no longer needed — the nickname comes from the auth
provider's display name.

Delete `client/src/components/NicknameForm.tsx`.

Verify no other file imports it:
```bash
cd client && grep -r "NicknameForm" src/
```

If no references remain, delete the file.

**Step 2: Verify build**

Run:
```bash
cd client && npm run build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add -u client/src/components/NicknameForm.tsx
git commit -m "chore: remove NicknameForm (nickname now from auth provider)"
```

---

## Task 9: Verification

**Step 1: Run all server tests**

```bash
cd server && mix test
```

Expected: All tests pass.

**Step 2: Run server lint and format**

```bash
cd server && mix format --check-formatted
cd server && mix credo --strict
```

Expected: No issues.

**Step 3: Run all client checks**

```bash
cd client && npm run lint
cd client && npm run format:check
cd client && npm run build
```

Expected: All pass.

**Step 4: Manual smoke test**

1. Start PostgreSQL
2. `cd server && mix ecto.reset && mix phx.server`
3. `cd client && npm run dev`
4. Verify: guest login works → JWT received → socket connects →
   lobby accessible → can create/join rooms

OAuth providers require registered credentials (Google/GitHub/Discord
developer consoles). Guest flow verifies the full auth pipeline without
external provider setup.

---

## Infrastructure Prerequisites

Before starting implementation:

1. **PostgreSQL** running locally (default: `localhost:5432`,
   user/pass: `postgres/postgres`)
2. **OAuth app registrations** (for full OAuth testing, not needed for
   guest flow):
   - Google: [console.cloud.google.com](https://console.cloud.google.com)
   - GitHub: Settings → Developer settings → OAuth Apps
   - Discord: [discord.com/developers](https://discord.com/developers)
3. **Environment variables** (for dev, set in shell or `.env`):
   - `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
   - `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`
   - `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET`
