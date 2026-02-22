import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router';
import { useGameContext } from '../context/GameContext.tsx';
import { GlassCard, Button, Input, Badge, PageTransition } from './ui/index.ts';
import type { RoomInfo } from '../types.ts';

interface NewRoom {
  name: string;
  max_players: number;
}

export default function Lobby() {
  const { lobbyChannel } = useGameContext();
  const [rooms, setRooms] = useState<RoomInfo[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [newRoom, setNewRoom] = useState<NewRoom>({
    name: '',
    max_players: 4,
  });
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const refreshRooms = useCallback(() => {
    if (!lobbyChannel) return;
    lobbyChannel.push('list_rooms', {}).receive('ok', (resp: { rooms: RoomInfo[] }) => {
      setRooms(resp.rooms);
    });
  }, [lobbyChannel]);

  useEffect(() => {
    refreshRooms();
    if (!lobbyChannel) return;

    const ref1 = lobbyChannel.on('room_created', () => refreshRooms());
    const ref2 = lobbyChannel.on('room_removed', () => refreshRooms());
    return () => {
      lobbyChannel.off('room_created', ref1);
      lobbyChannel.off('room_removed', ref2);
    };
  }, [lobbyChannel, refreshRooms]);

  function handleCreate() {
    if (!lobbyChannel) return;
    setError(null);
    lobbyChannel
      .push('create_room', {
        name: newRoom.name || 'Unnamed Room',
        max_players: newRoom.max_players,
      })
      .receive('ok', (resp: { room_id: string }) => {
        setShowCreate(false);
        navigate(`/room/${resp.room_id}`);
      })
      .receive('error', (resp: { reason: string }) => {
        setError(resp.reason);
      });
  }

  function handleJoin(room: RoomInfo) {
    navigate(`/room/${room.room_id}`);
  }

  return (
    <PageTransition className="min-h-screen p-8">
      <div className="mx-auto max-w-2xl">
        <div className="mb-6 flex items-center justify-between">
          <h2 className="font-display text-2xl font-bold text-text-primary">Lobby</h2>
          <div className="flex gap-3">
            <Button variant="primary" size="sm" onClick={() => setShowCreate(!showCreate)}>
              {showCreate ? 'Cancel' : 'Create Room'}
            </Button>
            <Button variant="ghost" size="sm" onClick={() => navigate('/')}>
              Back
            </Button>
          </div>
        </div>

        {error && <p className="mb-4 text-sm text-red">{error}</p>}

        {showCreate && (
          <GlassCard variant="elevated" padding="md" className="mb-6">
            <div className="space-y-3">
              <Input
                label="Room Name"
                placeholder="Room name"
                value={newRoom.name}
                onChange={(e) => setNewRoom({ ...newRoom, name: e.target.value })}
              />
              <div className="flex flex-col gap-1.5">
                <label className="font-body text-sm text-text-muted">Max Players</label>
                <select
                  value={newRoom.max_players}
                  onChange={(e) =>
                    setNewRoom({
                      ...newRoom,
                      max_players: parseInt(e.target.value, 10),
                    })
                  }
                  className="glass-subtle w-full px-3 py-2.5 text-text-primary focus:border-accent/50 focus:outline-none"
                >
                  <option value={2}>2 players</option>
                  <option value={3}>3 players</option>
                  <option value={4}>4 players</option>
                </select>
              </div>
              <Button variant="primary" fullWidth onClick={handleCreate}>
                Create
              </Button>
            </div>
          </GlassCard>
        )}

        <div className="space-y-2">
          {rooms.length === 0 && <p className="py-8 text-center text-text-muted">No rooms yet — create one!</p>}
          {rooms.map((room) => (
            <GlassCard
              key={room.room_id}
              padding="sm"
              onClick={() => handleJoin(room)}
              className="flex items-center justify-between"
            >
              <span className="font-display font-bold text-text-primary">{room.name}</span>
              <Badge variant="player">
                {room.player_count}/{room.max_players}
              </Badge>
            </GlassCard>
          ))}
        </div>
      </div>
    </PageTransition>
  );
}
