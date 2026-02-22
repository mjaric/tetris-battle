import { useState } from 'react';
import type { Channel } from 'phoenix';
import type { GameState } from '../types.ts';
import { GlassCard, Button, Badge, Avatar, Divider, PageTransition } from './ui/index.ts';

type Difficulty = 'easy' | 'medium' | 'hard' | 'battle';

interface WaitingRoomProps {
  gameState: GameState | null;
  isHost: boolean;
  startGame: () => void;
  onLeave: () => void;
  channel: Channel | null;
}

export default function WaitingRoom({ gameState, isHost, startGame, onLeave, channel }: WaitingRoomProps) {
  const [difficulty, setDifficulty] = useState<Difficulty>('medium');
  const players = gameState?.players ?? {};
  const playerCount = Object.keys(players).length;

  function addBot() {
    if (!channel) return;
    channel.push('add_bot', { difficulty }).receive<{ reason: string }>('error', (resp) => {
      console.error('add_bot failed:', resp.reason);
    });
  }

  function removeBot(botId: string) {
    if (!channel) return;
    channel.push('remove_bot', { bot_id: botId });
  }

  return (
    <PageTransition className="flex min-h-screen flex-col items-center justify-center p-8">
      <h2 className="mb-6 font-display text-2xl font-bold text-text-primary">Waiting Room</h2>

      <GlassCard variant="elevated" padding="md" className="mb-6 w-full max-w-md">
        <h3 className="mb-3 text-xs uppercase tracking-widest text-text-muted">Players</h3>
        <div className="space-y-2">
          {Object.entries(players).map(([id, p]) => (
            <div key={id} className="glass-subtle flex items-center justify-between px-3 py-2">
              <div className="flex items-center gap-2">
                <Avatar name={p.nickname} size="sm" />
                <span className="font-body text-sm text-text-primary">{p.nickname}</span>
                {p.is_bot && <Badge variant="bot">BOT</Badge>}
              </div>
              <div className="flex items-center gap-2">
                {gameState && id === gameState.host && <Badge variant="rank">HOST</Badge>}
                {isHost && p.is_bot && (
                  <Button variant="danger" size="sm" onClick={() => removeBot(id)}>
                    Remove
                  </Button>
                )}
              </div>
            </div>
          ))}
        </div>
      </GlassCard>

      {isHost && (
        <>
          <Divider className="mb-4 w-full max-w-md" />
          <div className="mb-6 flex items-center gap-3">
            <select
              value={difficulty}
              onChange={(e) => setDifficulty(e.target.value as Difficulty)}
              className="glass-subtle px-3 py-2 text-sm text-text-primary focus:border-accent/50 focus:outline-none"
            >
              <option value="easy">Easy</option>
              <option value="medium">Medium</option>
              <option value="hard">Hard</option>
              <option value="battle">Battle</option>
            </select>
            <Button variant="secondary" size="sm" onClick={addBot}>
              Add Bot
            </Button>
          </div>
        </>
      )}

      <div className="flex gap-3">
        <Button variant="ghost" onClick={onLeave}>
          Leave
        </Button>
        {isHost ? (
          <Button variant="primary" onClick={startGame} disabled={playerCount < 2}>
            Start Game
          </Button>
        ) : (
          <p className="py-3 text-text-muted">Waiting for host to start...</p>
        )}
      </div>
    </PageTransition>
  );
}
