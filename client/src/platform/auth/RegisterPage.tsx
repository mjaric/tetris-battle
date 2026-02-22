import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, Navigate } from 'react-router';
import { useAuthContext } from './AuthProvider.tsx';
import AmbientBackground from '../../components/ui/AmbientBackground.tsx';
import GlassCard from '../../components/ui/GlassCard.tsx';
import Input from '../../components/ui/Input.tsx';
import Button from '../../components/ui/Button.tsx';
import Badge from '../../components/ui/Badge.tsx';
import PageTransition from '../../components/ui/PageTransition.tsx';

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

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

  const checkNickname = useCallback(async (value: string) => {
    if (!NICKNAME_REGEX.test(value)) {
      setNicknameStatus('invalid');
      return;
    }

    setNicknameStatus('checking');

    try {
      const resp = await fetch(`${API_URL}/api/auth/check-nickname/${encodeURIComponent(value)}`);

      if (resp.ok) {
        const data = (await resp.json()) as { available: boolean };
        setNicknameStatus(data.available ? 'available' : 'taken');
      } else {
        setNicknameStatus('idle');
      }
    } catch {
      setNicknameStatus('idle');
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
    [checkNickname],
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

      try {
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
              'Registration failed',
          );
          setSubmitting(false);
        }
      } catch {
        setError('Network error. Please try again.');
        setSubmitting(false);
      }
    },
    [registrationToken, nickname, displayName, token, nicknameStatus, setToken, setRegistrationToken, navigate],
  );

  if (!registrationToken || !registrationData) {
    return <Navigate to="/login" replace />;
  }

  const canSubmit = nicknameStatus === 'available' && displayName.trim().length > 0 && !submitting;

  const nicknameStatusBadge = () => {
    switch (nicknameStatus) {
      case 'checking':
        return <Badge variant="status" color="#888">Checking...</Badge>;
      case 'available':
        return <Badge variant="status">Available</Badge>;
      case 'taken':
        return <Badge color="#ff4757">Already taken</Badge>;
      case 'invalid':
        return <Badge color="#ff4757">Invalid format</Badge>;
      default:
        return null;
    }
  };

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center">
      <AmbientBackground />
      <PageTransition className="flex w-full flex-col items-center px-4">
        <h1 className="mb-2 bg-gradient-to-br from-accent to-cyan bg-clip-text font-display text-4xl font-bold uppercase tracking-widest text-transparent">
          Create Account
        </h1>
        <p className="mb-8 text-sm text-text-muted">Choose your identity</p>

        <GlassCard variant="elevated" padding="lg" className="w-full max-w-sm">
          <form onSubmit={(e) => void handleSubmit(e)} className="space-y-5">
            <div>
              <Input
                label="Full Name"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="Your full name"
              />
              <p className="mt-1 text-xs text-text-muted">Private — only visible to you</p>
            </div>

            <div>
              <Input
                label="Nickname"
                value={nickname}
                onChange={(e) => handleNicknameChange(e.target.value)}
                placeholder="Pick a unique handle"
                maxLength={20}
                error={nicknameStatus === 'invalid' ? 'Must start with a letter, 3-20 chars, letters/digits/underscores' : undefined}
              />
              <div className="mt-2 flex items-center gap-2">
                {nicknameStatusBadge()}
                {nicknameStatus === 'idle' && nickname.length === 0 && (
                  <span className="text-xs text-text-muted">3-20 chars, letters/digits/underscores</span>
                )}
              </div>
            </div>

            {error && <p className="text-sm text-red">{error}</p>}

            <Button type="submit" variant="primary" fullWidth disabled={!canSubmit}>
              {submitting ? 'Creating...' : 'Create Account'}
            </Button>
          </form>
        </GlassCard>
      </PageTransition>
    </div>
  );
}
