import { BrowserRouter, Routes, Route, Navigate } from 'react-router';
import { GameProvider, useGameContext } from './context/GameContext.tsx';
import MainMenu from './components/MainMenu.tsx';
import SoloGame from './components/SoloGame.tsx';
import NicknameForm from './components/NicknameForm.tsx';
import Lobby from './components/Lobby.tsx';
import GameSession from './components/GameSession.tsx';
import type { ReactNode } from 'react';

function RequireNickname({ children }: { children: ReactNode }) {
  const { nickname } = useGameContext();
  if (!nickname) {
    return <Navigate to="/multiplayer" replace />;
  }
  return <>{children}</>;
}

function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<MainMenu />} />
      <Route path="/solo" element={<SoloGame />} />
      <Route path="/multiplayer" element={<NicknameForm />} />
      <Route
        path="/lobby"
        element={
          <RequireNickname>
            <Lobby />
          </RequireNickname>
        }
      />
      <Route
        path="/room/:roomId"
        element={
          <RequireNickname>
            <GameSession />
          </RequireNickname>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <GameProvider>
        <AppRoutes />
      </GameProvider>
    </BrowserRouter>
  );
}
