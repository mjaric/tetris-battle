import { useState, useEffect, useRef } from 'react';
import { Socket, type Channel } from 'phoenix';

const SOCKET_URL = import.meta.env['VITE_SOCKET_URL'] ?? 'ws://localhost:4000/socket';

interface UseSocketResult {
  socket: Socket | null;
  connected: boolean;
  playerId: string | null;
  lobbyChannel: Channel | null;
}

export function useSocket(nickname: string | null): UseSocketResult {
  const [socket, setSocket] = useState<Socket | null>(null);
  const [connected, setConnected] = useState(false);
  const [playerId, setPlayerId] = useState<string | null>(null);
  const [lobbyChannel, setLobbyChannel] = useState<Channel | null>(null);
  const socketRef = useRef<Socket | null>(null);
  const lobbyRef = useRef<Channel | null>(null);

  useEffect(() => {
    if (!nickname) return;

    const s = new Socket(SOCKET_URL, { params: { nickname } });
    s.connect();
    s.onOpen(() => setConnected(true));
    s.onClose(() => setConnected(false));
    socketRef.current = s;
    setSocket(s);

    const lobby = s.channel('lobby:main', {});
    lobby.join().receive('ok', (resp: { player_id: string }) => {
      setPlayerId(resp.player_id);
    });
    lobbyRef.current = lobby;
    setLobbyChannel(lobby);

    return () => {
      lobby.leave();
      lobbyRef.current = null;
      setLobbyChannel(null);
      s.disconnect();
      socketRef.current = null;
      setSocket(null);
      setConnected(false);
      setPlayerId(null);
    };
  }, [nickname]);

  return { socket, connected, playerId, lobbyChannel };
}
