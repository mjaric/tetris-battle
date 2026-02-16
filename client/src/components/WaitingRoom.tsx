import type { GameState } from "../types.ts";

interface WaitingRoomProps {
  gameState: GameState | null;
  isHost: boolean;
  startGame: () => void;
  onLeave: () => void;
}

export default function WaitingRoom({
  gameState,
  isHost,
  startGame,
  onLeave,
}: WaitingRoomProps) {
  const players = gameState?.players ?? {};
  const playerCount = Object.keys(players).length;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h2 className="mb-6 text-2xl font-bold">Waiting Room</h2>

      <div className="mb-6 min-w-75 rounded-lg border border-border bg-bg-secondary p-5">
        <h3 className="mb-3 text-xs uppercase tracking-widest text-muted">
          Players
        </h3>
        {Object.entries(players).map(([id, p]) => (
          <div
            key={id}
            className="mb-1 flex items-center justify-between rounded bg-bg-tertiary px-3 py-2"
          >
            <span>{p.nickname}</span>
            {gameState && id === gameState.host && (
              <span className="text-xs text-amber">HOST</span>
            )}
          </div>
        ))}
      </div>

      <div className="flex gap-3">
        <button
          onClick={onLeave}
          className="cursor-pointer rounded-lg border-none bg-border px-6 py-3 text-sm text-gray-400"
        >
          Leave
        </button>
        {isHost ? (
          <button
            onClick={startGame}
            disabled={playerCount < 2}
            className={`rounded-lg border-none px-8 py-3 text-base font-bold text-white ${
              playerCount >= 2
                ? "cursor-pointer bg-green"
                : "cursor-default bg-gray-700"
            }`}
          >
            Start Game
          </button>
        ) : (
          <div className="py-3 text-muted">
            Waiting for host to start...
          </div>
        )}
      </div>
    </div>
  );
}
