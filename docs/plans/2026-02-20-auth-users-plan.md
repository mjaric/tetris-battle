# Auth, Users & Social — Implementation Plan (Plan 1 of 2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Firebase authentication, user accounts, and friends system with game invites to the existing tetris-battle app.

**Architecture:** Namespace-separated `Platform.*` modules added to the existing Phoenix app. Firebase Auth on client, ID token verification on server, PostgreSQL via Ecto for user persistence. Phoenix Presence for online status.

**Tech Stack:** Ecto + Postgrex (PostgreSQL), JOSE (JWT verification), Firebase JS SDK (client)

**Design doc:** `docs/plans/2026-02-20-auth-users-design.md`

**Depends on:** Nothing (this is the foundation plan)

**Followed by:** `docs/plans/2026-02-20-game-history-streaming-plan.md` (Plan 2)

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

**Step 1: Add dependencies to mix.exs**

Add to the `deps` function in `server/mix.exs`:

```elixir
{:ecto_sql, "~> 3.12"},
{:postgrex, "~> 0.20"},
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

In `server/lib/tetris/application.ex`, add `Platform.Repo` to the children list before `TetrisWeb.Endpoint`:

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

In `server/config/config.exs`, add:

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

In `server/config/runtime.exs`, add inside the `if config_env() == :prod` block:

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

**Step 6: Update setup alias in mix.exs**

Update the aliases in `server/mix.exs`:

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

**Step 7: Fetch deps, create database, verify**

Run:
```bash
cd server && mix deps.get
cd server && mix ecto.create
cd server && mix test
```

Expected: All existing tests still pass. Database created.

**Step 8: Commit**

```bash
git add server/mix.exs server/mix.lock server/lib/platform/repo.ex \
  server/lib/tetris/application.ex server/config/ server/test/test_helper.exs
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

Edit the generated migration file:

```elixir
defmodule Platform.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :firebase_uid, :text, null: false
      add :email, :text
      add :display_name, :text, null: false
      add :avatar_url, :text
      add :provider, :text
      add :is_anonymous, :boolean, default: false
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:firebase_uid])
    create index(:users, [:display_name])
  end
end
```

**Step 3: Write the User Ecto schema**

Create `server/lib/platform/accounts/user.ex`:

```elixir
defmodule Platform.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :firebase_uid, :string
    field :email, :string
    field :display_name, :string
    field :avatar_url, :string
    field :provider, :string
    field :is_anonymous, :boolean, default: false
    field :settings, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:firebase_uid, :email, :display_name, :avatar_url, :provider, :is_anonymous, :settings])
    |> validate_required([:firebase_uid, :display_name])
    |> unique_constraint(:firebase_uid)
  end
end
```

**Step 4: Write the Accounts context**

Create `server/lib/platform/accounts.ex`:

```elixir
defmodule Platform.Accounts do
  import Ecto.Query
  alias Platform.Repo
  alias Platform.Accounts.User

  def get_user_by_firebase_uid(firebase_uid) do
    Repo.get_by(User, firebase_uid: firebase_uid)
  end

  def find_or_create_user(attrs) do
    case get_user_by_firebase_uid(attrs.firebase_uid) do
      nil -> create_user(attrs)
      user -> {:ok, user}
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

  def upgrade_anonymous_user(%User{is_anonymous: true} = anon_user, attrs) do
    full_attrs = Map.merge(attrs, %{is_anonymous: false})

    case get_user_by_firebase_uid(attrs.firebase_uid) do
      nil ->
        update_user(anon_user, full_attrs)

      existing ->
        Repo.delete(anon_user)
        {:ok, existing}
    end
  end

  def upgrade_anonymous_user(%User{is_anonymous: false} = user, _attrs), do: {:ok, user}

  def search_users_by_name(query_string, limit \\ 20) do
    pattern = "%#{query_string}%"

    User
    |> where([u], ilike(u.display_name, ^pattern))
    |> where([u], u.is_anonymous == false)
    |> limit(^limit)
    |> Repo.all()
  end
end
```

**Step 5: Write the failing tests**

Create `server/test/platform/accounts_test.exs`:

