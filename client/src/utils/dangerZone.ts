export type DangerLevel = 'none' | 'low' | 'medium' | 'critical';

/**
 * Compute danger level from board fill percentage.
 * Only counts non-null cells in the top portion of the board.
 */
export function computeDangerLevel(board: (string | null)[][]): DangerLevel {
  if (!board || board.length === 0) return 'none';

  const totalCells = board.length * board[0].length;
  let filledCells = 0;

  for (const row of board) {
    for (const cell of row) {
      if (cell !== null) filledCells++;
    }
  }

  const fillPercent = filledCells / totalCells;

  if (fillPercent >= 0.85) return 'critical';
  if (fillPercent >= 0.75) return 'medium';
  if (fillPercent >= 0.60) return 'low';
  return 'none';
}
