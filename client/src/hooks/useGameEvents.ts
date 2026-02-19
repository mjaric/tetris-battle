import { useRef, useMemo } from 'react';
import type { GameState, GameEvent } from '../types';

export function useGameEvents(
  gameState: GameState | null,
  myPlayerId: string | null
): { myEvents: GameEvent[]; opponentEvents: Map<string, GameEvent[]> } {
  const lastTickRef = useRef<number>(-1);

  return useMemo(() => {
    if (!gameState || gameState.status !== 'playing') {
      return { myEvents: [], opponentEvents: new Map() };
    }

    // Only process new events when tick changes
    if (gameState.tick === lastTickRef.current) {
      return { myEvents: [], opponentEvents: new Map() };
    }
    lastTickRef.current = gameState.tick;

    const myEvents: GameEvent[] = myPlayerId
      ? (gameState.players[myPlayerId]?.events ?? [])
      : [];

    const opponentEvents = new Map<string, GameEvent[]>();
    for (const [playerId, playerData] of Object.entries(gameState.players)) {
      if (playerId !== myPlayerId && playerData.events?.length) {
        opponentEvents.set(playerId, playerData.events);
      }
    }

    return { myEvents, opponentEvents };
  }, [gameState, myPlayerId]);
}
