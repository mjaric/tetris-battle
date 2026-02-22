import { useEffect, useRef } from 'react';

interface RenderStats {
  fps: number;
  boardRenders: number;
  elapsed: number;
}

export function useRenderStats(label: string, boardCount: number): void {
  const frameCountRef = useRef(0);
  const boardRenderCountRef = useRef(0);
  const lastLogRef = useRef(performance.now());
  const rafRef = useRef(0);

  boardRenderCountRef.current += boardCount;

  useEffect(() => {
    if (!import.meta.env.DEV) return;

    let running = true;

    function tick() {
      if (!running) return;
      frameCountRef.current++;
      rafRef.current = requestAnimationFrame(tick);
    }

    rafRef.current = requestAnimationFrame(tick);

    const interval = setInterval(() => {
      const now = performance.now();
      const elapsed = (now - lastLogRef.current) / 1000;
      const stats: RenderStats = {
        fps: Math.round(frameCountRef.current / elapsed),
        boardRenders: boardRenderCountRef.current,
        elapsed: Math.round(elapsed * 10) / 10,
      };

      console.log(
        `[${label}] FPS: ${String(stats.fps)} | ` +
          `Board renders: ${String(stats.boardRenders)} ` +
          `(${String(Math.round(stats.boardRenders / elapsed))}/s) | ` +
          `${String(stats.elapsed)}s`
      );

      frameCountRef.current = 0;
      boardRenderCountRef.current = 0;
      lastLogRef.current = now;
    }, 5000);

    return () => {
      running = false;
      cancelAnimationFrame(rafRef.current);
      clearInterval(interval);
    };
  }, [label]);
}
