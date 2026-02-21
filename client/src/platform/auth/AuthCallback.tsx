import { useEffect } from 'react';
import { useNavigate } from 'react-router';
import { useAuthContext } from './AuthProvider.tsx';

export default function AuthCallback() {
  const navigate = useNavigate();
  const { setToken } = useAuthContext();

  useEffect(() => {
    const hash = window.location.hash;
    const params = new URLSearchParams(window.location.search);

    if (hash.startsWith('#token=')) {
      const token = hash.slice('#token='.length);
      setToken(token);
      window.history.replaceState(null, '', '/oauth/callback');
      navigate('/', { replace: true });
      return;
    }

    const error = params.get('error');
    if (error) {
      console.error('Auth error:', error);
    }

    navigate('/login', { replace: true });
  }, [navigate, setToken]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-bg-primary">
      <p className="text-gray-400">Signing in...</p>
    </div>
  );
}
