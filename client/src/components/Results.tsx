import type { GameState, PlayerBroadcast } from "../types.ts";

const MEDAL_COLORS = ["#ffd700", "#c0c0c0", "#cd7f32", "#666"];

function getMedalColor(index: number): string {
  return MEDAL_COLORS[index] ?? "#666";
}

interface ResultsProps {
  gameState: GameState | null;
  onBack: () => void;
}

export default function Results({
  gameState,
  onBack,
}: ResultsProps) {
  const players = gameState?.players ?? {};
  const eliminatedOrder =
    gameState?.eliminated_order ?? [];

  const alive = Object.entries(players)
    .filter(([, p]) => p.alive)
    .map(([id]) => id);
  const ranking = [
    ...alive,
    ...eliminatedOrder.slice().reverse(),
  ];

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h2 className="mb-2 text-3xl font-bold text-amber">
        Game Over
      </h2>
      <h3 className="mb-6 text-muted">Rankings</h3>

      <div className="mb-8 min-w-100">
        {ranking.map((pid, idx) => {
          const p: PlayerBroadcast | undefined =
            players[pid];
          if (!p) return null;
          const medal = getMedalColor(idx);
          return (
            <div
              key={pid}
              className="mb-2 flex items-center justify-between rounded-lg bg-bg-secondary px-4 py-3"
              style={{ border: `2px solid ${medal}` }}
            >
              <div>
                <span
                  className="mr-3 font-bold"
                  style={{ color: medal }}
                >
                  #{idx + 1}
                </span>
                <span className="font-bold">
                  {p.nickname}
                </span>
              </div>
              <div className="text-sm text-muted">
                Score: {(p.score ?? 0).toLocaleString()} |
                Lines: {p.lines ?? 0} | Lvl:{" "}
                {p.level ?? 1}
              </div>
            </div>
          );
        })}
      </div>

      <div className="flex gap-3">
        <button
          onClick={onBack}
          className="cursor-pointer rounded-lg border-none bg-border px-6 py-3 text-sm text-gray-400"
        >
          Back to Lobby
        </button>
      </div>
    </div>
  );
}
