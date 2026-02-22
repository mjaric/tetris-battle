import { useState, useCallback } from 'react';
import { useAuth } from '../auth/useAuth.ts';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';
const PAGE_SIZE = 20;

export interface MatchPlayer {
  id: string;
  user_id: string | null;
  placement: number | null;
  score: number | null;
  lines_cleared: number | null;
  garbage_sent: number | null;
  garbage_received: number | null;
  pieces_placed: number | null;
  duration_ms: number | null;
}

export interface Match {
  id: string;
  mode: string;
  game_type: string;
  player_count: number;
  started_at: string | null;
  ended_at: string | null;
  inserted_at: string;
  players: MatchPlayer[];
}

interface UseMatchHistoryResult {
  matches: Match[];
  loading: boolean;
  error: string | null;
  hasMore: boolean;
  loadMore: () => Promise<void>;
  refresh: () => Promise<void>;
}

export function useMatchHistory(mode?: string): UseMatchHistoryResult {
  const { token } = useAuth();
  const [matches, setMatches] = useState<Match[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);
  const [offset, setOffset] = useState(0);

  const fetchMatches = useCallback(
    async (fetchOffset: number, append: boolean) => {
      if (!token) return;

      setLoading(true);
      setError(null);

      const params = new URLSearchParams({
        limit: String(PAGE_SIZE),
        offset: String(fetchOffset),
      });
      if (mode) params.set('mode', mode);

      try {
        const resp = await fetch(`${API_URL}/api/matches?${params.toString()}`, {
          headers: { Authorization: `Bearer ${token}` },
        });

        if (!resp.ok) {
          setError('Failed to load match history');
          setLoading(false);
          return;
        }

        const data = (await resp.json()) as { matches: Match[] };
        const fetched = data.matches;

        setMatches((prev) => (append ? [...prev, ...fetched] : fetched));
        setHasMore(fetched.length === PAGE_SIZE);
        setOffset(fetchOffset + fetched.length);
      } catch {
        setError('Network error');
      } finally {
        setLoading(false);
      }
    },
    [token, mode]
  );

  const loadMore = useCallback(async () => {
    await fetchMatches(offset, true);
  }, [fetchMatches, offset]);

  const refresh = useCallback(async () => {
    setOffset(0);
    setHasMore(true);
    await fetchMatches(0, false);
  }, [fetchMatches]);

  return { matches, loading, error, hasMore, loadMore, refresh };
}
