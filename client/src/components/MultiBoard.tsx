import { useState, useEffect, useMemo } from 'react';
import { TETROMINOES } from '../constants.ts';
import type { GameState } from '../types.ts';
import { calculateCellSize } from '../utils/calculateCellSize.ts';
import { useGameEvents } from '../hooks/useGameEvents.ts';
import { useRenderStats } from '../hooks/useRenderStats.ts';
import { computeDangerLevel } from '../utils/dangerZone.ts';
import PlayerBoard from './PlayerBoard.tsx';

interface MultiBoardProps {
  gameState: GameState;
  myPlayerId: string;
  latency: number | null;
}

type GlowLevel = 'self' | 'target' | 'other' | 'eliminated';

function resolveGlowLevel(playerId: string, myPlayerId: string, targetId: string | null, alive: boolean): GlowLevel {
  if (!alive) return 'eliminated';
  if (playerId === myPlayerId) return 'self';
  if (playerId === targetId) return 'target';
  return 'other';
}

function useViewportSize(): { width: number; height: number } {
  const [size, setSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });

  useEffect(() => {
    function handleResize() {
      setSize({ width: window.innerWidth, height: window.innerHeight });
    }
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  return size;
}

export default function MultiBoard({ gameState, myPlayerId, latency }: MultiBoardProps) {
  const { width: viewportWidth, height: viewportHeight } = useViewportSize();
  const myState = gameState.players[myPlayerId];
  const { myEvents, opponentEvents } = useGameEvents(gameState, myPlayerId);
  const dangerLevel = myState ? computeDangerLevel(myState.board) : ('none' as const);
  const tetroDef = myState?.next_piece ? TETROMINOES[myState.next_piece] : undefined;
  const nextPieceObj = useMemo(() => (tetroDef ? { shape: tetroDef.shape, color: tetroDef.color } : null), [tetroDef]);
  const playerIds = Object.keys(gameState.players);
  useRenderStats('MultiBoard', playerIds.length);
  if (!myState) return null;

  const sortedPlayers = Object.entries(gameState.players).sort(([a], [b]) => {
    if (a === myPlayerId) return -1;
    if (b === myPlayerId) return 1;
    return a.localeCompare(b);
  });
  const playerCount = sortedPlayers.length;
  const cellSize = calculateCellSize(playerCount, viewportWidth, viewportHeight);
  const gap = Math.max(24, Math.round(cellSize * 1.2));

  const targetNickname = myState.target ? gameState.players[myState.target]?.nickname : undefined;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center">
      <h1 className="mb-4 bg-gradient-to-br from-accent to-cyan bg-clip-text font-display text-2xl font-bold uppercase tracking-widest text-transparent">
        Tetris Battle
      </h1>
      <div
        style={{
          display: 'flex',
          alignItems: 'flex-end',
          gap,
        }}
      >
        {sortedPlayers.map(([id, player], index) => {
          const hue = (index * 360) / playerCount;
          const glowLevel = resolveGlowLevel(id, myPlayerId, myState.target, player.alive);
          const isMe = id === myPlayerId;
          return (
            <PlayerBoard
              key={id}
              board={player.board}
              cellSize={cellSize}
              nickname={player.nickname}
              score={player.score}
              lines={player.lines}
              pendingGarbage={player.pending_garbage}
              playerHue={hue}
              glowLevel={glowLevel}
              isMe={isMe}
              nextPiece={isMe ? nextPieceObj : undefined}
              targetNickname={isMe ? targetNickname : undefined}
              level={isMe ? myState.level : undefined}
              latency={isMe ? latency : undefined}
              events={isMe ? myEvents : (opponentEvents.get(id) ?? [])}
              dangerLevel={isMe ? dangerLevel : 'none'}
            />
          );
        })}
      </div>
    </div>
  );
}
