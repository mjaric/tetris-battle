import { useState, useEffect, useRef, useCallback } from 'react';
import { Socket } from 'phoenix';

const SOCKET_URL = process.env.REACT_APP_SOCKET_URL || 'ws://localhost:4000/socket';

export function useSocket(nickname) {
  const [socket, setSocket] = useState(null);
  const [connected, setConnected] = useState(false);
  const [playerId, setPlayerId] = useState(null);
  const socketRef = useRef(null);

  useEffect(() => {
    if (!nickname) return;

    const s = new Socket(SOCKET_URL, { params: { nickname } });
    s.connect();
    s.onOpen(() => setConnected(true));
    s.onClose(() => setConnected(false));
    socketRef.current = s;
    setSocket(s);

    return () => {
      s.disconnect();
    };
  }, [nickname]);

  return { socket, connected, playerId };
}

export function useChannel(socket, topic) {
  const [channel, setChannel] = useState(null);
  const [joined, setJoined] = useState(false);
  const [error, setError] = useState(null);
  const channelRef = useRef(null);

  const join = useCallback((params = {}) => {
    if (!socket || !topic) return;

    const ch = socket.channel(topic, params);
    ch.join()
      .receive('ok', (resp) => {
        setJoined(true);
        setError(null);
      })
      .receive('error', (resp) => {
        setError(resp);
        setJoined(false);
      });

    channelRef.current = ch;
    setChannel(ch);

    return ch;
  }, [socket, topic]);

  const leave = useCallback(() => {
    if (channelRef.current) {
      channelRef.current.leave();
      channelRef.current = null;
      setChannel(null);
      setJoined(false);
    }
  }, []);

  useEffect(() => {
    return () => {
      if (channelRef.current) {
        channelRef.current.leave();
      }
    };
  }, []);

  return { channel, joined, error, join, leave };
}
