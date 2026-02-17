import { useState, useEffect } from "react";
import { TETROMINOES } from "../constants.ts";
import type { GameState } from "../types.ts";
import { calculateCellSize } from "../utils/calculateCellSize.ts";
import PlayerBoard from "./PlayerBoard.tsx";

interface MultiBoardProps {
  gameState: GameState;
  myPlayerId: string;
  latency: number | null;
}

type GlowLevel = "self" | "target" | "other" | "eliminated";

function resolveGlowLevel(
  playerId: string,
  myPlayerId: string,
  targetId: string | null,
  alive: boolean,
): GlowLevel {
  if (!alive) return "eliminated";
  if (playerId === myPlayerId) return "self";
  if (playerId === targetId) return "target";
  return "other";
}

function useViewportWidth(): number {
  const [width, setWidth] = useState(window.innerWidth);

  useEffect(() => {
    function handleResize() {
      setWidth(window.innerWidth);
    }
    window.addEventListener("resize", handleResize);
    return () =>
      window.removeEventListener("resize", handleResize);
  }, []);

  return width;
}

export default function MultiBoard({
  gameState,
  myPlayerId,
  latency,
}: MultiBoardProps) {
  const viewportWidth = useViewportWidth();
  const myState = gameState.players[myPlayerId];
  if (!myState) return null;

  const sortedPlayers = Object.entries(gameState.players).sort(
    ([a], [b]) => a.localeCompare(b),
  );
  const playerCount = sortedPlayers.length;
  const cellSize = calculateCellSize(
    playerCount,
    viewportWidth,
  );
  const gap = Math.max(8, Math.round(cellSize * 0.4));

  const targetNickname = myState.target
    ? gameState.players[myState.target]?.nickname
    : undefined;

  const tetroDef = myState.next_piece
    ? TETROMINOES[myState.next_piece]
    : undefined;
  const nextPieceObj = tetroDef
    ? { shape: tetroDef.shape, color: tetroDef.color }
    : null;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-4 text-2xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris Battle
      </h1>
      <div
        style={{
          display: "flex",
          alignItems: "flex-start",
          gap,
        }}
      >
        {sortedPlayers.map(([id, player], index) => {
          const hue = (index * 360) / playerCount;
          const glowLevel = resolveGlowLevel(
            id,
            myPlayerId,
            myState.target,
            player.alive,
          );
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
            />
          );
        })}
      </div>
    </div>
  );
}
