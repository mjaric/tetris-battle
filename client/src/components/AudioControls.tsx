import { useState, useCallback } from 'react';
import { soundManager } from '../audio/SoundManager.ts';

export default function AudioControls() {
  const [muted, setMuted] = useState(soundManager.isMuted());
  const [volume, setVolume] = useState(soundManager.getVolume());

  const toggleMute = useCallback(() => {
    const next = !muted;
    setMuted(next);
    soundManager.setMuted(next);
  }, [muted]);

  const handleVolume = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const v = parseFloat(e.target.value);
      setVolume(v);
      soundManager.setVolume(v);
      if (v > 0 && muted) {
        setMuted(false);
        soundManager.setMuted(false);
      }
    },
    [muted]
  );

  return (
    <div
      style={{
        position: 'fixed',
        top: 12,
        right: 12,
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        backgroundColor: 'rgba(10, 10, 26, 0.85)',
        border: '1px solid rgba(255, 255, 255, 0.1)',
        borderRadius: 8,
        padding: '6px 12px',
        zIndex: 100,
      }}
    >
      <button
        onClick={toggleMute}
        style={{
          background: 'none',
          border: 'none',
          cursor: 'pointer',
          padding: 4,
          display: 'flex',
          alignItems: 'center',
        }}
        aria-label={muted ? 'Unmute' : 'Mute'}
      >
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke={muted ? '#ff4757' : '#888'}
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
          {muted ? (
            <>
              <line x1="23" y1="9" x2="17" y2="15" />
              <line x1="17" y1="9" x2="23" y2="15" />
            </>
          ) : (
            <>
              <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
              {volume > 0.5 && <path d="M19.07 4.93a10 10 0 0 1 0 14.14" />}
            </>
          )}
        </svg>
      </button>
      <input
        type="range"
        min="0"
        max="1"
        step="0.05"
        value={volume}
        onChange={handleVolume}
        style={{
          width: 70,
          accentColor: '#6c63ff',
          cursor: 'pointer',
        }}
        aria-label="Volume"
      />
    </div>
  );
}
