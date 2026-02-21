import { useNavigate } from 'react-router';
import { useAuth } from '../platform/auth/useAuth.ts';

export default function MainMenu() {
  const navigate = useNavigate();
  const { user, logout } = useAuth();

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      {user && (
        <div className="absolute top-6 right-6 flex items-center gap-3">
          <span className="text-sm text-gray-400">{user.displayName}</span>
          <button
            onClick={logout}
            className="cursor-pointer rounded border border-border px-3 py-1 text-xs text-gray-500 hover:text-white"
          >
            Logout
          </button>
        </div>
      )}

      <h1 className="mb-12 text-5xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris
      </h1>
      <button
        onClick={() => navigate('/solo')}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-accent px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Solo
      </button>
      <button
        onClick={() => navigate('/lobby')}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-green px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Multiplayer
      </button>
    </div>
  );
}
