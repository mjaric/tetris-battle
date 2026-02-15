import React from 'react';
import Board from './components/Board';
import Sidebar from './components/Sidebar';
import useTetris from './hooks/useTetris';

function Overlay({ children, onAction, actionLabel }) {
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: 'rgba(0, 0, 0, 0.75)',
        borderRadius: 4,
        zIndex: 10,
      }}
    >
      {children}
      {onAction && (
        <button onClick={onAction} style={buttonStyle}>
          {actionLabel}
        </button>
      )}
    </div>
  );
}

export default function App() {
  const {
    board,
    score,
    lines,
    level,
    nextPiece,
    gameOver,
    gameStarted,
    isPaused,
    startGame,
    togglePause,
  } = useTetris();

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '100vh',
        backgroundColor: '#0a0a1a',
        color: '#fff',
        fontFamily: "'Segoe UI', system-ui, -apple-system, sans-serif",
      }}
    >
      <h1
        style={{
          fontSize: 36,
          fontWeight: 800,
          letterSpacing: 8,
          textTransform: 'uppercase',
          marginBottom: 20,
          background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
          WebkitBackgroundClip: 'text',
          WebkitTextFillColor: 'transparent',
        }}
      >
        Tetris
      </h1>

      <div style={{ display: 'flex', alignItems: 'flex-start' }}>
        <div style={{ position: 'relative' }}>
          <Board board={board} />

          {!gameStarted && (
            <Overlay onAction={startGame} actionLabel="Start Game">
              <div style={{ fontSize: 18, marginBottom: 16, color: '#ccc' }}>
                Press Start to Play
              </div>
            </Overlay>
          )}

          {gameOver && (
            <Overlay onAction={startGame} actionLabel="Play Again">
              <div style={{ fontSize: 28, fontWeight: 'bold', marginBottom: 8, color: '#ff4757' }}>
                Game Over
              </div>
              <div style={{ fontSize: 16, marginBottom: 16, color: '#ccc' }}>
                Score: {score.toLocaleString()}
              </div>
            </Overlay>
          )}

          {isPaused && !gameOver && (
            <Overlay onAction={togglePause} actionLabel="Resume">
              <div style={{ fontSize: 28, fontWeight: 'bold', marginBottom: 16, color: '#ffa502' }}>
                Paused
              </div>
            </Overlay>
          )}
        </div>

        <Sidebar score={score} lines={lines} level={level} nextPiece={nextPiece} />
      </div>
    </div>
  );
}

const buttonStyle = {
  padding: '12px 32px',
  fontSize: 16,
  fontWeight: 'bold',
  color: '#fff',
  backgroundColor: '#6c63ff',
  border: 'none',
  borderRadius: 8,
  cursor: 'pointer',
  letterSpacing: 1,
  textTransform: 'uppercase',
  transition: 'background-color 0.2s',
};
