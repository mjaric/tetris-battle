import { useState, useEffect, useCallback } from "react";
import { useNavigate } from "react-router";
import { useGameContext } from "../context/GameContext.tsx";
import type { RoomInfo } from "../types.ts";

interface NewRoom {
  name: string;
  max_players: number;
}

export default function Lobby() {
  const { lobbyChannel } = useGameContext();
  const [rooms, setRooms] = useState<RoomInfo[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [newRoom, setNewRoom] = useState<NewRoom>({
    name: "",
    max_players: 4,
  });
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const refreshRooms = useCallback(() => {
    if (!lobbyChannel) return;
    lobbyChannel
      .push("list_rooms", {})
      .receive("ok", (resp: { rooms: RoomInfo[] }) => {
        setRooms(resp.rooms);
      });
  }, [lobbyChannel]);

  useEffect(() => {
    refreshRooms();
    if (!lobbyChannel) return;

    const ref1 = lobbyChannel.on(
      "room_created",
      () => refreshRooms(),
    );
    const ref2 = lobbyChannel.on(
      "room_removed",
      () => refreshRooms(),
    );
    return () => {
      lobbyChannel.off("room_created", ref1);
      lobbyChannel.off("room_removed", ref2);
    };
  }, [lobbyChannel, refreshRooms]);

  function handleCreate() {
    if (!lobbyChannel) return;
    setError(null);
    lobbyChannel
      .push("create_room", {
        name: newRoom.name || "Unnamed Room",
        max_players: newRoom.max_players,
      })
      .receive("ok", (resp: { room_id: string }) => {
        setShowCreate(false);
        navigate(`/room/${resp.room_id}`);
      })
      .receive("error", (resp: { reason: string }) => {
        setError(resp.reason);
      });
  }

  function handleJoin(room: RoomInfo) {
    navigate(`/room/${room.room_id}`);
  }

  return (
    <div className="flex min-h-screen flex-col items-center bg-bg-primary p-10">
      <h2 className="mb-6 text-2xl font-bold">Lobby</h2>

      <div className="mb-6 flex gap-3">
        <button
          onClick={() => setShowCreate(!showCreate)}
          className="cursor-pointer rounded-lg border-none bg-accent px-6 py-2.5 text-sm font-bold text-white"
        >
          Create Room
        </button>
        <button
          onClick={() => navigate("/")}
          className="cursor-pointer rounded-lg border-none bg-border px-6 py-2.5 text-sm font-bold text-white"
        >
          Back
        </button>
      </div>

      {error && (
        <div className="mb-4 text-sm text-red">{error}</div>
      )}

      {showCreate && (
        <div className="mb-6 rounded-lg border border-border bg-bg-secondary p-5">
          <input
            placeholder="Room name"
            value={newRoom.name}
            onChange={(e) =>
              setNewRoom({ ...newRoom, name: e.target.value })
            }
            className="block w-full rounded-md border border-border bg-bg-tertiary px-3.5 py-2.5 text-sm text-white outline-none"
          />
          <select
            value={newRoom.max_players}
            onChange={(e) =>
              setNewRoom({
                ...newRoom,
                max_players: parseInt(e.target.value, 10),
              })
            }
            className="mt-2 block w-full rounded-md border border-border bg-bg-tertiary px-3.5 py-2.5 text-sm text-white outline-none"
          >
            <option value={2}>2 players</option>
            <option value={3}>3 players</option>
            <option value={4}>4 players</option>
          </select>
          <button
            onClick={handleCreate}
            className="mt-3 w-full cursor-pointer rounded-lg border-none bg-accent px-6 py-2.5 text-sm font-bold text-white"
          >
            Create
          </button>
        </div>
      )}

      <div className="w-full max-w-lg">
        {rooms.length === 0 && (
          <div className="text-center text-gray-600">
            No rooms yet
          </div>
        )}
        {rooms.map((room) => (
          <div
            key={room.room_id}
            onClick={() => handleJoin(room)}
            className="mb-2 flex cursor-pointer items-center justify-between rounded-lg border border-border bg-bg-secondary px-4 py-3"
          >
            <span className="font-bold">{room.name}</span>
            <span className="text-muted">
              {room.player_count}/{room.max_players}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
