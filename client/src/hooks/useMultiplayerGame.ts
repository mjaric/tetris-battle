import { useState, useEffect, useCallback, useRef, useMemo } from "react";
import type { Channel } from "phoenix";
import type { GameState, PlayerBroadcast } from "../types.ts";

type GameStatus = GameState["status"];

export interface Opponent extends PlayerBroadcast {
  id: string;
}

interface UseMultiplayerGameResult {
  gameState: GameState | null;
  status: GameStatus;
  myState: PlayerBroadcast | null;
  opponents: Opponent[];
  isHost: boolean;
  startGame: () => void;
  sendInput: (action: string) => void;
  cycleTarget: () => void;
}

export function useMultiplayerGame(
  channel: Channel | null,
  myPlayerId: string | null,
): UseMultiplayerGameResult {
  const [gameState, setGameState] = useState<GameState | null>(null);
  const [status, setStatus] = useState<GameStatus>("waiting");
  const targetIndexRef = useRef(0);
  const prevStatusRef = useRef<GameStatus>("waiting");

  useEffect(() => {
    if (!channel) return;

    const ref = channel.on(
      "game_state",
      (payload: GameState) => {
        setGameState(payload);
        setStatus(payload.status);
      },
    );

    return () => {
      channel.off("game_state", ref);
    };
  }, [channel]);

  useEffect(() => {
    if (prevStatusRef.current !== "playing" && status === "playing") {
      targetIndexRef.current = 0;
    }
    prevStatusRef.current = status;
  }, [status]);

  const sendInput = useCallback(
    (action: string) => {
      if (channel && status === "playing") {
        channel.push("input", { action });
      }
    },
    [channel, status],
  );

  const cycleTarget = useCallback(() => {
    if (!gameState || !channel || !myPlayerId) return;

    const opponents = Object.entries(gameState.players)
      .filter(([id, p]) => id !== myPlayerId && p.alive)
      .map(([id]) => id);

    if (opponents.length === 0) return;

    targetIndexRef.current =
      (targetIndexRef.current + 1) % opponents.length;
    const newTarget = opponents[targetIndexRef.current];
    if (newTarget) {
      channel.push("set_target", { target_id: newTarget });
    }
  }, [gameState, channel, myPlayerId]);

  const startGame = useCallback(() => {
    if (channel) {
      channel.push("start_game", {});
    }
  }, [channel]);

  useEffect(() => {
    if (status !== "playing") return;

    function handleKeyDown(e: KeyboardEvent) {
      switch (e.key) {
        case "ArrowLeft":
          e.preventDefault();
          sendInput("move_left");
          break;
        case "ArrowRight":
          e.preventDefault();
          sendInput("move_right");
          break;
        case "ArrowDown":
          e.preventDefault();
          sendInput("move_down");
          break;
        case "ArrowUp":
          e.preventDefault();
          sendInput("rotate");
          break;
        case " ":
          e.preventDefault();
          sendInput("hard_drop");
          break;
        case "Tab":
          e.preventDefault();
          cycleTarget();
          break;
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [status, sendInput, cycleTarget]);

  const myState = myPlayerId
    ? gameState?.players[myPlayerId] ?? null
    : null;

  const opponents = useMemo<Opponent[]>(() => {
    if (!gameState || !myPlayerId) return [];
    return Object.entries(gameState.players)
      .filter(([id]) => id !== myPlayerId)
      .map(([id, p]) => ({ id, ...p }));
  }, [gameState, myPlayerId]);

  const isHost = Boolean(
    myPlayerId && gameState && gameState.host === myPlayerId,
  );

  return {
    gameState,
    status,
    myState,
    opponents,
    isHost,
    startGame,
    sendInput,
    cycleTarget,
  };
}
