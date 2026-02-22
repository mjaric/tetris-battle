import { useNavigate } from 'react-router';
import { useAuth } from '../platform/auth/useAuth.ts';
import { GlassCard, Button, PageTransition } from './ui/index.ts';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';

export default function MainMenu() {
  const navigate = useNavigate();
  const { user, isGuest, logout } = useAuth();

  return (
    <PageTransition className="flex min-h-screen flex-col items-center justify-center p-8">
      {user && (
        <div className="absolute top-6 right-6 flex items-center gap-3">
          <span className="text-sm text-text-muted">{user.nickname ?? user.displayName}</span>
          {isGuest && (
            <div className="flex gap-2">
              <a
                href={`${API_URL}/auth/google`}
                className="rounded-lg border border-accent/30 px-3 py-1 text-xs text-accent transition-colors hover:bg-accent hover:text-white"
              >
                Link Google
              </a>
              <a
                href={`${API_URL}/auth/github`}
                className="rounded-lg border border-accent/30 px-3 py-1 text-xs text-accent transition-colors hover:bg-accent hover:text-white"
              >
                Link GitHub
              </a>
              <a
                href={`${API_URL}/auth/discord`}
                className="rounded-lg border border-accent/30 px-3 py-1 text-xs text-accent transition-colors hover:bg-accent hover:text-white"
              >
                Link Discord
              </a>
            </div>
          )}
          <Button variant="ghost" size="sm" onClick={logout}>
            Logout
          </Button>
        </div>
      )}

      <h1 className="mb-10 bg-gradient-to-br from-accent to-cyan bg-clip-text font-display text-5xl font-bold uppercase tracking-widest text-transparent">
        Tetris
      </h1>

      <div className="flex flex-col gap-6 sm:flex-row">
        <GlassCard variant="elevated" padding="lg" className="flex w-64 flex-col items-center text-center">
          <span className="mb-3 text-4xl">🎮</span>
          <h2 className="mb-1 font-display text-xl font-bold text-text-primary">Solo Play</h2>
          <p className="mb-5 text-sm text-text-muted">Practice your skills against gravity</p>
          <Button variant="primary" fullWidth onClick={() => navigate('/solo')}>
            Play Solo
          </Button>
        </GlassCard>

        <GlassCard variant="elevated" padding="lg" className="flex w-64 flex-col items-center text-center">
          <span className="mb-3 text-4xl">⚔️</span>
          <h2 className="mb-1 font-display text-xl font-bold text-text-primary">Multiplayer</h2>
          <p className="mb-5 text-sm text-text-muted">Battle other players in real-time</p>
          <Button variant="primary" fullWidth onClick={() => navigate('/lobby')}>
            Enter Lobby
          </Button>
        </GlassCard>
      </div>
    </PageTransition>
  );
}
