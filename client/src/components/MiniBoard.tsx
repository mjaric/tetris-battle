const MINI_CELL = 12;
const MINI_ROWS = 20;

interface MiniBoardProps {
  board: (string | null)[][];
  nickname: string;
  alive: boolean;
  isTarget: boolean;
  pendingGarbage?: number;
}

export default function MiniBoard({
  board,
  nickname,
  alive,
  isTarget,
  pendingGarbage = 0,
}: MiniBoardProps) {
  if (!board) return null;

  const meterHeight = Math.min(pendingGarbage, MINI_ROWS) * MINI_CELL;
  const totalHeight = MINI_ROWS * MINI_CELL;

  return (
    <div
      style={{ opacity: alive ? 1 : 0.3 }}
      className="mb-3"
    >
      <div
        className={`mb-1 text-center text-xs ${
          isTarget ? "font-bold text-cyan" : "text-muted"
        }`}
      >
        {nickname} {isTarget && "(TARGET)"}
      </div>
      <div className="flex items-end">
        {pendingGarbage > 0 && (
          <div
            style={{
              width: 4,
              height: totalHeight,
              position: "relative",
              marginRight: 1,
            }}
          >
            <div
              style={{
                position: "absolute",
                bottom: 0,
                width: "100%",
                height: meterHeight,
                backgroundColor: "#ff4444",
                borderRadius: 1,
                transition: "height 0.15s ease-out",
                boxShadow: "0 0 4px rgba(255, 68, 68, 0.6)",
              }}
            />
          </div>
        )}
        <div
          style={{
            display: "grid",
            gridTemplateColumns: `repeat(10, ${String(MINI_CELL)}px)`,
            gridTemplateRows: `repeat(20, ${String(MINI_CELL)}px)`,
          }}
          className={`rounded-sm bg-bg-cell ${
            isTarget
              ? "border-2 border-cyan"
              : "border border-border"
          }`}
        >
          {board.map((row, y) =>
            row.map((cell, x) => {
              const isGhost =
                typeof cell === "string" && cell.startsWith("ghost:");
              const bg = cell && !isGhost ? cell : "#1a1a2e";
              return (
                <div
                  key={`${String(y)}-${String(x)}`}
                  style={{
                    width: MINI_CELL,
                    height: MINI_CELL,
                    backgroundColor: bg,
                  }}
                />
              );
            }),
          )}
        </div>
      </div>
    </div>
  );
}
