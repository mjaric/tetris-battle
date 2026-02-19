import { useEffect } from 'react';
import { useParams, useNavigate } from 'react-router';
import { useGameContext } from '../context/GameContext.tsx';
import { useChannel } from '../hooks/useChannel.ts';
import { useMultiplayerGame } from '../hooks/useMultiplayerGame.ts';
import { useLatency } from '../hooks/useLatency.ts';
import { soundManager } from '../audio/SoundManager.ts';
import AudioControls from './AudioControls.tsx';
import WaitingRoom from './WaitingRoom.tsx';
import MultiBoard from './MultiBoard.tsx';
import Results from './Results.tsx';

export default function GameSession() {
  const { roomId } = useParams();
  const navigate = useNavigate();
  const { socket, playerId } = useGameContext();
  const { channel, join, leave } = useChannel(socket, roomId ? `game:${roomId}` : null);
  const game = useMultiplayerGame(channel, playerId);
  const latency = useLatency(channel);

  useEffect(() => {
    if (socket && !channel && roomId) {
      join();
    }
  }, [socket, channel, roomId, join]);

  useEffect(() => {
    if (game.status === 'playing') {
      soundManager.init();
    }
  }, [game.status]);

  function handleLeave() {
    leave();
    navigate('/lobby');
  }

  if (game.status === 'finished') {
    return <Results gameState={game.gameState} onBack={handleLeave} />;
  }

  if (game.status === 'playing' && game.gameState && playerId) {
    return (
      <>
        <MultiBoard gameState={game.gameState} myPlayerId={playerId} latency={latency} />
        <AudioControls />
      </>
    );
  }

  return (
    <WaitingRoom
      gameState={game.gameState}
      isHost={game.isHost}
      startGame={game.startGame}
      onLeave={handleLeave}
      channel={channel}
    />
  );
}
