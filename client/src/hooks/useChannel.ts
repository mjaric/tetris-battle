import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import type { Socket, Channel } from 'phoenix';

interface UseChannelResult {
  channel: Channel | null;
  joined: boolean;
  error: unknown;
  join: (params?: Record<string, unknown>) => Channel | undefined;
  leave: () => void;
}

export function useChannel(socket: Socket | null, topic: string | null): UseChannelResult {
  const [joined, setJoined] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const channelRef = useRef<Channel | null>(null);
  const [revision, setRevision] = useState(0);

  const join = useCallback(
    (params: Record<string, unknown> = {}) => {
      if (!socket || !topic) return;

      if (channelRef.current) {
        channelRef.current.leave();
      }

      const ch = socket.channel(topic, params);
      ch.join()
        .receive('ok', () => {
          setJoined(true);
          setError(null);
        })
        .receive('error', (resp: unknown) => {
          setError(resp);
          setJoined(false);
        });

      channelRef.current = ch;
      setRevision((r) => r + 1);
      return ch;
    },
    [socket, topic]
  );

  const leave = useCallback(() => {
    if (channelRef.current) {
      channelRef.current.leave();
      channelRef.current = null;
      setJoined(false);
      setRevision((r) => r + 1);
    }
  }, []);

  useEffect(() => {
    return () => {
      if (channelRef.current) {
        channelRef.current.leave();
        channelRef.current = null;
      }
    };
  }, []);

  const result = useMemo<UseChannelResult>(
    () => ({
      channel: channelRef.current,
      joined,
      error,
      join,
      leave,
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [joined, error, join, leave, revision]
  );

  return result;
}
