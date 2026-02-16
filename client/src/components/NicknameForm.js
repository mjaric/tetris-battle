import React, { useState, useEffect } from 'react';

const STORAGE_KEY = 'tetris_nickname';

export default function NicknameForm({ onSubmit, onBack }) {
  const [nickname, setNickname] = useState('');

  useEffect(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) setNickname(saved);
  }, []);

  const handleSubmit = (e) => {
    e.preventDefault();
    const trimmed = nickname.trim();
    if (trimmed.length >= 3 && trimmed.length <= 16 && /^[a-zA-Z0-9_]+$/.test(trimmed)) {
      localStorage.setItem(STORAGE_KEY, trimmed);
      onSubmit(trimmed);
    }
  };

  const valid = nickname.trim().length >= 3 && nickname.trim().length <= 16 && /^[a-zA-Z0-9_]+$/.test(nickname.trim());

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h2 style={{ marginBottom: 24, color: '#ccc' }}>Enter Nickname</h2>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <input
          type="text"
          value={nickname}
          onChange={(e) => setNickname(e.target.value)}
          placeholder="3-16 chars, a-z, 0-9, _"
          maxLength={16}
          style={{
            padding: '12px 20px', fontSize: 18, backgroundColor: '#1a1a2e',
            border: '2px solid #333', borderRadius: 8, color: '#fff',
            width: 280, marginBottom: 16, outline: 'none',
          }}
          autoFocus
        />
        <div style={{ display: 'flex', gap: 12 }}>
          <button type="button" onClick={onBack} style={{
            padding: '12px 24px', fontSize: 14, backgroundColor: '#333',
            border: 'none', borderRadius: 8, color: '#ccc', cursor: 'pointer',
          }}>
            Back
          </button>
          <button type="submit" disabled={!valid} style={{
            padding: '12px 32px', fontSize: 16, fontWeight: 'bold',
            backgroundColor: valid ? '#6c63ff' : '#444', color: '#fff',
            border: 'none', borderRadius: 8, cursor: valid ? 'pointer' : 'default',
          }}>
            Enter Lobby
          </button>
        </div>
      </form>
    </div>
  );
}
