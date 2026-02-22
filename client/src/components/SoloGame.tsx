import { useEffect, useRef } from 'react';
import { useNavigate } from 'react-router';
import { useTetris } from '../hooks/useTetris.ts';
import { useSoundEffects } from '../hooks/useSoundEffects.ts';
import { useAuth } from '../platform/auth/useAuth.ts';
import { computeDangerLevel } from '../utils/dangerZone.ts';
import { soundManager } from '../audio/SoundManager.ts';
import AudioControls from './AudioControls.tsx';
import Board from './Board.tsx';
import Sidebar from './Sidebar.tsx';
import { Button, PageTransition } from './ui/index.ts';
import type { ReactNode } from 'react';

const API_URL = import.meta.env['VITE_API_URL'] ?? 'http://localhost:4000';

function Overlay({
  children,
  onAction,
  actionLabel,
}: {
  children: ReactNode;
  onAction?: () => void;
  actionLabel?: string;
}) {
  return (
    <div className="glass absolute inset-0 z-10 flex flex-col items-center justify-center rounded-xl bg-black/60">
      {children}
      {onAction && actionLabel && (
        <Button variant="primary" size="lg" onClick={onAction}>
          {actionLabel}
        </Button>
      )}
    </div>
  );
}

export default function SoloGame() {
  const navigate = useNavigate();
  const { board, score, lines, level, nextPiece, gameOver, gameStarted, isPaused, startGame, togglePause, events } =
    useTetris();
  const { isAuthenticated, token } = useAuth();
  const reportedRef = useRef(false);

  useSoundEffects(events);
  const dangerLevel = computeDangerLevel(board);

  useEffect(() => {
    if (gameStarted) {
      soundManager.init();
      reportedRef.current = false;
    }
  }, [gameStarted]);

  useEffect(() => {
    if (gameOver && isAuthenticated && token && !reportedRef.current) {
      reportedRef.current = true;
      fetch(`${API_URL}/api/solo_results`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          score,
          lines_cleared: lines,
          pieces_placed: 0,
          duration_ms: 0,
        }),
      }).catch(() => {});
    }
  }, [gameOver, isAuthenticated, token, score, lines]);

  const nextPieceObj = nextPiece ? { shape: nextPiece.shape, color: nextPiece.color } : null;

  return (
    <PageTransition className="flex min-h-screen flex-col items-center justify-center">
      <h1 className="mb-5 bg-gradient-to-br from-accent to-cyan bg-clip-text font-display text-4xl font-bold uppercase tracking-widest text-transparent">
        Tetris
      </h1>
      <div className="flex items-start">
        <div className="relative">
          <Board board={board} events={events} dangerLevel={dangerLevel} />
          {!gameStarted && (
            <Overlay onAction={startGame} actionLabel="Start Game">
              <div className="mb-4 text-lg text-text-muted">Press Start to Play</div>
            </Overlay>
          )}
          {gameOver && (
            <Overlay onAction={startGame} actionLabel="Play Again">
              <div className="mb-2 font-display text-2xl font-bold text-red">Game Over</div>
              <div className="mb-4 text-base text-text-muted">Score: {score.toLocaleString()}</div>
            </Overlay>
          )}
          {isPaused && !gameOver && (
            <Overlay onAction={togglePause} actionLabel="Resume">
              <div className="mb-4 font-display text-2xl font-bold text-amber">Paused</div>
            </Overlay>
          )}
        </div>
        <Sidebar score={score} lines={lines} level={level} nextPiece={nextPieceObj} />
      </div>
      <Button variant="ghost" size="sm" className="mt-5" onClick={() => navigate('/')}>
        Back to Menu
      </Button>
      {gameStarted && <AudioControls />}
    </PageTransition>
  );
}
