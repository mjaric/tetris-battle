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
}

export interface GameState {
  tick: number;
  status: "waiting" | "playing" | "finished";
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
  status: "waiting" | "playing" | "finished";
}
