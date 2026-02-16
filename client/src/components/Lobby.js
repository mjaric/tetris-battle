import React, { useState, useEffect, useCallback } from 'react';

export default function Lobby({ channel, onJoinRoom, onBack }) {
  const [rooms, setRooms] = useState([]);
  const [showCreate, setShowCreate] = useState(false);
  const [newRoom, setNewRoom] = useState({ name: '', max_players: 4, password: '' });

  const refreshRooms = useCallback(() => {
    if (!channel) return;
    channel.push('list_rooms', {}).receive('ok', (resp) => setRooms(resp.rooms || []));
  }, [channel]);

  useEffect(() => {
    refreshRooms();
    if (channel) {
      const ref1 = channel.on('room_created', () => refreshRooms());
      const ref2 = channel.on('room_removed', () => refreshRooms());
      return () => {
        channel.off('room_created', ref1);
        channel.off('room_removed', ref2);
      };
    }
  }, [channel, refreshRooms]);

  const handleCreate = () => {
    channel.push('create_room', {
      name: newRoom.name || 'Unnamed Room',
      max_players: newRoom.max_players,
      password: newRoom.password || null,
    }).receive('ok', (resp) => {
      setShowCreate(false);
      onJoinRoom(resp.room_id);
    });
  };

  const handleJoin = (room) => {
    if (room.has_password) {
      const pw = prompt('Enter room password:');
      if (pw) onJoinRoom(room.room_id, pw);
    } else {
      onJoinRoom(room.room_id);
    }
  };

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      minHeight: '100vh', backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif", padding: 40,
    }}>
      <h2 style={{ marginBottom: 24 }}>Lobby</h2>

      <div style={{ display: 'flex', gap: 12, marginBottom: 24 }}>
        <button onClick={() => setShowCreate(!showCreate)} style={btnStyle}>
          Create Room
        </button>
        <button onClick={onBack} style={{...btnStyle, backgroundColor: '#333'}}>
          Back
        </button>
      </div>

      {showCreate && (
        <div style={{ marginBottom: 24, padding: 20, backgroundColor: '#16162a', borderRadius: 8, border: '1px solid #333' }}>
          <input placeholder="Room name" value={newRoom.name}
            onChange={(e) => setNewRoom({...newRoom, name: e.target.value})}
            style={inputStyle} />
          <select value={newRoom.max_players}
            onChange={(e) => setNewRoom({...newRoom, max_players: parseInt(e.target.value)})}
            style={{...inputStyle, marginTop: 8}}>
            <option value={2}>2 players</option>
            <option value={3}>3 players</option>
            <option value={4}>4 players</option>
          </select>
          <input placeholder="Password (optional)" value={newRoom.password}
            onChange={(e) => setNewRoom({...newRoom, password: e.target.value})}
            type="password" style={{...inputStyle, marginTop: 8}} />
          <button onClick={handleCreate} style={{...btnStyle, marginTop: 12, width: '100%'}}>
            Create
          </button>
        </div>
      )}

      <div style={{ width: '100%', maxWidth: 500 }}>
        {rooms.length === 0 && <div style={{ color: '#666', textAlign: 'center' }}>No rooms yet</div>}
        {rooms.map((room) => (
          <div key={room.room_id} onClick={() => handleJoin(room)} style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            padding: '12px 16px', backgroundColor: '#16162a', borderRadius: 8,
            border: '1px solid #333', marginBottom: 8, cursor: 'pointer',
          }}>
            <div>
              <span style={{ fontWeight: 'bold' }}>{room.name}</span>
              {room.has_password && <span style={{ marginLeft: 8, color: '#ffa502' }}>locked</span>}
            </div>
            <span style={{ color: '#888' }}>{room.player_count}/{room.max_players}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const btnStyle = {
  padding: '10px 24px', fontSize: 14, fontWeight: 'bold',
  backgroundColor: '#6c63ff', color: '#fff', border: 'none',
  borderRadius: 8, cursor: 'pointer',
};

const inputStyle = {
  padding: '10px 14px', fontSize: 14, backgroundColor: '#1a1a2e',
  border: '1px solid #333', borderRadius: 6, color: '#fff',
  width: '100%', outline: 'none', display: 'block',
};
