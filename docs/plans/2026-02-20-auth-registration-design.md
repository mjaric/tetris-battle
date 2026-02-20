# Auth & Registration — Design Document

Date: 2026-02-20

## Summary

Add authentication and user accounts to the existing tetris-battle app.
Custom OAuth using Ueberauth for provider flows and JOSE for JWT
signing/verification. Server issues its own JWTs — no external auth service.
PostgreSQL via Ecto for user persistence. All new code lives under the
`Platform.*` namespace alongside existing modules.

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Auth approach | Custom: Ueberauth (OAuth) + JOSE (JWT) |
| 2 | Providers | Google, GitHub, Discord + anonymous guest |
| 3 | Token format | JWT signed with server's secret (HS256 via JOSE) |
| 4 | Token expiry | 1 hour, with refresh endpoint |
| 5 | Guest play | Server creates anon user + issues JWT, upgradeable |
| 6 | Data store | PostgreSQL via Ecto |
| 7 | Namespace | `Platform.*` modules alongside existing code |
| 8 | Solo mode | Auth optional; stats tracked if logged in |

---

## Section 1: Authentication Flow

### OAuth Login

1. Client renders login screen with provider buttons
2. User clicks provider → browser navigates to `GET /auth/{provider}`
3. Ueberauth redirects to provider's OAuth consent screen
4. Provider redirects back to `GET /auth/{provider}/callback`
5. Server `AuthController` receives Ueberauth auth struct with user info
6. Server upserts user by `(provider, provider_id)`
7. Server signs a JWT containing the user's database ID
8. Server redirects to `{client_url}/auth/callback#token={jwt}`
9. Client reads token from URL fragment, stores in memory, clears URL

### Guest Login

1. Client calls `POST /auth/guest`
2. Server creates user with `provider: "anonymous"`,
   `provider_id: <random_uuid>`, `is_anonymous: true`
3. Returns JWT in response body

### Token Refresh

- JWT expires after 1 hour
- Client calls `POST /auth/refresh` with current JWT before expiry
- Server verifies JWT, issues a new one if the user still exists
- WebSocket connections stay alive regardless (JWT only checked on `connect`)
- On socket reconnect (network drop), client refreshes token first

### Account Upgrade (Guest to Full)

1. Guest user clicks a provider sign-in button → same OAuth flow
2. Server detects existing anonymous session (JWT in cookie/header)
3. Updates the anon user record in-place: sets `provider`, `provider_id`,
   `is_anonymous: false`
4. Issues new JWT

No deletion of the anonymous record — update in-place preserves any
associated data (match history, settings).

---

## Section 2: Database Schema

```sql
users (
  id            uuid PRIMARY KEY,
  provider      text,           -- "google", "github", "discord", "anonymous"
  provider_id   text NOT NULL,  -- OAuth provider's user ID (UUID for anon)
  email         text,
  display_name  text NOT NULL,
  avatar_url    text,
  is_anonymous  boolean DEFAULT false,
  settings      jsonb DEFAULT '{}',
  inserted_at   utc_datetime,
  updated_at    utc_datetime,

  UNIQUE(provider, provider_id)
)
```

### Design notes

- `provider` + `provider_id` instead of `firebase_uid` — provider-agnostic.
  If the auth system changes later, only these columns need updating.
- `settings` as JSONB — flexible for preferences without schema migrations
  per setting.
- `is_anonymous` flag distinguishes guest accounts from full accounts.

---

## Section 3: Server Module Architecture

```
lib/
├── platform/
│   ├── auth/
│   │   └── token.ex              # JWT signing/verification (JOSE, HS256)
│   ├── accounts/
│   │   └── user.ex               # Ecto schema
│   ├── accounts.ex               # Context: upsert, update, upgrade anon, search
│   └── repo.ex                   # Ecto.Repo
├── platform_web/
│   ├── controllers/
│   │   └── auth_controller.ex    # OAuth callbacks, guest login, token refresh
│   ├── plugs/
│   │   └── auth_pipeline.ex      # Plug: extract + verify JWT from header
│   └── router.ex                 # /auth routes
└── tetris_web/
    └── user_socket.ex            # Verify JWT on connect (local crypto, no network)
```

