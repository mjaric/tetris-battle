import { useState, useEffect, useCallback, useRef } from 'react';

export default function useMultiplayerGame(channel, myPlayerId) {
  const [gameState, setGameState] = useState(null);
  const [status, setStatus] = useState('waiting');
  const targetIndexRef = useRef(0);

  useEffect(() => {
    if (!channel) return;

    const ref = channel.on('game_state', (payload) => {
      setGameState(payload);
      setStatus(payload.status);
    });

    return () => {
      channel.off('game_state', ref);
    };
  }, [channel]);

  const sendInput = useCallback((action) => {
    if (channel && status === 'playing') {
      channel.push('input', { action });
    }
  }, [channel, status]);

  const cycleTarget = useCallback(() => {
    if (!gameState || !channel) return;

    const opponents = Object.entries(gameState.players)
      .filter(([id, p]) => id !== myPlayerId && p.alive)
      .map(([id]) => id);

    if (opponents.length === 0) return;

    targetIndexRef.current = (targetIndexRef.current + 1) % opponents.length;
    const newTarget = opponents[targetIndexRef.current];
    channel.push('set_target', { target_id: newTarget });
  }, [gameState, channel, myPlayerId]);

  const startGame = useCallback(() => {
    if (channel) {
      channel.push('start_game', {});
    }
  }, [channel]);

  // Keyboard handler
  useEffect(() => {
    if (status !== 'playing') return;

    const handleKeyDown = (e) => {
      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault();
          sendInput('move_left');
          break;
        case 'ArrowRight':
          e.preventDefault();
          sendInput('move_right');
          break;
        case 'ArrowDown':
          e.preventDefault();
          sendInput('move_down');
          break;
        case 'ArrowUp':
          e.preventDefault();
          sendInput('rotate');
          break;
        case ' ':
          e.preventDefault();
          sendInput('hard_drop');
          break;
        case 'Tab':
          e.preventDefault();
          cycleTarget();
          break;
        default:
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [status, sendInput, cycleTarget]);

  const myState = gameState?.players?.[myPlayerId] || null;
  const opponents = gameState
    ? Object.entries(gameState.players)
        .filter(([id]) => id !== myPlayerId)
        .map(([id, p]) => ({ id, ...p }))
    : [];

  return {
    gameState,
    status,
    myState,
    opponents,
    startGame,
    sendInput,
    cycleTarget,
  };
}
