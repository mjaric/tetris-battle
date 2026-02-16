import {
  createContext,
  useContext,
  useState,
  useMemo,
  type ReactNode,
} from "react";
import type { Socket, Channel } from "phoenix";
import { useSocket } from "../hooks/useSocket.ts";

interface GameContextValue {
  nickname: string | null;
  setNickname: (name: string | null) => void;
  socket: Socket | null;
  connected: boolean;
  playerId: string | null;
  lobbyChannel: Channel | null;
}

const GameContext = createContext<GameContextValue | null>(null);

export function GameProvider(
  { children }: { children: ReactNode },
) {
  const [nickname, setNickname] = useState<string | null>(null);
  const { socket, connected, playerId, lobbyChannel } =
    useSocket(nickname);

  const value = useMemo<GameContextValue>(
    () => ({
      nickname,
      setNickname,
      socket,
      connected,
      playerId,
      lobbyChannel,
    }),
    [nickname, socket, connected, playerId, lobbyChannel],
  );

  return (
    <GameContext.Provider value={value}>
      {children}
    </GameContext.Provider>
  );
}

export function useGameContext(): GameContextValue {
  const ctx = useContext(GameContext);
  if (!ctx) {
    throw new Error(
      "useGameContext must be used within GameProvider",
    );
  }
  return ctx;
}
