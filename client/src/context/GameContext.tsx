import { createContext, useContext, useMemo, type ReactNode } from 'react';
import type { Socket, Channel } from 'phoenix';
import { useSocket } from '../hooks/useSocket.ts';
import { useAuthContext } from '../platform/auth/AuthProvider.tsx';

interface GameContextValue {
  nickname: string | null;
  socket: Socket | null;
  connected: boolean;
  playerId: string | null;
  lobbyChannel: Channel | null;
}

const GameContext = createContext<GameContextValue | null>(null);

export function GameProvider({ children }: { children: ReactNode }) {
  const { token, user } = useAuthContext();
  const { socket, connected, playerId, lobbyChannel } = useSocket(token);
  const nickname = user?.nickname ?? user?.displayName ?? null;

  const value = useMemo<GameContextValue>(
    () => ({
      nickname,
      socket,
      connected,
      playerId,
      lobbyChannel,
    }),
    [nickname, socket, connected, playerId, lobbyChannel]
  );

  return <GameContext.Provider value={value}>{children}</GameContext.Provider>;
}

export function useGameContext(): GameContextValue {
  const ctx = useContext(GameContext);
  if (!ctx) {
    throw new Error('useGameContext must be used within GameProvider');
  }
  return ctx;
}
