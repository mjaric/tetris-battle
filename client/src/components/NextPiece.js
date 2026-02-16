import React from 'react';

const PREVIEW_CELL = 22;

export default function NextPiece({ piece }) {
  if (!piece) return null;

  return (
    <div style={{ marginBottom: 20 }}>
      <h3 style={{ margin: '0 0 8px', color: '#aaa', fontSize: 14, textTransform: 'uppercase', letterSpacing: 2 }}>
        Next
      </h3>
      <div
        style={{
          display: 'inline-grid',
          gridTemplateColumns: `repeat(${piece.shape[0].length}, ${PREVIEW_CELL}px)`,
          gap: 1,
          padding: 10,
          backgroundColor: '#1a1a2e',
          borderRadius: 4,
          border: '1px solid #333',
        }}
      >
        {piece.shape.map((row, y) =>
          row.map((cell, x) => (
            <div
              key={`${y}-${x}`}
              style={{
                width: PREVIEW_CELL,
                height: PREVIEW_CELL,
                backgroundColor: cell ? piece.color : 'transparent',
                borderRadius: 2,
                boxShadow: cell
                  ? 'inset 0 0 6px rgba(255,255,255,0.3)'
                  : 'none',
              }}
            />
          ))
        )}
      </div>
    </div>
  );
}
