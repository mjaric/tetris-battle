import React from 'react';

export default function TargetIndicator({ targetNickname }) {
  return (
    <div style={{
      padding: '8px 16px',
      backgroundColor: '#1a1a2e',
      border: '1px solid #00f0f0',
      borderRadius: 6,
      marginBottom: 12,
      textAlign: 'center',
    }}>
      <div style={{ color: '#888', fontSize: 10, textTransform: 'uppercase', letterSpacing: 2 }}>
        Target
      </div>
      <div style={{ color: '#00f0f0', fontSize: 16, fontWeight: 'bold' }}>
        {targetNickname || '\u2014'}
      </div>
      <div style={{ color: '#555', fontSize: 10, marginTop: 4 }}>
        [Tab] to switch
      </div>
    </div>
  );
}
