# Registration & Nickname — Design

**Date:** 2026-02-21
**Status:** Approved
**Depends on:** Auth & Registration (completed)

## Problem

The current auth flow has three gaps:

1. **No registration step** — OAuth users get auto-created from provider data with no chance to pick a nickname.
2. **No nickname** — `display_name` (full name from OAuth) is used publicly everywhere. Users need a unique public handle separate from their private real name.
3. **Guest upgrade path** — not defined for converting anonymous users to registered accounts with a nickname.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Registration trigger | New OAuth users AND guest upgrades | Both cases need nickname selection |
| Nickname uniqueness | Unique, DB-enforced | Required for identity in multiplayer |
| Nickname format | `^[a-zA-Z][a-zA-Z0-9_]{2,19}$` | 3-20 chars, alphanumeric + underscore, starts with letter |
| Intermediate state | JWT registration token (no DB record) | Stateless, no server-side session storage |
| Registration token TTL | 10 minutes | Short enough for security, long enough for form completion |
| Guest linking | Client sends guest JWT alongside registration token | No server-side session state |
| Name pre-fill | From OAuth provider, editable | Convenience without lock-in |
| Privacy model | `nickname` = public, `display_name` + `email` = private (owner-only) | Personal data hidden from other players |

## Schema Changes

### New migration: add `nickname` column to `users`

```sql
ALTER TABLE users ADD COLUMN nickname text;
CREATE UNIQUE INDEX users_nickname_index ON users (nickname);
ALTER TABLE users ADD CONSTRAINT nickname_format
  CHECK (nickname ~ '^[a-zA-Z][a-zA-Z0-9_]{2,19}$');
```

- Nullable: guests don't have a nickname until upgrade.
- Unique index enforces uniqueness at DB level.
- Check constraint enforces format at DB level.

### User schema fields after change

| Field | Type | Nullable | Visibility | Purpose |
|-------|------|----------|------------|---------|
| `nickname` | string | yes | Public | Unique handle shown in games, lobby, leaderboards |
| `display_name` | string | no | Private | Full name (from OAuth or user-entered) |
| `email` | string | yes | Private | From OAuth provider |
| `avatar_url` | string | yes | Private | From OAuth provider |
| `is_anonymous` | boolean | no | N/A | Guest flag |

## Auth Flows

### Case 1: New OAuth User

```
Browser -> GET /auth/google -> Google OAuth -> GET /auth/google/callback
  Server: lookup user by (provider, provider_id) -> NOT FOUND
  Server: sign registration JWT (TTL 10 min):
    { type: "registration", provider: "google", provider_id: "123",
      name: "John Smith", email: "john@example.com",
      avatar_url: "...", exp: now+600 }
  Server: redirect -> /oauth/callback#registration_token=<JWT>
Client: AuthCallback detects registration_token -> navigate to /register
Client: Registration page:
  - Full name: "John Smith" (pre-filled, editable)
  - Nickname: "" (blank, live availability check via GET /api/auth/check-nickname/:nick)
Client: POST /api/auth/register { registration_token, nickname, display_name }
  Server: verify token, validate nickname, create user, return full auth JWT
```

### Case 2: Existing OAuth User

```
Browser -> GET /auth/google -> Google OAuth -> GET /auth/google/callback
  Server: lookup user by (provider, provider_id) -> FOUND
  Server: sign normal auth JWT (unchanged)
  Server: redirect -> /oauth/callback#token=<JWT>
```

### Case 3: Guest Login

```
Client: POST /api/auth/guest
  Server: create anonymous user (nickname=nil), return auth JWT
  (unchanged from current behavior)
```

### Case 4: Guest Upgrades via OAuth

```
Guest clicks "Link Account" -> GET /auth/google -> OAuth flow
  Server: callback -> lookup by (google, uid) -> NOT FOUND
  Server: sign registration JWT (same as Case 1)
  Server: redirect -> /oauth/callback#registration_token=<JWT>
Client: has guest JWT in localStorage already
Client: shows registration form
Client: POST /api/auth/register { registration_token, nickname, display_name, guest_token }
  Server: verify registration token + guest token
  Server: upgrade anonymous user (set provider, nickname, display_name, is_anonymous=false)
  Server: return full auth JWT
```

## API Endpoints

### New: `POST /api/auth/register`

Complete user registration (create new or upgrade guest).

