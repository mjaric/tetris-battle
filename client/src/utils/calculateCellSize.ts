const OUTER_PADDING = 32;
const GARBAGE_METER_EXTRA = 10;
const BORDER_EXTRA = 6;
const BOARD_COLUMNS = 10;
const GAP_PX = 12;
const MIN_CELL = 8;
const MAX_CELL = 42;

export function calculateCellSize(
  playerCount: number,
  viewportWidth: number,
): number {
  const availableWidth = viewportWidth - OUTER_PADDING;
  const totalGaps = Math.max(0, playerCount - 1) * GAP_PX;
  const perBoard = (availableWidth - totalGaps) / playerCount;
  const raw = Math.floor(
    (perBoard - GARBAGE_METER_EXTRA - BORDER_EXTRA) /
      BOARD_COLUMNS,
  );
  return Math.max(MIN_CELL, Math.min(MAX_CELL, raw));
}
