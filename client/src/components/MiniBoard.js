import React from 'react';

const MINI_CELL = 12;

export default function MiniBoard({ board, nickname, alive, isTarget, onClick }) {
  if (!board) return null;

  return (
    <div
      onClick={onClick}
      style={{
        opacity: alive ? 1 : 0.3,
        cursor: onClick ? 'pointer' : 'default',
        marginBottom: 12,
      }}
    >
      <div style={{
        fontSize: 11, color: isTarget ? '#00f0f0' : '#888',
        marginBottom: 4, fontWeight: isTarget ? 'bold' : 'normal',
        textAlign: 'center',
      }}>
        {nickname} {isTarget && '(TARGET)'}
      </div>
      <div style={{
        display: 'grid',
        gridTemplateColumns: `repeat(10, ${MINI_CELL}px)`,
        gridTemplateRows: `repeat(20, ${MINI_CELL}px)`,
        border: isTarget ? '2px solid #00f0f0' : '1px solid #333',
        borderRadius: 2,
        backgroundColor: '#0f0f23',
      }}>
        {board.map((row, y) =>
          row.map((cell, x) => {
            const isGhost = typeof cell === 'string' && cell.startsWith('ghost:');
            return (
              <div key={`${y}-${x}`} style={{
                width: MINI_CELL,
                height: MINI_CELL,
                backgroundColor: (cell && !isGhost) ? cell : '#1a1a2e',
              }} />
            );
          })
        )}
      </div>
    </div>
  );
}
