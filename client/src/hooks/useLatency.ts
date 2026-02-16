import { useState, useEffect, useRef } from "react";
import type { Channel } from "phoenix";

const PING_INTERVAL_MS = 2000;

export function useLatency(channel: Channel | null): number | null {
  const [latency, setLatency] = useState<number | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!channel) {
      setLatency(null);
      return;
    }

    function sendPing() {
      const start = performance.now();
      channel!
        .push("ping", {})
        .receive("ok", () => {
          setLatency(Math.round(performance.now() - start));
        });
    }

    sendPing();
    intervalRef.current = setInterval(sendPing, PING_INTERVAL_MS);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [channel]);

  return latency;
}
