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
} from '../constants';

function createEmptyBoard() {
  return Array.from({ length: BOARD_HEIGHT }, () => Array(BOARD_WIDTH).fill(null));
}

function randomTetromino() {
  const key = TETROMINO_KEYS[Math.floor(Math.random() * TETROMINO_KEYS.length)];
  return { type: key, ...TETROMINOES[key], rotation: 0 };
}

function rotate(matrix) {
  const N = matrix.length;
  const rotated = matrix.map((row, i) => row.map((_, j) => matrix[N - 1 - j][i]));
  return rotated;
}

function isValidPosition(board, shape, pos) {
  for (let y = 0; y < shape.length; y++) {
    for (let x = 0; x < shape[y].length; x++) {
      if (shape[y][x]) {
        const newX = pos.x + x;
        const newY = pos.y + y;
        if (newX < 0 || newX >= BOARD_WIDTH || newY >= BOARD_HEIGHT) return false;
        if (newY < 0) continue;
        if (board[newY][newX]) return false;
      }
    }
  }
  return true;
}

function placePiece(board, piece, pos) {
  const newBoard = board.map(row => [...row]);
  piece.shape.forEach((row, y) => {
    row.forEach((cell, x) => {
      if (cell) {
        const boardY = pos.y + y;
        const boardX = pos.x + x;
        if (boardY >= 0 && boardY < BOARD_HEIGHT && boardX >= 0 && boardX < BOARD_WIDTH) {
          newBoard[boardY][boardX] = piece.color;
        }
      }
    });
  });
  return newBoard;
}

function clearLines(board) {
  const newBoard = board.filter(row => row.some(cell => cell === null));
  const cleared = BOARD_HEIGHT - newBoard.length;
  const emptyRows = Array.from({ length: cleared }, () => Array(BOARD_WIDTH).fill(null));
  return { board: [...emptyRows, ...newBoard], linesCleared: cleared };
}

function getGhostPosition(board, piece, pos) {
  let ghostY = pos.y;
  while (isValidPosition(board, piece.shape, { x: pos.x, y: ghostY + 1 })) {
    ghostY++;
  }
  return { x: pos.x, y: ghostY };
}

