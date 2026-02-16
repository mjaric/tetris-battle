import React from 'react';

export default function WaitingRoom({ players, isHost, onStart, onBack }) {
  const playerCount = Object.keys(players).length;

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h2 style={{ marginBottom: 24 }}>Waiting Room</h2>

      <div style={{
        padding: 20, backgroundColor: '#16162a', borderRadius: 8,
        border: '1px solid #333', minWidth: 300, marginBottom: 24,
      }}>
        <h3 style={{ color: '#888', fontSize: 12, textTransform: 'uppercase', letterSpacing: 2, marginBottom: 12 }}>
          Players
        </h3>
        {Object.entries(players).map(([id, p]) => (
          <div key={id} style={{
            padding: '8px 12px', marginBottom: 4, borderRadius: 4,
            backgroundColor: '#1a1a2e', display: 'flex', justifyContent: 'space-between',
          }}>
            <span>{p.nickname}</span>
            {p.isHost && <span style={{ color: '#ffa502', fontSize: 12 }}>HOST</span>}
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', gap: 12 }}>
        <button onClick={onBack} style={{
          padding: '12px 24px', fontSize: 14, backgroundColor: '#333',
          border: 'none', borderRadius: 8, color: '#ccc', cursor: 'pointer',
        }}>
          Leave
        </button>
        {isHost && (
          <button
            onClick={onStart}
            disabled={playerCount < 2}
            style={{
              padding: '12px 32px', fontSize: 16, fontWeight: 'bold',
              backgroundColor: playerCount >= 2 ? '#00b894' : '#444',
              color: '#fff', border: 'none', borderRadius: 8,
              cursor: playerCount >= 2 ? 'pointer' : 'default',
            }}
          >
            Start Game
          </button>
        )}
        {!isHost && (
          <div style={{ color: '#888', padding: '12px 0' }}>Waiting for host to start...</div>
        )}
      </div>
    </div>
  );
}
