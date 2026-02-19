import { useState, useEffect, useRef } from 'react';
import type { GameEvent } from '../types';
import type { DangerLevel } from '../utils/dangerZone';

interface FloatingText {
  id: string;
  text: string;
  color: string;
  className: string;
}

interface AnimationState {
  boardClassName: string;
  overlays: FloatingText[];
  dangerClassName: string;
  garbageMeterPulse: boolean;
}

const MAX_CONCURRENT = 5;

export function useAnimations(
  events: GameEvent[],
  dangerLevel: DangerLevel,
  isMe: boolean
): AnimationState {
  const [activeAnims, setActiveAnims] = useState<string[]>([]);
  const [overlays, setOverlays] = useState<FloatingText[]>([]);
  const [garbageMeterPulse, setGarbageMeterPulse] = useState(false);
  const overlayIdRef = useRef(0);

  useEffect(() => {
    if (events.length === 0) return;

    const newAnims: string[] = [];
    const newOverlays: FloatingText[] = [];
    const timeouts: ReturnType<typeof setTimeout>[] = [];

    for (const event of events) {
      switch (event.type) {
        case 'hard_drop': {
          if (isMe) {
            const shake = event.distance > 10 ? 'anim-shake-lg' : event.distance > 5 ? 'anim-shake-md' : 'anim-shake-sm';
            newAnims.push(shake);
          }
          break;
        }
        case 'line_clear': {
          if (event.count === 4) {
            newAnims.push('anim-tetris');
            if (isMe) {
              overlayIdRef.current++;
              newOverlays.push({
                id: `tetris-${String(overlayIdRef.current)}`,
                text: 'TETRIS!',
                color: '#ffd700',
                className: 'anim-float-up',
              });
            }
          } else {
            newAnims.push(isMe ? 'anim-line-clear' : '');
          }
          break;
        }
        case 'combo': {
          if (isMe) {
            overlayIdRef.current++;
            newOverlays.push({
              id: `combo-${String(overlayIdRef.current)}`,
              text: `x${String(event.count)} COMBO`,
              color: '#00f0f0',
              className: 'anim-float-up',
            });
          }
          break;
        }
        case 'b2b_tetris': {
          newAnims.push('anim-b2b-aura');
          if (isMe) {
            overlayIdRef.current++;
            newOverlays.push({
              id: `b2b-${String(overlayIdRef.current)}`,
              text: 'B2B TETRIS',
              color: '#ffd700',
              className: 'anim-float-up',
            });
          }
          break;
        }
        case 'garbage_sent': {
          if (isMe) {
            newAnims.push('anim-garbage-sent');
            overlayIdRef.current++;
            newOverlays.push({
              id: `gsent-${String(overlayIdRef.current)}`,
              text: `+${String(event.count)}`,
              color: '#00f0f0',
              className: 'anim-float-up',
            });
          }
          break;
        }
        case 'garbage_received': {
          newAnims.push(isMe ? 'anim-garbage-slam' : '');
          if (isMe) {
            setGarbageMeterPulse(true);
            const t = setTimeout(() => setGarbageMeterPulse(false), 600);
            timeouts.push(t);
          }
          break;
        }
        case 'elimination': {
          newAnims.push('anim-elim-flash');
          break;
        }
      }
    }

    // Limit concurrent animations
    const limitedAnims = newAnims.filter(Boolean).slice(0, MAX_CONCURRENT);
    setActiveAnims(limitedAnims);

    // Add overlays (only for own board)
    if (newOverlays.length > 0) {
      setOverlays((prev) => [...prev, ...newOverlays].slice(-MAX_CONCURRENT));
    }

    // Clean up animations after their duration
    const animTimeout = setTimeout(() => {
      setActiveAnims([]);
    }, 500);
    timeouts.push(animTimeout);

    // Clean up overlays after float-up duration
    const overlayTimeout = setTimeout(() => {
      setOverlays((prev) =>
        prev.filter((o) => !newOverlays.some((n) => n.id === o.id))
      );
    }, 800);
    timeouts.push(overlayTimeout);

    return () => {
      timeouts.forEach(clearTimeout);
    };
  }, [events, isMe]);

  // Danger zone class
  let dangerClassName = '';
  if (isMe) {
    switch (dangerLevel) {
      case 'low':
        dangerClassName = 'anim-danger-pulse';
        break;
      case 'medium':
        dangerClassName = 'anim-danger-pulse';
        break;
      case 'critical':
        dangerClassName = 'anim-danger-pulse-fast';
        break;
    }
  }

  const boardClassName = activeAnims.join(' ');

  return {
    boardClassName,
    overlays,
    dangerClassName,
    garbageMeterPulse,
  };
}
