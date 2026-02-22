import NextPiece from './NextPiece.tsx';
import { GlassCard, Stat, Divider } from './ui/index.ts';

interface SidebarProps {
  score: number;
  lines: number;
  level: number;
  nextPiece: { shape: number[][]; color: string } | null;
}

export default function Sidebar({ score, lines, level, nextPiece }: SidebarProps) {
  return (
    <GlassCard variant="elevated" padding="md" className="ml-6 min-w-35">
      <NextPiece piece={nextPiece} />
      <Divider className="my-3" />
      <div className="space-y-3">
        <Stat label="Score" value={score.toLocaleString()} />
        <Stat label="Lines" value={lines} />
        <Stat label="Level" value={level} />
      </div>
      <Divider className="my-3" />
      <div>
        <h3 className="mb-2.5 text-xs uppercase tracking-widest text-text-muted">Controls</h3>
        <div className="text-xs leading-7 text-text-muted">
          <div>
            <Kbd>&larr; &rarr;</Kbd> Move
          </div>
          <div>
            <Kbd>&uarr;</Kbd> Rotate
          </div>
          <div>
            <Kbd>&darr;</Kbd> Soft drop
          </div>
          <div>
            <Kbd>Space</Kbd> Hard drop
          </div>
          <div>
            <Kbd>P</Kbd> Pause
          </div>
        </div>
      </div>
    </GlassCard>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="mr-1.5 inline-block rounded border border-glass-border bg-bg-elevated px-1.5 py-px font-mono text-xs text-text-muted">
      {children}
    </kbd>
  );
}
