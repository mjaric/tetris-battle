import { useAuth } from './useAuth.ts';

export default function LoginScreen() {
  const { loginWithGoogle, loginWithGithub, loginWithDiscord, loginAsGuest } = useAuth();

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-12 bg-gradient-to-br from-accent to-cyan bg-clip-text text-5xl font-extrabold uppercase tracking-widest text-transparent">
        Tetris
      </h1>

      <div className="w-full max-w-sm space-y-4">
        <button
          onClick={loginWithGoogle}
          className="w-full cursor-pointer rounded-lg bg-white px-4 py-3 font-medium text-gray-800 hover:bg-gray-100"
        >
          Continue with Google
        </button>
        <button
          onClick={loginWithGithub}
          className="w-full cursor-pointer rounded-lg bg-gray-700 px-4 py-3 font-medium text-white hover:bg-gray-600"
        >
          Continue with GitHub
        </button>
        <button
          onClick={loginWithDiscord}
          className="w-full cursor-pointer rounded-lg bg-indigo-600 px-4 py-3 font-medium text-white hover:bg-indigo-500"
        >
          Continue with Discord
        </button>

        <div className="relative py-2">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-border" />
          </div>
          <div className="relative flex justify-center text-sm">
            <span className="bg-bg-primary px-2 text-gray-500">or</span>
          </div>
        </div>

        <button
          onClick={() => void loginAsGuest()}
          className="w-full cursor-pointer rounded-lg border border-border px-4 py-3 font-medium text-gray-400 hover:bg-bg-tertiary"
        >
          Play as Guest
        </button>
        <p className="text-center text-xs text-gray-600">Guest accounts can be upgraded later</p>
      </div>
    </div>
  );
}