```elixir
defmodule Platform.AccountsTest do
  use ExUnit.Case, async: true

  alias Platform.Accounts
  alias Platform.Accounts.User

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Platform.Repo)
  end

  describe "create_user/1" do
    test "creates a user with valid attrs" do
      attrs = %{firebase_uid: "firebase_123", display_name: "TestUser", provider: "google"}
      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.firebase_uid == "firebase_123"
      assert user.display_name == "TestUser"
      assert user.is_anonymous == false
    end

    test "fails without required fields" do
      assert {:error, changeset} = Accounts.create_user(%{})
      assert %{firebase_uid: ["can't be blank"]} = errors_on(changeset)
    end

    test "fails on duplicate firebase_uid" do
      attrs = %{firebase_uid: "dup_uid", display_name: "User1"}
      assert {:ok, _} = Accounts.create_user(attrs)
      assert {:error, changeset} = Accounts.create_user(%{attrs | display_name: "User2"})
      assert %{firebase_uid: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "find_or_create_user/1" do
    test "creates new user when not found" do
      attrs = %{firebase_uid: "new_uid", display_name: "NewUser"}
      assert {:ok, %User{}} = Accounts.find_or_create_user(attrs)
    end

    test "returns existing user when found" do
      attrs = %{firebase_uid: "existing_uid", display_name: "Existing"}
      {:ok, original} = Accounts.create_user(attrs)
      {:ok, found} = Accounts.find_or_create_user(attrs)
      assert found.id == original.id
    end
  end

  describe "search_users_by_name/2" do
    test "finds users by partial name match" do
      Accounts.create_user(%{firebase_uid: "u1", display_name: "AliceSmith"})
      Accounts.create_user(%{firebase_uid: "u2", display_name: "BobAlice"})
      Accounts.create_user(%{firebase_uid: "u3", display_name: "Charlie"})

      results = Accounts.search_users_by_name("Alice")
      assert length(results) == 2
    end

    test "excludes anonymous users" do
      Accounts.create_user(%{firebase_uid: "u1", display_name: "Alice", is_anonymous: true})
      assert Accounts.search_users_by_name("Alice") == []
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

**Step 6: Run migration and tests**

Run:
```bash
cd server && mix ecto.migrate
cd server && mix test test/platform/accounts_test.exs -v
cd server && mix test
```

Expected: All tests pass.

**Step 7: Commit**

```bash
git add server/priv/repo/migrations/ server/lib/platform/accounts/ \
  server/lib/platform/accounts.ex server/test/platform/
git commit -m "feat: add users schema and accounts context"
```

---

## Task 3: Firebase Token Verification

**Files:**
- Modify: `server/mix.exs` (add `jose` dependency)
- Create: `server/lib/platform/auth/firebase_token.ex`
- Create: `server/lib/platform/auth/token_cache.ex`
- Create: `server/test/platform/auth/firebase_token_test.exs`
- Modify: `server/config/config.exs`
- Modify: `server/config/test.exs`
- Modify: `server/lib/tetris/application.ex`

**Step 1: Add JOSE dependency**

Add to deps in `server/mix.exs`:

```elixir
{:jose, "~> 1.11"},
```

Run: `cd server && mix deps.get`

**Step 2: Add Firebase config**

In `server/config/config.exs`, add:

```elixir
config :tetris, Platform.Auth,
  firebase_project_id: System.get_env("FIREBASE_PROJECT_ID") || "tetris-battle-dev"
```

In `server/config/test.exs`, add:

```elixir
config :tetris, Platform.Auth,
  firebase_project_id: "test-project"
