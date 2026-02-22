import { BOARD_WIDTH, BOARD_HEIGHT, CELL_SIZE } from '../constants.ts';
import type { GameEvent } from '../types.ts';
import type { DangerLevel } from '../utils/dangerZone.ts';
import { useAnimations } from '../hooks/useAnimations.ts';

interface CellProps {
  color: string | null;
}

function Cell({ color }: CellProps) {
  const isGhost = typeof color === 'string' && color.startsWith('ghost:');
  const actualColor = isGhost ? color.split(':')[1] : color;

  let backgroundColor = '#1a1a2e';
  let border = '1px solid #333';
  let boxShadow: string | undefined;

  if (actualColor) {
    if (isGhost) {
      backgroundColor = `${actualColor}20`;
      border = `2px solid ${actualColor}88`;
    } else {
      backgroundColor = actualColor;
      boxShadow = 'inset 0 0 8px rgba(255,255,255,0.3), inset -2px -2px 4px rgba(0,0,0,0.3)';
      border = '1px solid rgba(255,255,255,0.15)';
    }
  }

  return (
    <div
      style={{
        width: CELL_SIZE,
        height: CELL_SIZE,
        backgroundColor,
        border,
        boxShadow,
        boxSizing: 'border-box',
      }}
    />
  );
}

interface GarbageMeterProps {
  count: number;
  cellSize: number;
  totalRows: number;
}

function GarbageMeter({ count, cellSize, totalRows }: GarbageMeterProps) {
  if (count === 0) return null;

  const meterHeight = Math.min(count, totalRows) * cellSize;
  const totalHeight = totalRows * cellSize;

  return (
    <div
      style={{
        width: 6,
        height: totalHeight,
        position: 'relative',
        marginRight: 2,
      }}
    >
      <div
        style={{
          position: 'absolute',
          bottom: 0,
          width: '100%',
          height: meterHeight,
          backgroundColor: '#ff4444',
          borderRadius: 2,
          transition: 'height 0.15s ease-out',
          boxShadow: '0 0 6px rgba(255, 68, 68, 0.6)',
        }}
      />
    </div>
  );
}

interface BoardProps {
  board: (string | null)[][];
  pendingGarbage?: number;
  events?: GameEvent[];
  dangerLevel?: DangerLevel;
}

export default function Board({ board, pendingGarbage = 0, events = [], dangerLevel = 'none' }: BoardProps) {
  const { boardClassName, overlays, dangerClassName, garbageMeterPulse } = useAnimations(events, dangerLevel, true);

  return (
    <div style={{ position: 'relative' }}>
      <div className="flex items-end">
        <div className={garbageMeterPulse ? 'anim-garbage-meter-pulse' : ''}>
          <GarbageMeter count={pendingGarbage} cellSize={CELL_SIZE} totalRows={BOARD_HEIGHT} />
        </div>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: `repeat(${String(BOARD_WIDTH)}, ${String(CELL_SIZE)}px)`,
            gridTemplateRows: `repeat(${String(BOARD_HEIGHT)}, ${String(CELL_SIZE)}px)`,
          }}
          className={`rounded-lg border border-glass-border bg-bg-cell shadow-[0_0_20px_rgba(124,108,255,0.15),inset_0_0_0_1px_rgba(255,255,255,0.04)] ${boardClassName}`}
        >
          {board.map((row, y) => row.map((cell, x) => <Cell key={`${String(y)}-${String(x)}`} color={cell} />))}
        </div>
      </div>

      {/* Danger zone overlay */}
      {dangerClassName && (
        <div
          className={dangerClassName}
          style={{
            position: 'absolute',
            inset: 0,
            borderRadius: 4,
            pointerEvents: 'none',
            zIndex: 1,
          }}
        />
      )}

      {/* Floating text overlays */}
      {overlays.map((overlay) => (
        <div
          key={overlay.id}
          className={overlay.className}
          style={{
            position: 'absolute',
            top: '40%',
            left: '50%',
            transform: 'translateX(-50%)',
            color: overlay.color,
            fontWeight: 'bold',
            fontSize: 24,
            textShadow: `0 0 10px ${overlay.color}`,
            pointerEvents: 'none',
            zIndex: 2,
            whiteSpace: 'nowrap',
          }}
        >
          {overlay.text}
        </div>
      ))}
    </div>
  );
}
