import NextPiece from "./NextPiece.tsx";
import StatBox from "./StatBox.tsx";

interface SidebarProps {
  score: number;
  lines: number;
  level: number;
  nextPiece: { shape: number[][]; color: string } | null;
}

export default function Sidebar({
  score,
  lines,
  level,
  nextPiece,
}: SidebarProps) {
  return (
    <div className="ml-6 min-w-35 rounded-lg border border-border bg-bg-secondary p-5">
      <NextPiece piece={nextPiece} />
      <StatBox label="Score" value={score} />
      <StatBox label="Lines" value={lines} />
      <StatBox label="Level" value={level} />

      <div className="mt-6 border-t border-border pt-4">
        <h3 className="m-0 mb-2.5 text-xs uppercase tracking-widest text-gray-400">
          Controls
        </h3>
        <div className="text-xs leading-7 text-gray-600">
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
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="mr-1.5 inline-block rounded border border-gray-700 bg-bg-elevated px-1.5 py-px font-mono text-xs text-gray-400">
      {children}
    </kbd>
  );
}