```

**Step 3: Write the TokenCache GenServer**

Create `server/lib/platform/auth/token_cache.ex`:

```elixir
defmodule Platform.Auth.TokenCache do
  use GenServer

  @google_certs_url "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
  @default_refresh_interval :timer.hours(6)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_keys do
    GenServer.call(__MODULE__, :get_keys)
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  def put_keys(keys) do
    GenServer.call(__MODULE__, {:put_keys, keys})
  end

  @impl true
  def init(opts) do
    state = %{keys: %{}, fetcher: Keyword.get(opts, :fetcher, &fetch_google_certs/0)}
    {:ok, state, {:continue, :initial_fetch}}
  end

  @impl true
  def handle_continue(:initial_fetch, state) do
    keys = state.fetcher.()
    schedule_refresh()
    {:noreply, %{state | keys: keys}}
  end

  @impl true
  def handle_call(:get_keys, _from, state) do
    {:reply, state.keys, state}
  end

  @impl true
  def handle_call({:put_keys, keys}, _from, state) do
    {:reply, :ok, %{state | keys: keys}}
  end

  @impl true
  def handle_cast(:refresh, state) do
    keys = state.fetcher.()
    schedule_refresh()
    {:noreply, %{state | keys: keys}}
  end

  @impl true
  def handle_info(:refresh, state) do
    keys = state.fetcher.()
    schedule_refresh()
    {:noreply, %{state | keys: keys}}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @default_refresh_interval)
  end

  defp fetch_google_certs do
    case :httpc.request(:get, {~c"#{@google_certs_url}", []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        body
        |> Jason.decode!()
        |> Enum.into(%{}, fn {kid, pem} ->
          jwk = JOSE.JWK.from_pem(pem)
          {kid, jwk}
        end)

      _ ->
        %{}
    end
  end
end
```

**Step 4: Write the FirebaseToken verifier**

Create `server/lib/platform/auth/firebase_token.ex`:

```elixir
defmodule Platform.Auth.FirebaseToken do
  alias Platform.Auth.TokenCache

  @firebase_issuer_prefix "https://securetoken.google.com/"

  def verify(token) when is_binary(token) do
    project_id = Application.get_env(:tetris, Platform.Auth)[:firebase_project_id]
    expected_issuer = @firebase_issuer_prefix <> project_id

    with {:ok, header} <- peek_header(token),
         {:ok, jwk} <- get_signing_key(header),
         {:ok, claims} <- verify_signature(token, jwk),
         :ok <- validate_claims(claims, project_id, expected_issuer) do
      {:ok, claims}
    end
  end

  def verify(_), do: {:error, :invalid_token}

  defp peek_header(token) do
    case String.split(token, ".") do
      [header_b64 | _] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, json} -> {:ok, Jason.decode!(json)}
          _ -> {:error, :invalid_header}
        end

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp get_signing_key(%{"kid" => kid}) do
    keys = TokenCache.get_keys()

    case Map.get(keys, kid) do
      nil ->
        TokenCache.refresh()
        keys = TokenCache.get_keys()

        case Map.get(keys, kid) do
          nil -> {:error, :unknown_key_id}
          jwk -> {:ok, jwk}
        end

      jwk ->
        {:ok, jwk}
    end
  end

  defp get_signing_key(_), do: {:error, :missing_kid}

  defp verify_signature(token, jwk) do
    case JOSE.JWT.verify(jwk, token) do
      {true, %JOSE.JWT{fields: claims}, _} -> {:ok, claims}
      _ -> {:error, :invalid_signature}
    end
  end

  defp validate_claims(claims, project_id, expected_issuer) do
    now = System.system_time(:second)

    cond do
      Map.get(claims, "exp", 0) <= now -> {:error, :token_expired}
      Map.get(claims, "iat", now + 1) > now -> {:error, :token_not_yet_valid}
      Map.get(claims, "iss") != expected_issuer -> {:error, :invalid_issuer}
      Map.get(claims, "aud") != project_id -> {:error, :invalid_audience}
      Map.get(claims, "sub", "") == "" -> {:error, :missing_subject}
      true -> :ok
    end
  end
end
```

**Step 5: Write tests with a test RSA key**

Create `server/test/platform/auth/firebase_token_test.exs`:

```elixir
defmodule Platform.Auth.FirebaseTokenTest do
  use ExUnit.Case, async: false

  alias Platform.Auth.FirebaseToken
  alias Platform.Auth.TokenCache

  @test_kid "test-key-1"

  setup do
    rsa_key = JOSE.JWK.generate_key({:rsa, 2048})
    TokenCache.put_keys(%{@test_kid => rsa_key})
    %{rsa_key: rsa_key}
  end

  defp make_token(rsa_key, claims_override \\ %{}) do
    now = System.system_time(:second)
    project_id = "test-project"

    claims =
      Map.merge(
        %{
          "sub" => "firebase-uid-123",
          "email" => "test@example.com",
          "iss" => "https://securetoken.google.com/#{project_id}",
          "aud" => project_id,
          "iat" => now - 10,
          "exp" => now + 3600
        },
        claims_override
      )

    header = %{"kid" => @test_kid, "alg" => "RS256"}
    jwt = JOSE.JWT.from_map(claims)
    jws = JOSE.JWS.from_map(header)
    {_, token} = JOSE.JWT.sign(rsa_key, jws, jwt) |> JOSE.JWS.compact()
    token
  end

  describe "verify/1" do
    test "accepts a valid token", %{rsa_key: rsa_key} do
      token = make_token(rsa_key)
      assert {:ok, claims} = FirebaseToken.verify(token)
      assert claims["sub"] == "firebase-uid-123"
      assert claims["email"] == "test@example.com"
    end

    test "rejects expired token", %{rsa_key: rsa_key} do
      token = make_token(rsa_key, %{"exp" => System.system_time(:second) - 10})
      assert {:error, :token_expired} = FirebaseToken.verify(token)
    end

    test "rejects wrong issuer", %{rsa_key: rsa_key} do
      token = make_token(rsa_key, %{"iss" => "https://securetoken.google.com/wrong-project"})
      assert {:error, :invalid_issuer} = FirebaseToken.verify(token)
    end

    test "rejects wrong audience", %{rsa_key: rsa_key} do
      token = make_token(rsa_key, %{"aud" => "wrong-project"})
      assert {:error, :invalid_audience} = FirebaseToken.verify(token)
    end

    test "rejects token with missing subject", %{rsa_key: rsa_key} do
      token = make_token(rsa_key, %{"sub" => ""})
      assert {:error, :missing_subject} = FirebaseToken.verify(token)
    end

    test "rejects token signed with unknown key" do
      other_key = JOSE.JWK.generate_key({:rsa, 2048})
      token = make_token(other_key)
      assert {:error, _} = FirebaseToken.verify(token)
    end

    test "rejects non-string input" do
      assert {:error, :invalid_token} = FirebaseToken.verify(nil)
      assert {:error, :invalid_token} = FirebaseToken.verify(123)
    end
  end
end
```

**Step 6: Add TokenCache to supervision tree**

In `server/lib/tetris/application.ex`, add `Platform.Auth.TokenCache` after `Platform.Repo`:

```elixir
Platform.Auth.TokenCache,
```

Also add `:inets` to extra_applications in `server/mix.exs`:

```elixir
extra_applications: [:logger, :runtime_tools, :crypto, :inets],
```

**Step 7: Run tests**

Run:
```bash
cd server && mix deps.get && mix test test/platform/auth/ -v
cd server && mix test
```

Expected: All tests pass.

**Step 8: Commit**

```bash
git add server/mix.exs server/mix.lock server/lib/platform/auth/ \
  server/lib/tetris/application.ex server/config/ \
  server/test/platform/auth/
git commit -m "feat: add Firebase token verification module"
```

---

## Task 4: Socket Auth Integration

**Files:**
- Modify: `server/lib/tetris_web/channels/user_socket.ex`

**Step 1: Modify UserSocket to verify Firebase tokens**

Replace `server/lib/tetris_web/channels/user_socket.ex`:

```elixir
defmodule TetrisWeb.UserSocket do
  use Phoenix.Socket

  channel("lobby:*", TetrisWeb.LobbyChannel)
  channel("game:*", TetrisWeb.GameChannel)
  channel("social:*", PlatformWeb.SocialChannel)

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Platform.Auth.FirebaseToken.verify(token) do
      {:ok, claims} ->
        firebase_uid = claims["sub"]
        display_name = claims["name"] || claims["email"] || "Player"
        email = claims["email"]
        provider = claims["firebase"]
                   |> case do
                     %{"sign_in_provider" => p} -> p
                     _ -> "unknown"
                   end
        avatar_url = claims["picture"]
        is_anonymous = provider == "anonymous"

        {:ok, user} =
          Platform.Accounts.find_or_create_user(%{
            firebase_uid: firebase_uid,
            display_name: display_name,
            email: email,
            provider: provider,
            avatar_url: avatar_url,
            is_anonymous: is_anonymous
          })

        socket =
          socket
          |> assign(:user_id, user.id)
          |> assign(:player_id, user.id)
          |> assign(:nickname, user.display_name)
          |> assign(:firebase_uid, firebase_uid)

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  # Legacy: allow nickname-only connection for backwards compat during migration
  def connect(%{"nickname" => nickname}, socket, _connect_info) do
    player_id = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    socket =
      socket
      |> assign(:player_id, player_id)
      |> assign(:nickname, nickname)
      |> assign(:user_id, nil)

    {:ok, socket}
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.player_id}"
end
```

**Step 2: Verify existing tests still pass**

Run:
```bash
cd server && mix test
```

Expected: All existing channel tests pass via the legacy nickname path.

**Step 3: Commit**

```bash
git add server/lib/tetris_web/channels/user_socket.ex
git commit -m "feat: add Firebase token auth to UserSocket with legacy fallback"
```

---

## Task 5: Friendships Schema and Social Context

**Files:**
- Create: `server/priv/repo/migrations/*_create_friendships.exs`
- Create: `server/lib/platform/social/friendship.ex`
- Create: `server/lib/platform/social.ex`
- Create: `server/test/platform/social_test.exs`

**Step 1: Generate and write migration**

Run: `cd server && mix ecto.gen.migration create_friendships`

Edit the generated file:

```elixir
defmodule Platform.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :friend_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :text, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:friendships, [:user_id, :friend_id])
    create index(:friendships, [:friend_id])
  end
end
```

**Step 2: Write Friendship schema**

Create `server/lib/platform/social/friendship.ex`:

```elixir
defmodule Platform.Social.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  alias Platform.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "friendships" do
    belongs_to :user, User
    belongs_to :friend, User

    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:user_id, :friend_id, :status])
    |> validate_required([:user_id, :friend_id, :status])
    |> validate_inclusion(:status, ["pending", "accepted", "blocked"])
    |> unique_constraint([:user_id, :friend_id])
    |> validate_not_self()
  end

  defp validate_not_self(changeset) do
    user_id = get_field(changeset, :user_id)
    friend_id = get_field(changeset, :friend_id)

    if user_id && friend_id && user_id == friend_id do
      add_error(changeset, :friend_id, "cannot friend yourself")
    else
      changeset
    end
  end
end
```

**Step 3: Write Social context**

Create `server/lib/platform/social.ex`:

```elixir
defmodule Platform.Social do
  import Ecto.Query
  alias Platform.Repo
  alias Platform.Social.Friendship

  def send_friend_request(user_id, friend_id) do
    %Friendship{}
    |> Friendship.changeset(%{user_id: user_id, friend_id: friend_id, status: "pending"})
    |> Repo.insert()
  end

  def accept_friend_request(user_id, friend_id) do
    case get_friendship(friend_id, user_id) do
      %Friendship{status: "pending"} = friendship ->
        Repo.transaction(fn ->
          {:ok, updated} =
            friendship
            |> Friendship.changeset(%{status: "accepted"})
            |> Repo.update()

          {:ok, _reverse} =
            %Friendship{}
            |> Friendship.changeset(%{user_id: user_id, friend_id: friend_id, status: "accepted"})
            |> Repo.insert()

          updated
        end)

      nil ->
        {:error, :not_found}

      %Friendship{} ->
        {:error, :not_pending}
    end
  end

  def decline_friend_request(user_id, friend_id) do
    case get_friendship(friend_id, user_id) do
      %Friendship{status: "pending"} = friendship ->
        Repo.delete(friendship)

      nil ->
        {:error, :not_found}

      _ ->
        {:error, :not_pending}
    end
  end

  def block_user(user_id, friend_id) do
    Repo.transaction(fn ->
      from(f in Friendship,
        where:
          (f.user_id == ^user_id and f.friend_id == ^friend_id) or
            (f.user_id == ^friend_id and f.friend_id == ^user_id)
      )
      |> Repo.delete_all()

      {:ok, _} =
        %Friendship{}
        |> Friendship.changeset(%{user_id: user_id, friend_id: friend_id, status: "blocked"})
        |> Repo.insert()
    end)
  end

  def remove_friend(user_id, friend_id) do
    from(f in Friendship,
      where:
        (f.user_id == ^user_id and f.friend_id == ^friend_id) or
          (f.user_id == ^friend_id and f.friend_id == ^user_id)
    )
    |> Repo.delete_all()

    :ok
  end

  def list_friends(user_id) do
    from(f in Friendship,
      where: f.user_id == ^user_id and f.status == "accepted",
      join: u in assoc(f, :friend),
      select: u
    )
    |> Repo.all()
  end

  def list_pending_requests(user_id) do
    from(f in Friendship,
      where: f.friend_id == ^user_id and f.status == "pending",
      join: u in assoc(f, :user),
      select: u
    )
    |> Repo.all()
  end

  def get_friendship(user_id, friend_id) do
    Repo.get_by(Friendship, user_id: user_id, friend_id: friend_id)
  end
end
```

**Step 4: Write tests**

Create `server/test/platform/social_test.exs`:

```elixir
defmodule Platform.SocialTest do
  use ExUnit.Case, async: true

  alias Platform.Accounts
  alias Platform.Social

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Platform.Repo)

    {:ok, alice} = Accounts.create_user(%{firebase_uid: "alice_uid", display_name: "Alice"})
    {:ok, bob} = Accounts.create_user(%{firebase_uid: "bob_uid", display_name: "Bob"})
    {:ok, charlie} = Accounts.create_user(%{firebase_uid: "charlie_uid", display_name: "Charlie"})

    %{alice: alice, bob: bob, charlie: charlie}
  end

  describe "send_friend_request/2" do
    test "creates pending friendship", %{alice: alice, bob: bob} do
      assert {:ok, friendship} = Social.send_friend_request(alice.id, bob.id)
      assert friendship.status == "pending"
    end

    test "cannot friend yourself", %{alice: alice} do
      assert {:error, changeset} = Social.send_friend_request(alice.id, alice.id)
      assert %{friend_id: ["cannot friend yourself"]} = errors_on(changeset)
    end

    test "cannot send duplicate request", %{alice: alice, bob: bob} do
      assert {:ok, _} = Social.send_friend_request(alice.id, bob.id)
      assert {:error, _} = Social.send_friend_request(alice.id, bob.id)
    end
  end

  describe "accept_friend_request/2" do
    test "accepts pending request and creates reverse", %{alice: alice, bob: bob} do
      {:ok, _} = Social.send_friend_request(alice.id, bob.id)
      assert {:ok, _} = Social.accept_friend_request(bob.id, alice.id)

      assert [friend] = Social.list_friends(alice.id)
      assert friend.id == bob.id

      assert [friend] = Social.list_friends(bob.id)
      assert friend.id == alice.id
    end

    test "returns error for nonexistent request", %{alice: alice, bob: bob} do
      assert {:error, :not_found} = Social.accept_friend_request(bob.id, alice.id)
    end
  end

  describe "list_pending_requests/1" do
    test "lists incoming requests", %{alice: alice, bob: bob, charlie: charlie} do
      Social.send_friend_request(alice.id, bob.id)
      Social.send_friend_request(charlie.id, bob.id)

      pending = Social.list_pending_requests(bob.id)
      assert length(pending) == 2
    end
  end

  describe "remove_friend/2" do
    test "removes friendship in both directions", %{alice: alice, bob: bob} do
      {:ok, _} = Social.send_friend_request(alice.id, bob.id)
      {:ok, _} = Social.accept_friend_request(bob.id, alice.id)

      :ok = Social.remove_friend(alice.id, bob.id)
      assert Social.list_friends(alice.id) == []
      assert Social.list_friends(bob.id) == []
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

**Step 5: Run migration and tests**

```bash
cd server && mix ecto.migrate
cd server && mix test test/platform/social_test.exs -v
cd server && mix test
```

**Step 6: Commit**

```bash
git add server/priv/repo/migrations/ server/lib/platform/social/ \
  server/lib/platform/social.ex server/test/platform/social_test.exs
git commit -m "feat: add friendships schema and social context"
```

---

## Task 6: Social Channel with Presence

**Files:**
- Create: `server/lib/platform_web/presence.ex`
- Create: `server/lib/platform_web/channels/social_channel.ex`
- Create: `server/test/platform_web/channels/social_channel_test.exs`
- Modify: `server/lib/tetris/application.ex`

**Step 1: Create Presence module**

Create `server/lib/platform_web/presence.ex`:

```elixir
defmodule PlatformWeb.Presence do
  use Phoenix.Presence,
    otp_app: :tetris,
    pubsub_server: Tetris.PubSub
end
```

Add to supervision tree in `server/lib/tetris/application.ex` (after `Platform.Auth.TokenCache`):

```elixir
PlatformWeb.Presence,
```

**Step 2: Create SocialChannel**

Create `server/lib/platform_web/channels/social_channel.ex`:

```elixir
defmodule PlatformWeb.SocialChannel do
  use Phoenix.Channel

  alias PlatformWeb.Presence
  alias Platform.Social
  alias Platform.Accounts

  @impl true
  def join("social:" <> user_id, _params, socket) do
    if socket.assigns[:user_id] == user_id do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id

    Presence.track(socket, user_id, %{
      status: "online",
      nickname: socket.assigns.nickname
    })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("send_friend_request", %{"friend_id" => friend_id}, socket) do
    user_id = socket.assigns.user_id

    case Social.send_friend_request(user_id, friend_id) do
      {:ok, _friendship} ->
        TetrisWeb.Endpoint.broadcast("social:#{friend_id}", "friend_request", %{
          from_user_id: user_id,
          from_nickname: socket.assigns.nickname
        })

        {:reply, :ok, socket}

      {:error, changeset} ->
        {:reply, {:error, %{reason: format_error(changeset)}}, socket}
    end
  end

  def handle_in("accept_friend_request", %{"from_user_id" => from_user_id}, socket) do
    user_id = socket.assigns.user_id

    case Social.accept_friend_request(user_id, from_user_id) do
      {:ok, _} ->
        TetrisWeb.Endpoint.broadcast("social:#{from_user_id}", "friend_request_accepted", %{
          user_id: user_id,
          nickname: socket.assigns.nickname
        })

        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("decline_friend_request", %{"from_user_id" => from_user_id}, socket) do
    user_id = socket.assigns.user_id

    case Social.decline_friend_request(user_id, from_user_id) do
      {:ok, _} -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("remove_friend", %{"friend_id" => friend_id}, socket) do
    :ok = Social.remove_friend(socket.assigns.user_id, friend_id)
    {:reply, :ok, socket}
  end

  def handle_in("block_user", %{"user_id" => target_id}, socket) do
    case Social.block_user(socket.assigns.user_id, target_id) do
      {:ok, _} -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("list_friends", _params, socket) do
    friends = Social.list_friends(socket.assigns.user_id)

    friends_data =
      Enum.map(friends, fn f ->
        %{id: f.id, display_name: f.display_name, avatar_url: f.avatar_url}
      end)

    {:reply, {:ok, %{friends: friends_data}}, socket}
  end

  def handle_in("list_pending_requests", _params, socket) do
    pending = Social.list_pending_requests(socket.assigns.user_id)

    pending_data =
      Enum.map(pending, fn u ->
        %{id: u.id, display_name: u.display_name, avatar_url: u.avatar_url}
      end)

    {:reply, {:ok, %{pending: pending_data}}, socket}
  end

  def handle_in("search_users", %{"query" => query}, socket) do
    users = Accounts.search_users_by_name(query)

    users_data =
      Enum.map(users, fn u ->
        %{id: u.id, display_name: u.display_name, avatar_url: u.avatar_url}
      end)

    {:reply, {:ok, %{users: users_data}}, socket}
  end

  def handle_in("send_game_invite", %{"friend_id" => friend_id, "room_id" => room_id}, socket) do
    TetrisWeb.Endpoint.broadcast("social:#{friend_id}", "game_invite", %{
      from_user_id: socket.assigns.user_id,
      from_nickname: socket.assigns.nickname,
      room_id: room_id
    })

    {:reply, :ok, socket}
  end

  def handle_in("update_status", %{"status" => status}, socket) do
    Presence.update(socket, socket.assigns.user_id, fn meta ->
      Map.put(meta, :status, status)
    end)

    {:noreply, socket}
  end

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_error(other), do: to_string(other)
end
```

**Step 3: Write tests**

Create `server/test/platform_web/channels/social_channel_test.exs`:

```elixir
defmodule PlatformWeb.SocialChannelTest do
  use ExUnit.Case, async: true

  alias Platform.Accounts

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Platform.Repo)

    {:ok, alice} = Accounts.create_user(%{firebase_uid: "alice_sc", display_name: "Alice"})
    {:ok, bob} = Accounts.create_user(%{firebase_uid: "bob_sc", display_name: "Bob"})

    %{alice: alice, bob: bob}
  end

  test "friend request flow via Social context", %{alice: alice, bob: bob} do
    {:ok, _} = Platform.Social.send_friend_request(alice.id, bob.id)

    pending = Platform.Social.list_pending_requests(bob.id)
    assert length(pending) == 1
    assert hd(pending).id == alice.id

    {:ok, _} = Platform.Social.accept_friend_request(bob.id, alice.id)

    assert [f] = Platform.Social.list_friends(alice.id)
    assert f.id == bob.id
    assert [f] = Platform.Social.list_friends(bob.id)
    assert f.id == alice.id
  end
end
```

**Step 4: Run tests**

```bash
cd server && mix test test/platform_web/ -v
cd server && mix test
```

**Step 5: Commit**

```bash
git add server/lib/platform_web/ server/lib/tetris/application.ex \
  server/test/platform_web/
git commit -m "feat: add social channel with presence and friend management"
```

---

## Task 7: Client — Firebase Auth Setup

**Files:**
- Modify: `client/package.json` (add firebase dependency)
- Create: `client/src/platform/auth/firebase.ts`
- Create: `client/src/platform/auth/FirebaseProvider.tsx`
- Create: `client/src/platform/auth/useAuth.ts`
- Create: `client/src/platform/auth/LoginScreen.tsx`

**Step 1: Install Firebase SDK**

```bash
cd client && npm install firebase
```

**Step 2: Create Firebase initialization**

Create `client/src/platform/auth/firebase.ts`:

```typescript
import { initializeApp } from "firebase/app";
import {
  getAuth,
  GoogleAuthProvider,
  GithubAuthProvider,
  OAuthProvider,
  signInAnonymously,
  signInWithPopup,
  linkWithPopup,
  type Auth,
  type User,
} from "firebase/auth";

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);

const googleProvider = new GoogleAuthProvider();
const githubProvider = new GithubAuthProvider();
const discordProvider = new OAuthProvider("discord.com");

export {
  auth,
  googleProvider,
  githubProvider,
  discordProvider,
  signInAnonymously,
  signInWithPopup,
  linkWithPopup,
};
export type { Auth, User };
```

**Step 3: Create FirebaseProvider context**

Create `client/src/platform/auth/FirebaseProvider.tsx`:

```tsx
import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { onAuthStateChanged } from "firebase/auth";
import { auth, type User } from "./firebase";

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  getIdToken: () => Promise<string | null>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function FirebaseProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (firebaseUser) => {
      setUser(firebaseUser);
      setLoading(false);
    });
    return unsubscribe;
  }, []);

  const getIdToken = async (): Promise<string | null> => {
    if (!user) return null;
    return user.getIdToken();
  };

  return (
    <AuthContext.Provider value={{ user, loading, getIdToken }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useFirebaseAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useFirebaseAuth must be used within FirebaseProvider");
  return ctx;
}
```

**Step 4: Create useAuth hook**

Create `client/src/platform/auth/useAuth.ts`:

```typescript
import {
  auth,
  googleProvider,
  githubProvider,
  discordProvider,
  signInAnonymously,
  signInWithPopup,
  linkWithPopup,
} from "./firebase";
import { signOut } from "firebase/auth";
import { useFirebaseAuth } from "./FirebaseProvider";

export function useAuth() {
  const { user, loading, getIdToken } = useFirebaseAuth();

  const signInWithGoogle = () => signInWithPopup(auth, googleProvider);
  const signInWithGithub = () => signInWithPopup(auth, githubProvider);
  const signInWithDiscord = () => signInWithPopup(auth, discordProvider);
  const signInAsGuest = () => signInAnonymously(auth);

  const upgradeAnonymous = async (provider: "google" | "github" | "discord") => {
    if (!user || !user.isAnonymous) return;
    const p =
      provider === "google"
        ? googleProvider
        : provider === "github"
          ? githubProvider
          : discordProvider;
    return linkWithPopup(user, p);
  };

  const logout = () => signOut(auth);

  return {
    user,
    loading,
    isAnonymous: user?.isAnonymous ?? false,
    isAuthenticated: !!user,
    displayName: user?.displayName || user?.email || "Guest",
    avatarUrl: user?.photoURL || null,
    getIdToken,
    signInWithGoogle,
    signInWithGithub,
    signInWithDiscord,
    signInAsGuest,
    upgradeAnonymous,
    logout,
  };
}
```

**Step 5: Create LoginScreen component**

Create `client/src/platform/auth/LoginScreen.tsx`:

```tsx
import { useAuth } from "./useAuth";

export default function LoginScreen() {
  const {
    signInWithGoogle,
    signInWithGithub,
    signInWithDiscord,
    signInAsGuest,
  } = useAuth();

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900">
      <div className="w-full max-w-sm space-y-6 rounded-xl bg-gray-800 p-8 text-center">
        <h1 className="text-3xl font-bold text-white">Tetris Battle</h1>
        <p className="text-gray-400">Sign in to play</p>

        <div className="space-y-3">
          <button
            onClick={signInWithGoogle}
            className="w-full rounded-lg bg-white px-4 py-3 font-medium text-gray-800 hover:bg-gray-100"
          >
            Continue with Google
          </button>
          <button
            onClick={signInWithGithub}
            className="w-full rounded-lg bg-gray-700 px-4 py-3 font-medium text-white hover:bg-gray-600"
          >
            Continue with GitHub
          </button>
          <button
            onClick={signInWithDiscord}
            className="w-full rounded-lg bg-indigo-600 px-4 py-3 font-medium text-white hover:bg-indigo-500"
          >
            Continue with Discord
          </button>
        </div>

        <div className="relative">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-gray-600" />
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="bg-gray-800 px-2 text-gray-400">or</span>
          </div>
        </div>

        <button
          onClick={signInAsGuest}
          className="w-full rounded-lg border border-gray-600 px-4 py-3 font-medium text-gray-300 hover:bg-gray-700"
        >
          Play as Guest
        </button>
        <p className="text-xs text-gray-500">
          Guest accounts can be upgraded to a full account later
        </p>
      </div>
    </div>
  );
}
```

**Step 6: Commit**

```bash
git add client/package.json client/package-lock.json client/src/platform/
git commit -m "feat: add Firebase auth setup, hooks, and login screen on client"
```

---

## Task 8: Client — App Integration (Socket Auth + Routes)

**Files:**
- Modify: `client/src/App.tsx`
- Modify: `client/src/hooks/useSocket.ts`
- Modify: `client/src/context/GameContext.tsx`
- Modify: `client/src/components/MainMenu.tsx`

**Step 1: Modify useSocket to pass Firebase token**

In `client/src/hooks/useSocket.ts`, change the hook to accept a token getter:

```typescript
export function useSocket(
  nickname: string | null,
  getIdToken?: () => Promise<string | null>
): UseSocketResult {
```

Update the socket initialization to use the token when available. If `getIdToken` is provided, call it and pass as `params.token`. Otherwise fall back to `params.nickname`.

**Step 2: Modify GameContext**

In `client/src/context/GameContext.tsx`, integrate `useFirebaseAuth` to automatically derive nickname from Firebase user and pass `getIdToken` to `useSocket`.

**Step 3: Modify App.tsx**

Wrap with `FirebaseProvider`. Show `LoginScreen` when not authenticated. Remove or make `NicknameForm` optional (nickname now comes from Firebase profile, with ability to customize).

**Step 4: Modify MainMenu**

Show user avatar/name, logout button, links to profile/friends.

**Step 5: Verify client builds**

```bash
cd client && npm run build
```

**Step 6: Commit**

```bash
git add client/src/
git commit -m "feat: integrate Firebase auth into app routing and socket connection"
```

---

## Task 9: Client — Friends UI

**Files:**
- Create: `client/src/platform/social/useSocial.ts`
- Create: `client/src/platform/social/FriendsList.tsx`
- Create: `client/src/platform/social/FriendRequest.tsx`
- Create: `client/src/platform/social/GameInvite.tsx`
- Modify: `client/src/components/Lobby.tsx`

**Step 1: Create useSocial hook**

Uses `useChannel` to join `social:{userId}`. Handles:
- Friend list via `list_friends` message
- Pending requests via `list_pending_requests`
- Presence tracking via `presence_state` and `presence_diff`
- Game invites via `game_invite` listener
- Actions: `send_friend_request`, `accept_friend_request`, `decline_friend_request`, `send_game_invite`, `search_users`

**Step 2: Create FriendsList component**

Sidebar/overlay showing online friends with status indicators, invite button, pending requests section, user search.

**Step 3: Create FriendRequest and GameInvite components**

Toast/notification components for incoming friend requests and game invites.

**Step 4: Modify Lobby**

Add friend online indicators and invite buttons.

**Step 5: Verify build**

```bash
cd client && npm run build
cd client && npx oxlint src/
```

**Step 6: Commit**

```bash
git add client/src/
git commit -m "feat: add friends list, requests, and game invite UI"
```

---

## Task 10: Verification

**Step 1: Run all server tests**

```bash
cd server && mix test
```

**Step 2: Run all client checks**

```bash
cd client && npx oxlint src/
cd client && npx prettier --check "src/**/*.{ts,tsx,js,jsx,css}"
cd client && npm run build
```

**Step 3: Manual smoke test**

1. Start PostgreSQL
2. `cd server && mix ecto.reset && mix phx.server`
3. `cd client && npm run dev`
4. Verify: login with Firebase -> lobby displays user -> create room -> friend request flow

---

## Infrastructure Prerequisites

Before starting implementation:

1. **PostgreSQL** running locally (default: localhost:5432, user/pass: postgres/postgres)
2. **Firebase project** created with Google/GitHub/Discord auth providers enabled
3. **Environment variables** for Firebase client config (`VITE_FIREBASE_*`)
4. **Server env var** `FIREBASE_PROJECT_ID` set to match Firebase project
