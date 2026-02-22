import { BrowserRouter, Routes, Route, Navigate } from 'react-router';
import { AuthProvider, useAuthContext } from './platform/auth/AuthProvider.tsx';
import { GameProvider, useGameContext } from './context/GameContext.tsx';
import LoginScreen from './platform/auth/LoginScreen.tsx';
import AuthCallback from './platform/auth/AuthCallback.tsx';
import RegisterPage from './platform/auth/RegisterPage.tsx';
import MainMenu from './components/MainMenu.tsx';
import SoloGame from './components/SoloGame.tsx';
import Lobby from './components/Lobby.tsx';
import GameSession from './components/GameSession.tsx';
import AppShell from './components/ui/AppShell.tsx';
import type { ReactNode } from 'react';

function RequireAuth({ children }: { children: ReactNode }) {
  const { isAuthenticated, loading } = useAuthContext();
  if (loading) return null;
  if (!isAuthenticated) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function RequireSocket({ children }: { children: ReactNode }) {
  const { connected } = useGameContext();
  if (!connected) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <p className="text-text-muted">Connecting...</p>
      </div>
    );
  }
  return <>{children}</>;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<LoginScreen />} />
      <Route path="/oauth/callback" element={<AuthCallback />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <AppShell>
              <MainMenu />
            </AppShell>
          </RequireAuth>
        }
      />
      <Route
        path="/solo"
        element={
          <AppShell hideSidebar>
            <SoloGame />
          </AppShell>
        }
      />
      <Route
        path="/lobby"
        element={
          <RequireAuth>
            <RequireSocket>
              <AppShell>
                <Lobby />
              </AppShell>
            </RequireSocket>
          </RequireAuth>
        }
      />
      <Route
        path="/room/:roomId"
        element={
          <RequireAuth>
            <RequireSocket>
              <AppShell hideSidebar>
                <GameSession />
              </AppShell>
            </RequireSocket>
          </RequireAuth>
        }
      />
      {/* Dev component showcase — only in dev mode */}
      {import.meta.env.DEV && (
        <Route
          path="/dev/components"
          element={
            <AppShell>
              <></>
            </AppShell>
          }
        />
      )}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <GameProvider>
          <AppRoutes />
        </GameProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
