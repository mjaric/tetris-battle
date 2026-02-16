import React from 'react';

export default function Results({ players, eliminatedOrder, onPlayAgain, onBackToLobby }) {
  const playerList = Object.entries(players);
  const alive = playerList.filter(([_, p]) => p.alive).map(([id]) => id);
  const ranking = [...alive, ...(eliminatedOrder || []).slice().reverse()];

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h2 style={{ marginBottom: 8, fontSize: 32, color: '#ffa502' }}>Game Over</h2>
      <h3 style={{ marginBottom: 24, color: '#888' }}>Rankings</h3>

      <div style={{ minWidth: 400, marginBottom: 32 }}>
        {ranking.map((pid, idx) => {
          const p = players[pid];
          if (!p) return null;
          const medal = idx === 0 ? '#ffd700' : idx === 1 ? '#c0c0c0' : idx === 2 ? '#cd7f32' : '#666';
          return (
            <div key={pid} style={{
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              padding: '12px 16px', marginBottom: 8, borderRadius: 8,
              backgroundColor: '#16162a', border: '2px solid ' + medal,
            }}>
              <div>
                <span style={{ color: medal, fontWeight: 'bold', marginRight: 12 }}>#{idx + 1}</span>
                <span style={{ fontWeight: 'bold' }}>{p.nickname}</span>
              </div>
              <div style={{ color: '#888', fontSize: 13 }}>
                Score: {(p.score || 0).toLocaleString()} | Lines: {p.lines || 0} | Lvl: {p.level || 1}
              </div>
            </div>
          );
        })}
      </div>

      <div style={{ display: 'flex', gap: 12 }}>
        <button onClick={onBackToLobby} style={{
          padding: '12px 24px', fontSize: 14, backgroundColor: '#333',
          border: 'none', borderRadius: 8, color: '#ccc', cursor: 'pointer',
        }}>
          Back to Lobby
        </button>
        <button onClick={onPlayAgain} style={{
          padding: '12px 32px', fontSize: 16, fontWeight: 'bold',
          backgroundColor: '#6c63ff', color: '#fff', border: 'none',
          borderRadius: 8, cursor: 'pointer',
        }}>
          Play Again
        </button>
      </div>
    </div>
  );
}
