import { useState, useCallback, useEffect, useRef } from 'react';
import {
  BOARD_WIDTH,
  BOARD_HEIGHT,
  TETROMINOES,
  TETROMINO_KEYS,
  TICK_SPEED_MS,
  SPEED_INCREMENT,
  LINES_PER_LEVEL,
  POINTS,
  WALL_KICKS,
} from '../constants.ts';
import type { GameEvent } from '../types.ts';
import { soundManager } from '../audio/SoundManager.ts';

type Cell = string | null;
type Board = Cell[][];

interface Piece {
  type: string;
  shape: number[][];
  color: string;
  rotation: number;
}

interface Position {
  x: number;
  y: number;
}

interface UseTetrisResult {
  board: Board;
  score: number;
  lines: number;
  level: number;
  nextPiece: Piece | null;
  gameOver: boolean;
  gameStarted: boolean;
  isPaused: boolean;
  startGame: () => void;
  togglePause: () => void;
  events: GameEvent[];
}

function createEmptyBoard(): Board {
  return Array.from({ length: BOARD_HEIGHT }, () => Array<Cell>(BOARD_WIDTH).fill(null));
}

function randomTetromino(): Piece {
  const key = TETROMINO_KEYS[Math.floor(Math.random() * TETROMINO_KEYS.length)]!;
  const def = TETROMINOES[key]!;
  return { type: key, shape: def.shape, color: def.color, rotation: 0 };
}

function rotateMatrix(matrix: number[][]): number[][] {
  const n = matrix.length;
  return matrix.map((row, i) => row.map((_, j) => matrix[n - 1 - j]![i]!));
}

function isValidPosition(board: Board, shape: number[][], pos: Position): boolean {
  for (let y = 0; y < shape.length; y++) {
    const row = shape[y]!;
    for (let x = 0; x < row.length; x++) {
      if (row[x]) {
        const newX = pos.x + x;
        const newY = pos.y + y;
        if (newX < 0 || newX >= BOARD_WIDTH || newY >= BOARD_HEIGHT) {
          return false;
        }
        if (newY < 0) continue;
        if (board[newY]![newX]) return false;
      }
    }
  }
  return true;
}

function placePiece(board: Board, piece: Piece, pos: Position): Board {
  const newBoard = board.map((row) => [...row]);
  piece.shape.forEach((row, y) => {
    row.forEach((cell, x) => {
      if (cell) {
        const boardY = pos.y + y;
        const boardX = pos.x + x;
        if (boardY >= 0 && boardY < BOARD_HEIGHT && boardX >= 0 && boardX < BOARD_WIDTH) {
          newBoard[boardY]![boardX] = piece.color;
        }
      }
    });
  });
  return newBoard;
}

function clearLines(board: Board): { board: Board; linesCleared: number } {
  const kept = board.filter((row) => row.some((cell) => cell === null));
  const cleared = BOARD_HEIGHT - kept.length;
  const emptyRows = Array.from({ length: cleared }, () => Array<Cell>(BOARD_WIDTH).fill(null));
  return { board: [...emptyRows, ...kept], linesCleared: cleared };
}

function getGhostPosition(board: Board, piece: Piece, pos: Position): Position {
  let ghostY = pos.y;
  while (isValidPosition(board, piece.shape, { x: pos.x, y: ghostY + 1 })) {
    ghostY++;
  }
  return { x: pos.x, y: ghostY };
}

