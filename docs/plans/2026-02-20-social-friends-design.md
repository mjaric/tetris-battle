# Social & Friends — Design Document

Date: 2026-02-20

## Summary

Add a bidirectional friends system with online status tracking and game
invites. Phoenix Presence for real-time status. Dedicated Social Channel
for friend management and notifications. All new code lives under the
`Platform.*` / `PlatformWeb.*` namespace.

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Friends model | Bidirectional pairs — A sends request, accept creates reverse row |
| 2 | Online status | Phoenix Presence (built-in, no external dependency) |
| 3 | Game invites | Push via Social Channel, client auto-joins room |
| 4 | Error convention | `{:error, changeset}` for validation, `{:error, :atom}` for business logic |
| 5 | Finding friends | Search by display name + recent opponents (when history exists) |
| 6 | Status types | `online`, `in_game:{room_id}`, `in_lobby` |

---

## Section 1: Database Schema

```sql
friendships (
  id          uuid PRIMARY KEY,
  user_id     uuid REFERENCES users NOT NULL,
  friend_id   uuid REFERENCES users NOT NULL,
  status      text NOT NULL,   -- "pending", "accepted", "blocked"
  inserted_at utc_datetime,
  updated_at  utc_datetime,

  UNIQUE(user_id, friend_id)
)
```

### Design notes

- Directional pairs: when A befriends B, two rows exist after acceptance
  (A→B `accepted` and B→A `accepted`). Query `WHERE user_id = ?` to get
  a user's full friends list.
- `status` values: `pending` (request sent, awaiting response),
  `accepted` (mutual friendship), `blocked` (one-way block).
- `validate_not_self` on the changeset prevents self-friending.

---

## Section 2: Server Module Architecture

```
lib/
├── platform/
│   ├── social/
│   │   └── friendship.ex         # Ecto schema + validate_not_self
│   └── social.ex                 # Context: send/accept/decline/block/remove
├── platform_web/
│   ├── presence.ex               # Phoenix Presence for online status
│   └── channels/
│       └── social_channel.ex     # "social:{user_id}" — all friend/invite ops
└── tetris_web/
    └── user_socket.ex            # Modified: add channel("social:*", ...)
```

### Social Context (`Platform.Social`)

Functions:

- `send_friend_request(user_id, friend_id)` — creates pending friendship
- `accept_friend_request(user_id, from_user_id)` — sets accepted, creates
  reverse row in a transaction
- `decline_friend_request(user_id, from_user_id)` — deletes the pending row
- `block_user(user_id, target_id)` — removes all rows between the pair,
  creates a blocked row
- `remove_friend(user_id, friend_id)` — deletes rows in both directions
- `list_friends(user_id)` — returns accepted friends with user data
- `list_pending_requests(user_id)` — returns incoming pending requests

### Error shape convention

- `{:error, changeset}` — validation failures (duplicate request,
  self-friend, missing fields)
- `{:error, :not_found}` — no matching friendship record
- `{:error, :not_pending}` — friendship exists but not in pending state

Transaction operations (`accept_friend_request`, `block_user`) use proper
error handling inside `Repo.transaction` — no `{:ok, _} =` pattern matching
that raises on failure. Each step returns an error tuple on failure, and the
transaction rolls back.

---

## Section 3: Social Channel

Each authenticated user joins `social:{user_id}` on connect. The channel
verifies that `socket.assigns.user_id` matches the topic's user ID.

### Incoming messages (client → server)

| Message | Params | Reply |
|---------|--------|-------|
| `send_friend_request` | `friend_id` | `:ok` or `{:error, reason}` |
| `accept_friend_request` | `from_user_id` | `:ok` or `{:error, reason}` |
| `decline_friend_request` | `from_user_id` | `:ok` or `{:error, reason}` |
| `block_user` | `user_id` | `:ok` or `{:error, reason}` |
| `remove_friend` | `friend_id` | `:ok` or `{:error, reason}` |
| `list_friends` | — | `{:ok, %{friends: [...]}}` |
| `list_pending_requests` | — | `{:ok, %{pending: [...]}}` |
| `search_users` | `query` | `{:ok, %{users: [...]}}` |
| `send_game_invite` | `friend_id`, `room_id` | `:ok` |
| `update_status` | `status` | — (noreply) |

