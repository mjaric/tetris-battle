import { TETROMINOES } from "../constants.ts";
import type { PlayerBroadcast } from "../types.ts";
import type { Opponent } from "../hooks/useMultiplayerGame.ts";
import Board from "./Board.tsx";
import MiniBoard from "./MiniBoard.tsx";
import TargetIndicator from "./TargetIndicator.tsx";
import NextPiece from "./NextPiece.tsx";
import StatBox from "./StatBox.tsx";
import LatencyIndicator from "./LatencyIndicator.tsx";

interface MultiBoardProps {
  myState: PlayerBroadcast | null;
  opponents: Opponent[];
  latency: number | null;
}

export default function MultiBoard({
  myState,
  opponents,
  latency,
}: MultiBoardProps) {
  if (!myState) return null;

  const targetOpponent = opponents.find(
    (o) => o.id === myState.target,
  );

  const tetroDef = myState.next_piece
    ? TETROMINOES[myState.next_piece]
    : undefined;
  const nextPieceObj = tetroDef
    ? { shape: tetroDef.shape, color: tetroDef.color }
    : null;

  const leftOpponents = opponents.filter((_, i) => i % 2 === 0);
  const rightOpponents = opponents.filter(
    (_, i) => i % 2 === 1,
  );

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-4 text-2xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris Battle
      </h1>
      <div className="flex items-start gap-5">
        <div className="flex min-w-35 flex-col">
          {leftOpponents.map((o) => (
            <MiniBoard
              key={o.id}
              board={o.board}
              nickname={o.nickname}
              alive={o.alive}
              isTarget={o.id === myState.target}
              pendingGarbage={o.pending_garbage}
            />
          ))}
          <TargetIndicator
            targetNickname={targetOpponent?.nickname}
          />
          <div className="rounded-lg border border-border bg-bg-secondary p-3">
            {nextPieceObj && <NextPiece piece={nextPieceObj} />}
            <StatBox label="Score" value={myState.score} />
            <StatBox label="Lines" value={myState.lines} />
            <StatBox label="Level" value={myState.level} />
          </div>
          <LatencyIndicator latency={latency} />
        </div>

        <div className="relative">
          <Board board={myState.board} pendingGarbage={myState.pending_garbage} />
          {!myState.alive && (
            <div className="absolute inset-0 flex items-center justify-center rounded bg-black/75">
              <div className="text-2xl font-bold text-red">
                Eliminated
              </div>
            </div>
          )}
        </div>

        <div className="flex min-w-35 flex-col">
          {rightOpponents.map((o) => (
            <MiniBoard
              key={o.id}
              board={o.board}
              nickname={o.nickname}
              alive={o.alive}
              isTarget={o.id === myState.target}
              pendingGarbage={o.pending_garbage}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