export function useTetris(): UseTetrisResult {
  const [board, setBoard] = useState<Board>(createEmptyBoard);
  const [currentPiece, setCurrentPiece] = useState<Piece | null>(null);
  const [currentPos, setCurrentPos] = useState<Position>({ x: 0, y: 0 });
  const [nextPiece, setNextPiece] = useState<Piece | null>(null);
  const [score, setScore] = useState(0);
  const [lines, setLines] = useState(0);
  const [level, setLevel] = useState(1);
  const [gameOver, setGameOver] = useState(false);
  const [gameStarted, setGameStarted] = useState(false);
  const [isPaused, setIsPaused] = useState(false);

  const boardRef = useRef(board);
  const currentPieceRef = useRef(currentPiece);
  const currentPosRef = useRef(currentPos);
  const gameOverRef = useRef(gameOver);
  const isPausedRef = useRef(isPaused);
  const tickRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const levelRef = useRef(level);
  const [events, setEvents] = useState<GameEvent[]>([]);
  const comboRef = useRef(0);
  const lastWasTetrisRef = useRef(false);

  boardRef.current = board;
  currentPieceRef.current = currentPiece;
  currentPosRef.current = currentPos;
  gameOverRef.current = gameOver;
  isPausedRef.current = isPaused;
  levelRef.current = level;

  const spawnPiece = useCallback((piece: Piece) => {
    const startX = Math.floor((BOARD_WIDTH - piece.shape[0]!.length) / 2);
    const startY = -1;

    if (
      !isValidPosition(boardRef.current, piece.shape, {
        x: startX,
        y: startY + 1,
      })
    ) {
      setGameOver(true);
      return;
    }

    setCurrentPiece({ ...piece });
    setCurrentPos({ x: startX, y: startY });
  }, []);

  const lockPiece = useCallback(() => {
    const piece = currentPieceRef.current;
    const pos = currentPosRef.current;
    if (!piece) return;

    const newBoard = placePiece(boardRef.current, piece, pos);
    const { board: clearedBoard, linesCleared } = clearLines(newBoard);

    setBoard(clearedBoard);

    // Generate events
    const newEvents: GameEvent[] = [];

    if (linesCleared > 0) {
      newEvents.push({ type: 'line_clear', count: linesCleared });

      // Combo tracking
      comboRef.current += 1;
      if (comboRef.current >= 2) {
        newEvents.push({ type: 'combo', count: comboRef.current });
      }

      // B2B Tetris tracking
      const isTetris = linesCleared === 4;
      if (lastWasTetrisRef.current && isTetris) {
        newEvents.push({ type: 'b2b_tetris' });
      }
      lastWasTetrisRef.current = isTetris;

      setLines((prev) => {
        const newLines = prev + linesCleared;
        const newLevel = Math.floor(newLines / LINES_PER_LEVEL) + 1;
        setLevel(newLevel);
        return newLines;
      });
      const pointValue = POINTS[linesCleared as keyof typeof POINTS] ?? 0;
      setScore((prev) => prev + pointValue * levelRef.current);
    } else {
      // Reset combo on no-clear lock
      comboRef.current = 0;
      lastWasTetrisRef.current = false;
    }

    if (newEvents.length > 0) {
      setEvents(newEvents);
      // Clear events after a short delay so they're consumed once
      setTimeout(() => setEvents([]), 50);
    }

    const next = nextPiece ?? randomTetromino();
    setNextPiece(randomTetromino());
    spawnPiece(next);
  }, [nextPiece, spawnPiece]);

  const moveDown = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) {
      return;
    }
    const newPos = {
      x: currentPosRef.current.x,
      y: currentPosRef.current.y + 1,
    };
    if (isValidPosition(boardRef.current, currentPieceRef.current.shape, newPos)) {
      setCurrentPos(newPos);
    } else {
      lockPiece();
    }
  }, [lockPiece]);

  const moveLeft = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) {
      return;
    }
    const newPos = {
      x: currentPosRef.current.x - 1,
      y: currentPosRef.current.y,
    };
    if (isValidPosition(boardRef.current, currentPieceRef.current.shape, newPos)) {
      setCurrentPos(newPos);
    }
  }, []);

  const moveRight = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) {
      return;
    }
    const newPos = {
      x: currentPosRef.current.x + 1,
      y: currentPosRef.current.y,
    };
    if (isValidPosition(boardRef.current, currentPieceRef.current.shape, newPos)) {
      setCurrentPos(newPos);
    }
  }, []);

  const rotatePiece = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) {
      return;
    }
    const piece = currentPieceRef.current;
    const pos = currentPosRef.current;
    const rotated = rotateMatrix(piece.shape);
    const newRotation = (piece.rotation + 1) % 4;
    const kickKey = `${String(piece.rotation)}>${String(newRotation)}`;
    const kicks = piece.type === 'I' ? WALL_KICKS.I : WALL_KICKS.normal;
    const kickTests = kicks[kickKey] ?? [[0, 0]];

    for (const kick of kickTests) {
      const [dx, dy] = kick!;
      const newPos = { x: pos.x + dx!, y: pos.y - dy! };
      if (isValidPosition(boardRef.current, rotated, newPos)) {
        setCurrentPiece({
          ...piece,
          shape: rotated,
          rotation: newRotation,
        });
        setCurrentPos(newPos);
        return;
      }
    }
  }, []);

  const hardDrop = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) {
      return;
    }
    const ghost = getGhostPosition(boardRef.current, currentPieceRef.current, currentPosRef.current);
    const dropDistance = ghost.y - currentPosRef.current.y;
    setScore((prev) => prev + dropDistance * 2);
    setCurrentPos(ghost);

    // Emit hard_drop event
    if (dropDistance > 0) {
      setEvents((prev) => [...prev, { type: 'hard_drop', distance: dropDistance }]);
    }

    setTimeout(() => lockPiece(), 0);
  }, [lockPiece]);

  const togglePause = useCallback(() => {
    if (gameOverRef.current || !gameStarted) return;
    setIsPaused((prev) => !prev);
  }, [gameStarted]);

  const startGame = useCallback(() => {
    const emptyBoard = createEmptyBoard();
    setBoard(emptyBoard);
    boardRef.current = emptyBoard;
    setScore(0);
    setLines(0);
    setLevel(1);
    setGameOver(false);
    setIsPaused(false);
    setGameStarted(true);
    comboRef.current = 0;
    lastWasTetrisRef.current = false;
    setEvents([]);

    const first = randomTetromino();
    const next = randomTetromino();
    setNextPiece(next);
    spawnPiece(first);
  }, [spawnPiece]);

  useEffect(() => {
    if (!gameStarted || gameOver || isPaused) {
      if (tickRef.current) clearInterval(tickRef.current);
      return;
    }

    const speed = Math.max(100, TICK_SPEED_MS - (level - 1) * SPEED_INCREMENT);
    tickRef.current = setInterval(moveDown, speed);

    return () => {
      if (tickRef.current) clearInterval(tickRef.current);
    };
  }, [gameStarted, gameOver, isPaused, level, moveDown]);

  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (!gameStarted) return;

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault();
          moveLeft();
          soundManager.playMove();
          break;
        case 'ArrowRight':
          e.preventDefault();
          moveRight();
          soundManager.playMove();
          break;
        case 'ArrowDown':
          e.preventDefault();
          moveDown();
          soundManager.playSoftDrop();
          break;
        case 'ArrowUp':
          e.preventDefault();
          rotatePiece();
          soundManager.playRotate();
          break;
        case ' ':
          e.preventDefault();
          hardDrop();
          break;
        case 'p':
        case 'P':
          togglePause();
          break;
      }
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [gameStarted, moveLeft, moveRight, moveDown, rotatePiece, hardDrop, togglePause]);

  const displayBoard: Board = board.map((row) => [...row]);

  if (currentPiece && !gameOver) {
    const ghostPos = getGhostPosition(board, currentPiece, currentPos);
    currentPiece.shape.forEach((row, y) => {
      row.forEach((cell, x) => {
        if (cell) {
          const boardY = ghostPos.y + y;
          const boardX = ghostPos.x + x;
          if (boardY >= 0 && boardY < BOARD_HEIGHT && boardX >= 0 && boardX < BOARD_WIDTH) {
            if (!displayBoard[boardY]![boardX]) {
              displayBoard[boardY]![boardX] = `ghost:${currentPiece.color}`;
            }
          }
        }
      });
    });

    currentPiece.shape.forEach((row, y) => {
      row.forEach((cell, x) => {
        if (cell) {
          const boardY = currentPos.y + y;
          const boardX = currentPos.x + x;
          if (boardY >= 0 && boardY < BOARD_HEIGHT && boardX >= 0 && boardX < BOARD_WIDTH) {
            displayBoard[boardY]![boardX] = currentPiece.color;
          }
        }
      });
    });
  }

  return {
    board: displayBoard,
    score,
    lines,
    level,
    nextPiece,
    gameOver,
    gameStarted,
    isPaused,
    startGame,
    togglePause,
    events,
  };
}
