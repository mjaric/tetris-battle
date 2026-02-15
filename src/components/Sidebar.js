import React from 'react';
import NextPiece from './NextPiece';

function StatBox({ label, value }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <div style={{ color: '#888', fontSize: 12, textTransform: 'uppercase', letterSpacing: 2, marginBottom: 4 }}>
        {label}
      </div>
      <div style={{ color: '#fff', fontSize: 24, fontWeight: 'bold', fontFamily: 'monospace' }}>
        {value.toLocaleString()}
      </div>
    </div>
  );
}

export default function Sidebar({ score, lines, level, nextPiece }) {
  return (
    <div
      style={{
        marginLeft: 24,
        padding: 20,
        backgroundColor: '#16162a',
        borderRadius: 8,
        border: '1px solid #333',
        minWidth: 140,
      }}
    >
      <NextPiece piece={nextPiece} />
      <StatBox label="Score" value={score} />
      <StatBox label="Lines" value={lines} />
      <StatBox label="Level" value={level} />

      <div style={{ marginTop: 24, borderTop: '1px solid #333', paddingTop: 16 }}>
        <h3 style={{ margin: '0 0 10px', color: '#aaa', fontSize: 12, textTransform: 'uppercase', letterSpacing: 2 }}>
          Controls
        </h3>
        <div style={{ color: '#666', fontSize: 12, lineHeight: 1.8 }}>
          <div><kbd style={kbdStyle}>&larr; &rarr;</kbd> Move</div>
          <div><kbd style={kbdStyle}>&uarr;</kbd> Rotate</div>
          <div><kbd style={kbdStyle}>&darr;</kbd> Soft drop</div>
          <div><kbd style={kbdStyle}>Space</kbd> Hard drop</div>
          <div><kbd style={kbdStyle}>P</kbd> Pause</div>
        </div>
      </div>
    </div>
  );
}

const kbdStyle = {
  display: 'inline-block',
  padding: '1px 6px',
  backgroundColor: '#2a2a4a',
  borderRadius: 3,
  border: '1px solid #444',
  fontSize: 11,
  color: '#ccc',
  marginRight: 6,
  fontFamily: 'monospace',
};
