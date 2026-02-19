export type GameEvent =
  | { type: 'hard_drop'; distance: number }
  | { type: 'line_clear'; count: number }
  | { type: 'combo'; count: number }
  | { type: 'b2b_tetris' }
  | { type: 'garbage_sent'; target: string; count: number }
  | { type: 'garbage_received'; count: number }
  | { type: 'elimination' };

export interface PlayerBroadcast {
  nickname: string;
  board: (string | null)[][];
  score: number;
  lines: number;
  level: number;
  alive: boolean;
  next_piece: string | null;
  target: string | null;
  pending_garbage: number;
  is_bot?: boolean;
  events: GameEvent[];
}

export interface GameState {
  tick: number;
  status: 'waiting' | 'playing' | 'finished';
  players: Record<string, PlayerBroadcast>;
  eliminated_order: string[];
  host: string;
}

export interface RoomInfo {
  room_id: string;
  name: string;
  host: string;
  max_players: number;
  player_count: number;
  status: 'waiting' | 'playing' | 'finished';
}