export default function useTetris() {
  const [board, setBoard] = useState(createEmptyBoard);
  const [currentPiece, setCurrentPiece] = useState(null);
  const [currentPos, setCurrentPos] = useState({ x: 0, y: 0 });
  const [nextPiece, setNextPiece] = useState(null);
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
  const tickRef = useRef(null);
  const levelRef = useRef(level);

  boardRef.current = board;
  currentPieceRef.current = currentPiece;
  currentPosRef.current = currentPos;
  gameOverRef.current = gameOver;
  isPausedRef.current = isPaused;
  levelRef.current = level;

  const spawnPiece = useCallback((piece) => {
    const startX = Math.floor((BOARD_WIDTH - piece.shape[0].length) / 2);
    const startY = -1;

    if (!isValidPosition(boardRef.current, piece.shape, { x: startX, y: startY + 1 })) {
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

    if (linesCleared > 0) {
      setLines(prev => {
        const newLines = prev + linesCleared;
        const newLevel = Math.floor(newLines / LINES_PER_LEVEL) + 1;
        setLevel(newLevel);
        return newLines;
      });
      setScore(prev => prev + (POINTS[linesCleared] || 0) * levelRef.current);
    }

    const next = nextPiece || randomTetromino();
    setNextPiece(randomTetromino());
    spawnPiece(next);
  }, [nextPiece, spawnPiece]);

  const moveDown = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) return;

    const newPos = { x: currentPosRef.current.x, y: currentPosRef.current.y + 1 };
    if (isValidPosition(boardRef.current, currentPieceRef.current.shape, newPos)) {
      setCurrentPos(newPos);
    } else {
      lockPiece();
    }
  }, [lockPiece]);

  const moveLeft = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) return;
    const newPos = { x: currentPosRef.current.x - 1, y: currentPosRef.current.y };
    if (isValidPosition(boardRef.current, currentPieceRef.current.shape, newPos)) {
      setCurrentPos(newPos);
    }
  }, []);

  const moveRight = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) return;
    const newPos = { x: currentPosRef.current.x + 1, y: currentPosRef.current.y };
    if (isValidPosition(boardRef.current, currentPieceRef.current.shape, newPos)) {
      setCurrentPos(newPos);
    }
  }, []);

  const rotatePiece = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) return;

    const piece = currentPieceRef.current;
    const pos = currentPosRef.current;
    const rotated = rotate(piece.shape);
    const newRotation = (piece.rotation + 1) % 4;
    const kickKey = `${piece.rotation}>${newRotation}`;
    const kicks = piece.type === 'I' ? WALL_KICKS.I : WALL_KICKS.normal;
    const kickTests = kicks[kickKey] || [[0, 0]];

    for (const [dx, dy] of kickTests) {
      const newPos = { x: pos.x + dx, y: pos.y - dy };
      if (isValidPosition(boardRef.current, rotated, newPos)) {
        setCurrentPiece({ ...piece, shape: rotated, rotation: newRotation });
        setCurrentPos(newPos);
        return;
      }
    }
  }, []);

  const hardDrop = useCallback(() => {
    if (gameOverRef.current || isPausedRef.current || !currentPieceRef.current) return;
    const ghost = getGhostPosition(boardRef.current, currentPieceRef.current, currentPosRef.current);
    const dropDistance = ghost.y - currentPosRef.current.y;
    setScore(prev => prev + dropDistance * 2);
    setCurrentPos(ghost);
    // Lock immediately on next tick
    setTimeout(() => lockPiece(), 0);
  }, [lockPiece]);

  const togglePause = useCallback(() => {
    if (gameOverRef.current || !gameStarted) return;
    setIsPaused(prev => !prev);
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

    const first = randomTetromino();
    const next = randomTetromino();
    setNextPiece(next);
    spawnPiece(first);
  }, [spawnPiece]);

  // Game tick
  useEffect(() => {
    if (!gameStarted || gameOver || isPaused) {
      if (tickRef.current) clearInterval(tickRef.current);
      return;
    }

    const speed = Math.max(100, TICK_SPEED_MS - (level - 1) * SPEED_INCREMENT);
    tickRef.current = setInterval(moveDown, speed);

    return () => clearInterval(tickRef.current);
  }, [gameStarted, gameOver, isPaused, level, moveDown]);

  // Keyboard controls
  useEffect(() => {
    const handleKeyDown = (e) => {
      if (!gameStarted) return;

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault();
          moveLeft();
          break;
        case 'ArrowRight':
          e.preventDefault();
          moveRight();
          break;
        case 'ArrowDown':
          e.preventDefault();
          moveDown();
          break;
        case 'ArrowUp':
          e.preventDefault();
          rotatePiece();
          break;
        case ' ':
          e.preventDefault();
          hardDrop();
          break;
        case 'p':
        case 'P':
          togglePause();
          break;
        default:
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [gameStarted, moveLeft, moveRight, moveDown, rotatePiece, hardDrop, togglePause]);

  // Build display board with current piece and ghost
  const displayBoard = board.map(row => [...row]);

  if (currentPiece && !gameOver) {
    // Draw ghost
    const ghostPos = getGhostPosition(board, currentPiece, currentPos);
    currentPiece.shape.forEach((row, y) => {
      row.forEach((cell, x) => {
        if (cell) {
          const boardY = ghostPos.y + y;
          const boardX = ghostPos.x + x;
          if (boardY >= 0 && boardY < BOARD_HEIGHT && boardX >= 0 && boardX < BOARD_WIDTH) {
            if (!displayBoard[boardY][boardX]) {
              displayBoard[boardY][boardX] = `ghost:${currentPiece.color}`;
            }
          }
        }
      });
    });

    // Draw current piece
    currentPiece.shape.forEach((row, y) => {
      row.forEach((cell, x) => {
        if (cell) {
          const boardY = currentPos.y + y;
          const boardX = currentPos.x + x;
          if (boardY >= 0 && boardY < BOARD_HEIGHT && boardX >= 0 && boardX < BOARD_WIDTH) {
            displayBoard[boardY][boardX] = currentPiece.color;
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
  };
}
