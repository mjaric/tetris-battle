import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, Navigate } from 'react-router';
import { useAuthContext } from './AuthProvider.tsx';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';
const NICKNAME_REGEX = /^[a-zA-Z][a-zA-Z0-9_]{2,19}$/;
const DEBOUNCE_MS = 300;

type NicknameStatus = 'idle' | 'checking' | 'available' | 'taken' | 'invalid';

export default function RegisterPage() {
  const navigate = useNavigate();
  const { registrationToken, registrationData, token, setToken, setRegistrationToken } = useAuthContext();
  const [displayName, setDisplayName] = useState('');
  const [nickname, setNickname] = useState('');
  const [nicknameStatus, setNicknameStatus] = useState<NicknameStatus>('idle');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (registrationData) {
      setDisplayName(registrationData.name);
    }
  }, [registrationData]);

  const checkNickname = useCallback(async (value: string) => {
    if (!NICKNAME_REGEX.test(value)) {
      setNicknameStatus('invalid');
      return;
    }

    setNicknameStatus('checking');

    const resp = await fetch(`${API_URL}/api/auth/check-nickname/${encodeURIComponent(value)}`);

    if (resp.ok) {
      const data = (await resp.json()) as { available: boolean };
      setNicknameStatus(data.available ? 'available' : 'taken');
    }
  }, []);

  const handleNicknameChange = useCallback(
    (value: string) => {
      setNickname(value);
      setNicknameStatus('idle');

      if (debounceRef.current) clearTimeout(debounceRef.current);

      if (value.length < 3) {
        setNicknameStatus(value.length > 0 ? 'invalid' : 'idle');
        return;
      }

      debounceRef.current = setTimeout(() => {
        void checkNickname(value);
      }, DEBOUNCE_MS);
    },
    [checkNickname]
  );

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!registrationToken || nicknameStatus !== 'available') return;

      setSubmitting(true);
      setError(null);

      const body: Record<string, string> = {
        registration_token: registrationToken,
        nickname,
        display_name: displayName,
      };

      if (token) {
        body['guest_token'] = token;
      }

      const resp = await fetch(`${API_URL}/api/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });

      if (resp.ok) {
        const data = (await resp.json()) as { token: string };
        setRegistrationToken(null);
        setToken(data.token);
        navigate('/', { replace: true });
      } else {
        const data = (await resp.json()) as {
          error?: string;
          errors?: Record<string, string[]>;
        };
        setError(
          data.error ??
            Object.values(data.errors ?? {})
              .flat()
              .join(', ') ??
            'Registration failed'
        );
        setSubmitting(false);
      }
    },
    [registrationToken, nickname, displayName, token, nicknameStatus, setToken, setRegistrationToken, navigate]
  );

  if (!registrationToken || !registrationData) {
    return <Navigate to="/login" replace />;
  }

  const canSubmit = nicknameStatus === 'available' && displayName.trim().length > 0 && !submitting;

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-8 bg-gradient-to-br from-accent to-cyan bg-clip-text text-4xl font-extrabold uppercase tracking-widest text-transparent">
        Create Account
      </h1>

      <form onSubmit={(e) => void handleSubmit(e)} className="w-full max-w-sm space-y-6">
        <div>
          <label htmlFor="displayName" className="mb-1 block text-sm text-gray-400">
            Full Name
          </label>
          <input
            id="displayName"
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            className="w-full rounded-lg border border-border bg-bg-secondary px-4 py-3 text-white focus:border-accent focus:outline-none"
            placeholder="Your full name"
          />
          <p className="mt-1 text-xs text-gray-600">Private — only visible to you</p>
        </div>

        <div>
          <label htmlFor="nickname" className="mb-1 block text-sm text-gray-400">
            Nickname
          </label>
          <input
            id="nickname"
            type="text"
            value={nickname}
            onChange={(e) => handleNicknameChange(e.target.value)}
            className="w-full rounded-lg border border-border bg-bg-secondary px-4 py-3 text-white focus:border-accent focus:outline-none"
            placeholder="Pick a unique handle"
            maxLength={20}
          />
          <div className="mt-1 flex items-center gap-1 text-xs">
            {nicknameStatus === 'idle' && (
              <span className="text-gray-600">3-20 chars, letters/digits/underscores, starts with a letter</span>
            )}
            {nicknameStatus === 'checking' && <span className="text-gray-400">Checking...</span>}
            {nicknameStatus === 'available' && <span className="text-green-400">Available</span>}
            {nicknameStatus === 'taken' && <span className="text-red-400">Already taken</span>}
            {nicknameStatus === 'invalid' && (
              <span className="text-red-400">Must start with a letter, 3-20 chars, letters/digits/underscores</span>
            )}
          </div>
        </div>

        {error && <p className="text-sm text-red-400">{error}</p>}

        <button
          type="submit"
          disabled={!canSubmit}
          className="w-full cursor-pointer rounded-lg bg-accent px-4 py-3 font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {submitting ? 'Creating...' : 'Create Account'}
        </button>
      </form>
    </div>
  );
}
