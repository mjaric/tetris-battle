import { useCallback } from 'react';
import { useAuthContext } from './AuthProvider.tsx';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';

interface UseAuthResult {
  user: { id: string; displayName: string } | null;
  token: string | null;
  loading: boolean;
  isAuthenticated: boolean;
  loginWithGoogle: () => void;
  loginWithGithub: () => void;
  loginWithDiscord: () => void;
  loginAsGuest: () => Promise<void>;
  logout: () => void;
}

export function useAuth(): UseAuthResult {
  const { user, token, loading, isAuthenticated, setToken, logout } = useAuthContext();

  const loginWithGoogle = useCallback(() => {
    window.location.href = `${API_URL}/auth/google`;
  }, []);

  const loginWithGithub = useCallback(() => {
    window.location.href = `${API_URL}/auth/github`;
  }, []);

  const loginWithDiscord = useCallback(() => {
    window.location.href = `${API_URL}/auth/discord`;
  }, []);

  const loginAsGuest = useCallback(async () => {
    const resp = await fetch(`${API_URL}/api/auth/guest`, {
      method: 'POST',
    });

    if (resp.ok) {
      const data = (await resp.json()) as { token: string };
      setToken(data.token);
    }
  }, [setToken]);

  return {
    user,
    token,
    loading,
    isAuthenticated,
    loginWithGoogle,
    loginWithGithub,
    loginWithDiscord,
    loginAsGuest,
    logout,
  };
}