### Key implementation details

- `Token.sign/1` and `Token.verify/1` use JOSE with HS256 and Phoenix's
  `secret_key_base`. No key management overhead, no JWKS fetching.
- `find_or_create_user/1` uses `Repo.insert` with `on_conflict` upsert on
  `(provider, provider_id)` — no TOCTOU race condition.
- `search_users_by_name/2` escapes `%` and `_` in user input before ILIKE
  interpolation. All user-provided strings used in queries must be sanitized.
- `upgrade_anonymous_user/2` updates the record in-place, never deletes.
- No `TokenCache` needed — verification is a local crypto operation with the
  server's own secret.
- No legacy nickname-only socket connect fallback. Token required.

### Integration points with existing code

1. `UserSocket.connect/3` — verify JWT, attach `user_id` and `nickname`
   to socket assigns.
2. `GameChannel.join/3` — use `socket.assigns.user_id` instead of
   nickname-only identity.
3. `LobbyChannel` — include user display names and auth status in room
   listings.

---

## Section 4: Client Architecture

```
src/
├── platform/
│   └── auth/
│       ├── AuthProvider.tsx      # Context: stores JWT, decodes user info
│       ├── useAuth.ts            # Hook: login URLs, guest login, logout, refresh
│       └── LoginScreen.tsx       # Provider buttons + guest play
├── hooks/
│   └── useSocket.ts              # Modified: pass JWT on connect
├── components/
│   ├── App.tsx                   # Wrap with AuthProvider, show login when unauthed
│   └── MainMenu.tsx              # User avatar/name, logout
```

### App flow

- `App.tsx` wraps everything in `AuthProvider`
- New screen states: `login → menu → ...` (existing flow continues after menu)
- `useSocket` modified to include JWT in socket params
- `MainMenu` shows user avatar/name, logout button
- Guest users see a "Sign in for full features" prompt but can play immediately

No external SDK. Login buttons are `<a>` links to `/auth/{provider}` —
server handles the redirect. Client bundle stays light.

---

## Section 5: Error Handling

- Invalid/expired JWT on socket connect → connection rejected, client
  redirects to login
- OAuth provider error → server redirects to client with error param
  (`/auth/callback?error=provider_denied`), client shows message
- Anonymous upgrade → update in-place, preserve associated data
- All user-provided query strings sanitized for SQL (ILIKE escaping,
  parameterized queries)

---

## Section 6: Testing Strategy

- **Token module:** Unit tests for sign/verify with valid, expired, and
  tampered tokens.
- **Accounts context:** Ecto sandbox tests for upsert, upgrade, search
  (including sanitization edge cases).
- **AuthController:** Controller tests for OAuth callback (mock Ueberauth),
  guest login, token refresh.
- **UserSocket:** Channel tests verifying token-based connect and rejection.

---

## Dependencies

### Server (new)

- `ecto_sql` + `postgrex` — PostgreSQL integration
- `jose` — JWT signing and verification
- `ueberauth` — OAuth framework
- `ueberauth_google` — Google OAuth strategy
- `ueberauth_github` — GitHub OAuth strategy
- `ueberauth_discord` — Discord OAuth strategy

### Client (new)

None. No external auth SDK.

---

## Depends On

Nothing — this is the foundation plan.

## Followed By

- `docs/plans/2026-02-20-social-friends-design.md` (Social & Friends)
- `docs/plans/2026-02-20-game-history-streaming-design.md` (History & Streaming)

---

## Out of Scope

- Friends system and social features (separate initiative)
- Match history and replay recording (separate initiative)
- Ranked matchmaking / ELO (future phase)
- Spectator mode (future phase)
- LLM commentary (future phase)
