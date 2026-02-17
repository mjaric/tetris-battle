import { useState } from "react";
import type { Channel } from "phoenix";
import type { GameState } from "../types.ts";

type Difficulty = "easy" | "medium" | "hard" | "battle";

interface WaitingRoomProps {
  gameState: GameState | null;
  isHost: boolean;
  startGame: () => void;
  onLeave: () => void;
  channel: Channel | null;
}

export default function WaitingRoom({
  gameState,
  isHost,
  startGame,
  onLeave,
  channel,
}: WaitingRoomProps) {
  const [difficulty, setDifficulty] = useState<Difficulty>("medium");
  const players = gameState?.players ?? {};
  const playerCount = Object.keys(players).length;

  function addBot() {
    if (!channel) return;
    channel
      .push("add_bot", { difficulty })
      .receive("error", (resp) => {
        console.error("add_bot failed:", resp.reason);
      });
  }

  function removeBot(botId: string) {
    if (!channel) return;
    channel.push("remove_bot", { bot_id: botId });
  }

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
            <div className="flex items-center gap-2">
              <span>{p.nickname}</span>
              {p.is_bot && (
                <span className="rounded bg-cyan/20 px-1.5 py-0.5 text-xs text-cyan">
                  BOT
                </span>
              )}
            </div>
            <div className="flex items-center gap-2">
              {gameState && id === gameState.host && (
                <span className="text-xs text-amber">HOST</span>
              )}
              {isHost && p.is_bot && (
                <button
                  onClick={() => removeBot(id)}
                  className="cursor-pointer rounded border-none bg-red/20 px-2 py-0.5 text-xs text-red"
                >
                  Remove
                </button>
              )}
            </div>
          </div>
        ))}
      </div>

      {isHost && (
        <div className="mb-4 flex items-center gap-2">
          <select
            value={difficulty}
            onChange={(e) => setDifficulty(e.target.value as Difficulty)}
            className="rounded border border-border bg-bg-tertiary px-3 py-2 text-sm text-white"
          >
            <option value="easy">Easy</option>
            <option value="medium">Medium</option>
            <option value="hard">Hard</option>
            <option value="battle">Battle</option>
          </select>
          <button
            onClick={addBot}
            className="cursor-pointer rounded-lg border-none bg-cyan px-4 py-2 text-sm font-bold text-black"
          >
            Add Bot
          </button>
        </div>
      )}

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
