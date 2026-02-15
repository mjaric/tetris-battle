import React from 'react';
import { BOARD_WIDTH, BOARD_HEIGHT, CELL_SIZE } from '../constants';

function Cell({ color }) {
  const isGhost = typeof color === 'string' && color.startsWith('ghost:');
  const actualColor = isGhost ? color.split(':')[1] : color;

  const style = {
    width: CELL_SIZE,
    height: CELL_SIZE,
    border: '1px solid #333',
    boxSizing: 'border-box',
  };

  if (actualColor) {
    if (isGhost) {
      style.backgroundColor = '#1a1a2e';
      style.border = `1px dashed ${actualColor}55`;
    } else {
      style.backgroundColor = actualColor;
      style.boxShadow = `inset 0 0 8px rgba(255,255,255,0.3), inset -2px -2px 4px rgba(0,0,0,0.3)`;
      style.border = '1px solid rgba(255,255,255,0.15)';
    }
  } else {
    style.backgroundColor = '#1a1a2e';
  }

  return <div style={style} />;
}

export default function Board({ board }) {
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${BOARD_WIDTH}, ${CELL_SIZE}px)`,
        gridTemplateRows: `repeat(${BOARD_HEIGHT}, ${CELL_SIZE}px)`,
        border: '3px solid #6c63ff',
        borderRadius: 4,
        boxShadow: '0 0 20px rgba(108, 99, 255, 0.3)',
        backgroundColor: '#0f0f23',
      }}
    >
      {board.map((row, y) =>
        row.map((cell, x) => <Cell key={`${y}-${x}`} color={cell} />)
      )}
    </div>
  );
}
