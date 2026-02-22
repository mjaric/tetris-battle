import { useEffect } from 'react';
import { useNavigate } from 'react-router';
import { useMatchHistory } from './useMatchHistory.ts';
import type { Match, MatchPlayer } from './useMatchHistory.ts';
import { useAuth } from '../auth/useAuth.ts';
import { GlassCard, Button, Stat, PageTransition } from '../../components/ui/index.ts';

function formatDate(iso: string | null): string {
  if (!iso) return '--';
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatDuration(ms: number | null): string {
  if (!ms) return '--';
  const secs = Math.floor(ms / 1000);
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function findPlayer(match: Match, userId: string): MatchPlayer | undefined {
  return match.players.find((p) => p.user_id === userId);
}

function MatchCard({ match, userId }: { match: Match; userId: string }) {
  const player = findPlayer(match, userId);
  const isSolo = match.mode === 'solo';

  return (
    <GlassCard padding="md" className="flex items-center justify-between">
      <div className="flex flex-col gap-1">
        <div className="flex items-center gap-2">
          <span className="font-display text-sm font-bold uppercase text-text-primary">
            {isSolo ? 'Solo' : 'Multiplayer'}
          </span>
          <span className="text-xs text-text-muted">{formatDate(match.inserted_at)}</span>
        </div>
        {!isSolo && (
          <span className="text-xs text-text-muted">
            {match.player_count} players
            {player?.placement != null ? ` \u2014 #${player.placement}` : ''}
          </span>
        )}
      </div>
      <div className="flex items-center gap-4">
        <Stat label="Score" value={(player?.score ?? 0).toLocaleString()} />
        <Stat label="Lines" value={player?.lines_cleared ?? 0} />
        {player?.duration_ms != null && player.duration_ms > 0 && (
          <Stat label="Time" value={formatDuration(player.duration_ms)} />
        )}
      </div>
    </GlassCard>
  );
}

export default function MatchHistory() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { matches, loading, error, hasMore, loadMore, refresh } = useMatchHistory();

  useEffect(() => {
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const userId = user?.id ?? '';

  return (
    <PageTransition className="flex min-h-screen flex-col items-center px-4 pt-16 pb-8">
      <h1 className="mb-2 bg-gradient-to-br from-accent to-cyan bg-clip-text font-display text-3xl font-bold uppercase tracking-widest text-transparent">
        Match History
      </h1>
      <p className="mb-8 text-sm text-text-muted">Your recent games</p>

      <div className="w-full max-w-lg space-y-3">
        {matches.map((m) => (
          <MatchCard key={m.id} match={m} userId={userId} />
        ))}

        {matches.length === 0 && !loading && (
          <GlassCard padding="lg" className="text-center">
            <p className="text-text-muted">No matches yet. Play a game to see your history!</p>
          </GlassCard>
        )}

        {error && (
          <GlassCard padding="md" className="text-center">
            <p className="text-sm text-red">{error}</p>
          </GlassCard>
        )}

        {loading && (
          <div className="py-4 text-center">
            <p className="text-sm text-text-muted">Loading...</p>
          </div>
        )}

        {hasMore && matches.length > 0 && !loading && (
          <div className="flex justify-center pt-2">
            <Button variant="secondary" size="sm" onClick={() => void loadMore()}>
              Load More
            </Button>
          </div>
        )}
      </div>

      <Button variant="ghost" size="sm" className="mt-8" onClick={() => navigate('/')}>
        Back to Menu
      </Button>
    </PageTransition>
  );
}
