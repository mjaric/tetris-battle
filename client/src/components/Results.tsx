import type { GameState, PlayerBroadcast } from '../types.ts';
import { GlassCard, Button, Badge, Avatar, Stat, PageTransition } from './ui/index.ts';

const MEDAL_LABELS = ['1st', '2nd', '3rd', '4th'];
const MEDAL_COLORS = ['var(--color-gold)', 'var(--color-silver)', 'var(--color-bronze)', 'var(--color-muted)'];

interface ResultsProps {
  gameState: GameState | null;
  onBack: () => void;
}

export default function Results({ gameState, onBack }: ResultsProps) {
  const players = gameState?.players ?? {};
  const eliminatedOrder = gameState?.eliminated_order ?? [];

  const alive = Object.entries(players)
    .filter(([, p]) => p.alive)
    .map(([id]) => id);
  const ranking = [...alive, ...eliminatedOrder.slice().reverse()];

  return (
    <PageTransition className="flex min-h-screen flex-col items-center justify-center p-8">
      <h2 className="mb-2 font-display text-3xl font-bold text-amber">Game Over</h2>
      <p className="mb-8 text-text-muted">Rankings</p>

      <div className="mb-8 w-full max-w-lg space-y-3">
        {ranking.map((pid, idx) => {
          const p: PlayerBroadcast | undefined = players[pid];
          if (!p) return null;
          const isWinner = idx === 0;
          const medalColor = MEDAL_COLORS[idx] ?? 'var(--color-muted)';

          return (
            <GlassCard
              key={pid}
              variant={isWinner ? 'elevated' : 'default'}
              padding="md"
              glow={isWinner ? 'rgba(255, 215, 0, 0.2)' : undefined}
              className="flex items-center justify-between"
            >
              <div className="flex items-center gap-3">
                <Badge variant="rank" color={medalColor}>
                  {MEDAL_LABELS[idx] ?? `#${idx + 1}`}
                </Badge>
                <Avatar name={p.nickname} size="sm" />
                <span className="font-display font-bold text-text-primary">{p.nickname}</span>
              </div>
              <div className="flex items-center gap-4">
                <Stat label="Score" value={(p.score ?? 0).toLocaleString()} />
                <Stat label="Lines" value={p.lines ?? 0} />
                <Stat label="Level" value={p.level ?? 1} />
              </div>
            </GlassCard>
          );
        })}
      </div>

      <Button variant="ghost" onClick={onBack}>
        Back to Lobby
      </Button>
    </PageTransition>
  );
}
