import React, { useState, useCallback } from 'react';
import MainMenu from './components/MainMenu';
import NicknameForm from './components/NicknameForm';
import Lobby from './components/Lobby';
import WaitingRoom from './components/WaitingRoom';
import MultiBoard from './components/MultiBoard';
import Results from './components/Results';
import Board from './components/Board';
import Sidebar from './components/Sidebar';
import useTetris from './hooks/useTetris';
import { useSocket, useChannel } from './hooks/useChannel';
import useMultiplayerGame from './hooks/useMultiplayerGame';

// Screens: menu, solo, nickname, lobby, waiting, playing, results
export default function App() {
  const [screen, setScreen] = useState('menu');
  const [nickname, setNickname] = useState(null);
  const [roomId, setRoomId] = useState(null);
  const [playerId, setPlayerId] = useState(null);
  const [isHost, setIsHost] = useState(false);

  // Socket connection (only when we have a nickname)
  const { socket, connected } = useSocket(nickname);

  // Lobby channel
  const lobbyChannel = useChannel(socket, 'lobby:main');

  // Game channel
  const gameChannel = useChannel(socket, roomId ? `game:${roomId}` : null);

  // Multiplayer game state
  const mp = useMultiplayerGame(gameChannel.channel, playerId);

  // --- Navigation handlers ---

  const goToSolo = useCallback(() => setScreen('solo'), []);
  const goToMenu = useCallback(() => {
    setScreen('menu');
    setNickname(null);
    setRoomId(null);
    lobbyChannel.leave();
    gameChannel.leave();
  }, [lobbyChannel, gameChannel]);

  const goToNickname = useCallback(() => setScreen('nickname'), []);

  const handleNickname = useCallback((nick) => {
    setNickname(nick);
    setScreen('lobby');
  }, []);

  const handleJoinRoom = useCallback((rid, password) => {
    setRoomId(rid);
    setScreen('waiting');
  }, []);

  const handleStartGame = useCallback(() => {
    mp.startGame();
  }, [mp]);

  // Auto-join lobby channel when entering lobby screen
  React.useEffect(() => {
    if (screen === 'lobby' && socket && !lobbyChannel.joined) {
      lobbyChannel.join();
    }
  }, [screen, socket, lobbyChannel]);

  // Auto-join game channel when entering waiting room
  React.useEffect(() => {
    if (screen === 'waiting' && socket && roomId && !gameChannel.joined) {
      gameChannel.join();
    }
  }, [screen, socket, roomId, gameChannel]);

  // Transition to playing when game starts
  React.useEffect(() => {
    if (mp.status === 'playing' && screen === 'waiting') {
      setScreen('playing');
    }
    if (mp.status === 'finished' && screen === 'playing') {
      setScreen('results');
    }
  }, [mp.status, screen]);

  // --- Render screens ---

  switch (screen) {
    case 'menu':
      return <MainMenu onSolo={goToSolo} onMultiplayer={goToNickname} />;

    case 'solo':
      return <SoloGame onBack={goToMenu} />;

    case 'nickname':
      return <NicknameForm onSubmit={handleNickname} onBack={goToMenu} />;

    case 'lobby':
      return <Lobby channel={lobbyChannel.channel} onJoinRoom={handleJoinRoom} onBack={goToMenu} />;

    case 'waiting':
      return (
        <WaitingRoom
          players={mp.gameState?.players || {}}
          isHost={isHost}
          onStart={handleStartGame}
          onBack={() => { gameChannel.leave(); setScreen('lobby'); }}
        />
      );

    case 'playing':
      return (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center',
          justifyContent: 'center', minHeight: '100vh',
          backgroundColor: '#0a0a1a', color: '#fff',
          fontFamily: "'Segoe UI', system-ui, sans-serif",
        }}>
          <h1 style={{
            fontSize: 28, fontWeight: 800, letterSpacing: 6,
            textTransform: 'uppercase', marginBottom: 16,
            background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
            WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
          }}>
            Tetris Battle
          </h1>
          <MultiBoard myState={mp.myState} opponents={mp.opponents} myPlayerId={playerId} />
        </div>
      );

    case 'results':
      return (
        <Results
          players={mp.gameState?.players || {}}
          eliminatedOrder={mp.gameState?.eliminated_order || []}
          onPlayAgain={handleStartGame}
          onBackToLobby={() => { gameChannel.leave(); setScreen('lobby'); }}
        />
      );

    default:
      return <MainMenu onSolo={goToSolo} onMultiplayer={goToNickname} />;
  }
}

// Solo game wrapper (existing single-player, unchanged logic)
function SoloGame({ onBack }) {
  const {
    board, score, lines, level, nextPiece,
    gameOver, gameStarted, isPaused, startGame, togglePause,
  } = useTetris();

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h1 style={{
        fontSize: 36, fontWeight: 800, letterSpacing: 8,
        textTransform: 'uppercase', marginBottom: 20,
        background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
        WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
      }}>
        Tetris
      </h1>
      <div style={{ display: 'flex', alignItems: 'flex-start' }}>
        <div style={{ position: 'relative' }}>
          <Board board={board} />
          {!gameStarted && (
            <Overlay onAction={startGame} actionLabel="Start Game">
              <div style={{ fontSize: 18, marginBottom: 16, color: '#ccc' }}>Press Start to Play</div>
            </Overlay>
          )}
          {gameOver && (
            <Overlay onAction={startGame} actionLabel="Play Again">
              <div style={{ fontSize: 28, fontWeight: 'bold', marginBottom: 8, color: '#ff4757' }}>Game Over</div>
              <div style={{ fontSize: 16, marginBottom: 16, color: '#ccc' }}>Score: {score.toLocaleString()}</div>
            </Overlay>
          )}
          {isPaused && !gameOver && (
            <Overlay onAction={togglePause} actionLabel="Resume">
              <div style={{ fontSize: 28, fontWeight: 'bold', marginBottom: 16, color: '#ffa502' }}>Paused</div>
            </Overlay>
          )}
        </div>
        <Sidebar score={score} lines={lines} level={level} nextPiece={nextPiece} />
      </div>
      <button onClick={onBack} style={{
        marginTop: 20, padding: '8px 20px', fontSize: 13,
        backgroundColor: '#333', color: '#ccc', border: 'none',
        borderRadius: 6, cursor: 'pointer',
      }}>
        Back to Menu
      </button>
    </div>
  );
}

function Overlay({ children, onAction, actionLabel }) {
  return (
    <div style={{
      position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      backgroundColor: 'rgba(0, 0, 0, 0.75)', borderRadius: 4, zIndex: 10,
    }}>
      {children}
      {onAction && (
        <button onClick={onAction} style={{
          padding: '12px 32px', fontSize: 16, fontWeight: 'bold', color: '#fff',
          backgroundColor: '#6c63ff', border: 'none', borderRadius: 8,
          cursor: 'pointer', letterSpacing: 1, textTransform: 'uppercase',
        }}>
          {actionLabel}
        </button>
      )}
    </div>
  );
}
