import React from 'react';
import Board from './Board';
import MiniBoard from './MiniBoard';
import TargetIndicator from './TargetIndicator';
import NextPiece from './NextPiece';
import { TETROMINOES } from '../constants';

export default function MultiBoard({ myState, opponents, myPlayerId }) {
  if (!myState) return null;

  const myBoard = myState.board;
  const targetOpponent = opponents.find(o => o.id === myState.target);

  const nextPieceObj = myState.next_piece && TETROMINOES[myState.next_piece]
    ? { shape: TETROMINOES[myState.next_piece].shape, color: TETROMINOES[myState.next_piece].color }
    : null;

  const leftOpponents = opponents.filter((_, i) => i % 2 === 0);
  const rightOpponents = opponents.filter((_, i) => i % 2 === 1);

  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 20 }}>
      {/* Left side: opponents + stats */}
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 140 }}>
        {leftOpponents.map(o => (
          <MiniBoard
            key={o.id}
            board={o.board}
            nickname={o.nickname}
            alive={o.alive}
            isTarget={o.id === myState.target}
          />
        ))}
        <TargetIndicator targetNickname={targetOpponent?.nickname} />
        <div style={{ padding: 12, backgroundColor: '#16162a', borderRadius: 8, border: '1px solid #333' }}>
          {nextPieceObj && <NextPiece piece={nextPieceObj} />}
          <StatBox label="Score" value={myState.score} />
          <StatBox label="Lines" value={myState.lines} />
          <StatBox label="Level" value={myState.level} />
        </div>
      </div>

      {/* Center: my board */}
      <div style={{ position: 'relative' }}>
        <Board board={myBoard} />
        {!myState.alive && (
          <div style={{
            position: 'absolute', inset: 0, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            backgroundColor: 'rgba(0,0,0,0.75)', borderRadius: 4,
          }}>
            <div style={{ fontSize: 28, fontWeight: 'bold', color: '#ff4757' }}>
              Eliminated
            </div>
          </div>
        )}
      </div>

      {/* Right side: opponents */}
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 140 }}>
        {rightOpponents.map(o => (
          <MiniBoard
            key={o.id}
            board={o.board}
            nickname={o.nickname}
            alive={o.alive}
            isTarget={o.id === myState.target}
          />
        ))}
      </div>
    </div>
  );
}

function StatBox({ label, value }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ color: '#888', fontSize: 11, textTransform: 'uppercase', letterSpacing: 2 }}>{label}</div>
      <div style={{ color: '#fff', fontSize: 20, fontWeight: 'bold', fontFamily: 'monospace' }}>
        {(value || 0).toLocaleString()}
      </div>
    </div>
  );
}
