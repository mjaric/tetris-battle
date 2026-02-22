import { useEffect } from 'react';
import { useNavigate } from 'react-router';
import { useAuth } from './useAuth.ts';
import AmbientBackground from '../../components/ui/AmbientBackground.tsx';
import GlassCard from '../../components/ui/GlassCard.tsx';
import Button from '../../components/ui/Button.tsx';
import Divider from '../../components/ui/Divider.tsx';
import PageTransition from '../../components/ui/PageTransition.tsx';

export default function LoginScreen() {
  const { loginWithGoogle, loginWithGithub, loginWithDiscord, loginAsGuest, isAuthenticated, loading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (isAuthenticated) {
      navigate('/', { replace: true });
    }
  }, [isAuthenticated, navigate]);

  if (loading) return null;

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center">
      <AmbientBackground />
      <PageTransition className="flex w-full flex-col items-center px-4">
        <h1 className="mb-2 bg-gradient-to-br from-accent to-cyan bg-clip-text font-display text-5xl font-bold uppercase tracking-widest text-transparent">
          Tetris
        </h1>
        <p className="mb-10 text-sm text-text-muted">Multiplayer battle arena</p>

        <GlassCard variant="elevated" padding="lg" className="w-full max-w-sm">
          <div className="space-y-3">
            <Button variant="ghost" fullWidth onClick={loginWithGoogle} className="border border-glass-border">
              Continue with Google
            </Button>
            <Button variant="ghost" fullWidth onClick={loginWithGithub} className="border border-glass-border">
              Continue with GitHub
            </Button>
            <Button variant="ghost" fullWidth onClick={loginWithDiscord} className="border border-glass-border">
              Continue with Discord
            </Button>
          </div>

          <Divider label="OR" className="my-6" />

          <Button variant="secondary" fullWidth onClick={() => void loginAsGuest()}>
            Play as Guest
          </Button>
          <p className="mt-3 text-center text-xs text-text-muted">Guest accounts can be upgraded later</p>
        </GlassCard>
      </PageTransition>
    </div>
  );
}