**Request:**
```json
{
  "registration_token": "<JWT with type:registration>",
  "nickname": "Cool_Player1",
  "display_name": "John Smith",
  "guest_token": "<optional, present when upgrading a guest>"
}
```

**Success (200):**
```json
{
  "token": "<full auth JWT>",
  "user": { "id": "...", "nickname": "Cool_Player1", "display_name": "John Smith" }
}
```

**Errors:**
- `422` — invalid nickname format, nickname taken, or missing required fields
- `401` — invalid or expired registration token
- `409` — OAuth provider+id already registered (race condition)

### New: `GET /api/auth/check-nickname/:nickname`

Check nickname availability.

**Success (200):**
```json
{ "available": true, "nickname": "Cool_Player1" }
```
```json
{ "available": false, "nickname": "Cool_Player1", "reason": "taken" }
```

Invalid format returns `available: false` with `reason: "invalid_format"`.

### Modified: `AuthController.callback`

- Existing user -> normal JWT redirect (unchanged behavior)
- New user -> registration JWT redirect to `/oauth/callback#registration_token=<JWT>`

### Unchanged endpoints

- `POST /api/auth/guest` — no changes
- `POST /api/auth/refresh` — adds `nickname` to JWT claims

## JWT Token Changes

### Registration token (new)

Short-lived (10 min), carries OAuth data, no `sub` claim:

```
{ type: "registration", provider: "google", provider_id: "123",
  name: "John Smith", email: "john@example.com",
  avatar_url: "https://...", iat: ..., exp: now+600 }
```

Signed and verified by `Token.sign_registration/1` and `Token.verify_registration/1`.

### Auth token (modified)

Add `nickname` claim alongside existing `name` claim:

```
{ sub: "<user_id>", name: "John Smith", nickname: "Cool_Player1",
  iat: ..., exp: ... }
```

Guests without a nickname: `nickname` claim is omitted or null.

## Server Module Changes

| Module | Change |
|--------|--------|
| `Platform.Accounts.User` | Add `nickname` field. Add `registration_changeset/2` with nickname format + uniqueness validation. |
| `Platform.Accounts` | Add `register_user/1`, `check_nickname_available?/1`. Modify `upgrade_anonymous_user/2` to accept nickname. |
| `Platform.Auth.Token` | Add `sign_registration/1`, `verify_registration/1`. |
| `PlatformWeb.AuthController` | Split callback (existing vs new user). Add `register/2`, `check_nickname/2`. |
| `TetrisWeb.Router` | Add routes for register and check-nickname. |
| `TetrisWeb.UserSocket` | Use `user.nickname \|\| user.display_name` for `:nickname` assign. |
| New migration | Add `nickname` column, unique index, check constraint. |

## Client Module Changes

| Module | Change |
|--------|--------|
| `AuthProvider` | Add `registrationToken`, `registrationData` state. Extract `nickname` from JWT. |
| `AuthUser` interface | Add `nickname: string \| null`. |
| `AuthCallback` | Handle `#registration_token=` -> store and navigate to `/register`. |
| `GameContext` | Use `nickname ?? displayName` for socket/game identity. |
| `MainMenu` | Show nickname. Add "Link Account" for guests. |
| `App.tsx` | Add `/register` route. |
| New: `RegisterPage.tsx` | Registration form with name, nickname, live availability check. |

## Client Registration Page

**Route:** `/register`
**Guard:** `RequireRegistration` — redirects to `/login` if no registration token present.

**Form:**
1. **Full Name** — text input, pre-filled from registration token's `name` claim, editable
2. **Nickname** — text input, blank, debounced (300ms) availability check via `GET /api/auth/check-nickname/:nick`
   - Inline validation: format rules + availability
   - Visual feedback: green check (available), red X (taken/invalid)
3. **Submit** — "Create Account" button, disabled until nickname is valid and available

**Guest upgrade:** Same form. If client has a guest JWT in localStorage and a registration token, it sends both to the register endpoint.

## What Stays Unchanged

- Guest login endpoint (`POST /api/auth/guest`)
- Token refresh (`POST /api/auth/refresh`) — just includes nickname claim now
- Game channels — already use `socket.assigns.nickname`
- All game logic modules (`Tetris.*`)
- Lobby and game room processes (`TetrisGame.*`)
- Solo mode (`useTetris` hook)
