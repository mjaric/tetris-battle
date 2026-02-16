import { useNavigate } from "react-router";
import { useTetris } from "../hooks/useTetris.ts";
import Board from "./Board.tsx";
import Sidebar from "./Sidebar.tsx";
import type { ReactNode } from "react";

function Overlay({
  children,
  onAction,
  actionLabel,
}: {
  children: ReactNode;
  onAction?: () => void;
  actionLabel?: string;
}) {
  return (
    <div className="absolute inset-0 z-10 flex flex-col items-center justify-center rounded bg-black/75">
      {children}
      {onAction && actionLabel && (
        <button
          onClick={onAction}
          className="cursor-pointer rounded-lg border-none bg-accent px-8 py-3 text-base font-bold uppercase tracking-wide text-white"
        >
          {actionLabel}
        </button>
      )}
    </div>
  );
}

export default function SoloGame() {
  const navigate = useNavigate();
  const {
    board,
    score,
    lines,
    level,
    nextPiece,
    gameOver,
    gameStarted,
    isPaused,
    startGame,
    togglePause,
  } = useTetris();

  const nextPieceObj = nextPiece
    ? { shape: nextPiece.shape, color: nextPiece.color }
    : null;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-5 text-4xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris
      </h1>
      <div className="flex items-start">
        <div className="relative">
          <Board board={board} />
          {!gameStarted && (
            <Overlay onAction={startGame} actionLabel="Start Game">
              <div className="mb-4 text-lg text-gray-400">
                Press Start to Play
              </div>
            </Overlay>
          )}
          {gameOver && (
            <Overlay onAction={startGame} actionLabel="Play Again">
              <div className="mb-2 text-2xl font-bold text-red">
                Game Over
              </div>
              <div className="mb-4 text-base text-gray-400">
                Score: {score.toLocaleString()}
              </div>
            </Overlay>
          )}
          {isPaused && !gameOver && (
            <Overlay onAction={togglePause} actionLabel="Resume">
              <div className="mb-4 text-2xl font-bold text-amber">
                Paused
              </div>
            </Overlay>
          )}
        </div>
        <Sidebar
          score={score}
          lines={lines}
          level={level}
          nextPiece={nextPieceObj}
        />
      </div>
      <button
        onClick={() => navigate("/")}
        className="mt-5 cursor-pointer rounded-md border-none bg-border px-5 py-2 text-sm text-gray-400"
      >
        Back to Menu
      </button>
    </div>
  );
}
