import React from 'react';

const buttonStyle = {
  padding: '16px 48px',
  fontSize: 18,
  fontWeight: 'bold',
  color: '#fff',
  backgroundColor: '#6c63ff',
  border: 'none',
  borderRadius: 8,
  cursor: 'pointer',
  letterSpacing: 1,
  textTransform: 'uppercase',
  transition: 'background-color 0.2s',
  marginBottom: 16,
  width: 260,
};

export default function MainMenu({ onSolo, onMultiplayer }) {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: '100vh',
      backgroundColor: '#0a0a1a',
      color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h1 style={{
        fontSize: 48,
        fontWeight: 800,
        letterSpacing: 8,
        textTransform: 'uppercase',
        marginBottom: 48,
        background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
        WebkitBackgroundClip: 'text',
        WebkitTextFillColor: 'transparent',
      }}>
        Tetris
      </h1>
      <button onClick={onSolo} style={buttonStyle}>Solo</button>
      <button onClick={onMultiplayer} style={{...buttonStyle, backgroundColor: '#00b894'}}>
        Multiplayer
      </button>
    </div>
  );
}
