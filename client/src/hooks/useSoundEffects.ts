import { useEffect } from 'react';
import type { GameEvent } from '../types';
import { soundManager } from '../audio/SoundManager';

export function useSoundEffects(events: GameEvent[]): void {
  useEffect(() => {
    if (events.length === 0) return;

    for (const event of events) {
      switch (event.type) {
        case 'hard_drop':
          soundManager.playHardDrop(event.distance);
          break;
        case 'line_clear':
          soundManager.playLineClear(event.count);
          break;
        case 'combo':
          soundManager.playCombo(event.count);
          break;
        case 'b2b_tetris':
          soundManager.playB2B();
          break;
        case 'garbage_sent':
          soundManager.playGarbageSent();
          break;
        case 'garbage_received':
          soundManager.playGarbageReceived();
          break;
        case 'elimination':
          soundManager.playElimination();
          break;
      }
    }
  }, [events]);
}