### Outgoing pushes (server → client)

| Event | Data | Trigger |
|-------|------|---------|
| `friend_request` | `from_user_id`, `from_nickname` | Someone sends you a request |
| `friend_request_accepted` | `user_id`, `nickname` | Someone accepts your request |
| `game_invite` | `from_user_id`, `from_nickname`, `room_id` | Friend invites you |
| `presence_state` | Presence map | On join |
| `presence_diff` | Presence diff | On status change |

### Presence

Phoenix Presence tracks each user with metadata:

```elixir
%{status: "online", nickname: "Alice"}
```

Status values: `"online"`, `"in_game:{room_id}"`, `"in_lobby"`.
Clients call `update_status` when navigating between screens.

---

## Section 4: Friend Request Flow

1. User A searches for User B by display name
2. Sends request → creates `friendship` row (status: `"pending"`)
3. Server broadcasts `friend_request` to User B's social channel
4. User B sees notification, clicks accept
5. Server sets status to `"accepted"`, creates reverse row (B→A `"accepted"`)
6. Server broadcasts `friend_request_accepted` to User A's social channel
7. Both users see each other in friends list with online status via Presence

---

## Section 5: Game Invite Flow

1. User A is in a game room or lobby
2. Opens friends panel, clicks "Invite" next to an online friend
3. Server pushes `game_invite` to User B's social channel (includes `room_id`)
4. User B sees a toast notification with accept/decline
5. Accept → client auto-joins the room via the existing lobby join flow

---

## Section 6: Client Architecture

```
src/
├── platform/
│   └── social/
│       ├── useSocial.ts          # Hook: social channel, presence, actions
│       ├── FriendsList.tsx       # Panel with status indicators + invite button
│       ├── FriendRequest.tsx     # Incoming request notification
│       └── GameInvite.tsx        # Invite toast with accept/decline
├── components/
│   └── Lobby.tsx                 # Modified: friend online indicators, invite buttons
```

### useSocial hook

Uses `useChannel` to join `social:{userId}`. Provides:

- `friends` — list of friends with online status from Presence
- `pendingRequests` — incoming friend requests
- `sendFriendRequest(friendId)` — send a request
- `acceptRequest(fromUserId)` / `declineRequest(fromUserId)`
- `removeFriend(friendId)` / `blockUser(userId)`
- `searchUsers(query)` — search by display name
- `sendGameInvite(friendId, roomId)` — invite to a game
- `onGameInvite(callback)` — listener for incoming invites

---

## Section 7: Error Handling

- Friend request to self → `{:error, changeset}` with
  `friend_id: "cannot friend yourself"`
- Duplicate friend request → `{:error, changeset}` with unique constraint
  violation
- Accept nonexistent request → `{:error, :not_found}`
- Accept non-pending request → `{:error, :not_pending}`
- Channel translates error tuples into user-facing reply messages
- `search_users` sanitizes input (ILIKE escaping) before query

---

## Section 8: Testing Strategy

- **Social context:** Ecto sandbox tests for each operation (send, accept,
  decline, block, remove, list). Test transaction error handling.
- **Friendship schema:** Changeset tests for validation (self-friend,
  status values, required fields).
- **Social channel:** Channel tests for message handling, authorization
  (can't join another user's channel), and push delivery.
- **Presence:** Verify tracking and status updates.

---

## Dependencies

None new. Phoenix Presence is built-in.

---

## Depends On

Auth & Registration — needs user IDs, authenticated socket, Ecto repo.

## Followed By

Independent of History & Streaming — can be implemented in either order.

---

## Out of Scope

- Authentication (separate initiative)
- Match history and replay recording (separate initiative)
- Recent opponents list (depends on History initiative)
- Ranked matchmaking / ELO (future phase)
- Chat system (future phase)
