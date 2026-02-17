import { BOARD_WIDTH, BOARD_HEIGHT } from "../constants.ts";

type GlowLevel = "self" | "target" | "other" | "eliminated";

interface PlayerBoardProps {
  board: (string | null)[][];
  cellSize: number;
  nickname: string;
  score: number;
  lines: number;
  pendingGarbage: number;
  playerHue: number;
  glowLevel: GlowLevel;
  isMe: boolean;
  nextPiece?: { shape: number[][]; color: string } | null | undefined;
  targetNickname?: string | undefined;
  level?: number | undefined;
  latency?: number | null | undefined;
}

interface PlayerCellProps {
  color: string | null;
  size: number;
}

function PlayerCell({ color, size }: PlayerCellProps) {
  const isGhost =
    typeof color === "string" && color.startsWith("ghost:");
  const actualColor = isGhost ? color.split(":")[1] : color;
  const showInset = size > 16;

  let backgroundColor = "#1a1a2e";
  let border = "1px solid #333";
  let boxShadow: string | undefined;

  if (actualColor) {
    if (isGhost) {
      border = `1px dashed ${actualColor}55`;
    } else {
      backgroundColor = actualColor;
      if (showInset) {
        boxShadow =
          "inset 0 0 8px rgba(255,255,255,0.3), " +
          "inset -2px -2px 4px rgba(0,0,0,0.3)";
      }
      border = "1px solid rgba(255,255,255,0.15)";
    }
  }

  return (
    <div
      style={{
        width: size,
        height: size,
        backgroundColor,
        border,
        boxShadow,
        boxSizing: "border-box",
      }}
    />
  );
}

interface GarbageMeterProps {
  count: number;
  cellSize: number;
  totalRows: number;
}

function GarbageMeter({
  count,
  cellSize,
  totalRows,
}: GarbageMeterProps) {
  if (count === 0) return null;

  const meterWidth = Math.max(3, Math.round(cellSize * 0.2));
  const meterHeight = Math.min(count, totalRows) * cellSize;
  const totalHeight = totalRows * cellSize;

  return (
    <div
      style={{
        width: meterWidth,
        height: totalHeight,
        position: "relative",
        marginRight: Math.max(1, Math.round(cellSize * 0.07)),
      }}
    >
      <div
        style={{
          position: "absolute",
          bottom: 0,
          width: "100%",
          height: meterHeight,
          backgroundColor: "#ff4444",
          borderRadius: Math.max(1, Math.round(meterWidth / 3)),
          transition: "height 0.15s ease-out",
          boxShadow: "0 0 6px rgba(255, 68, 68, 0.6)",
        }}
      />
    </div>
  );
}

function glowStyles(
  hue: number,
  level: GlowLevel,
): React.CSSProperties {
  const h = hue;

  switch (level) {
    case "self":
      return {
        border: `3px solid hsl(${String(h)}, 70%, 60%)`,
        boxShadow:
          `0 0 40px 10px hsla(${String(h)}, 70%, 50%, 0.4), ` +
          `0 0 80px 20px hsla(${String(h)}, 70%, 50%, 0.2)`,
        opacity: 1.0,
      };
    case "target":
      return {
        border: `2px solid hsla(${String(h)}, 70%, 60%, 0.7)`,
        boxShadow:
          `0 0 25px 5px hsla(${String(h)}, 70%, 50%, 0.25)`,
        opacity: 0.9,
      };
    case "other":
      return {
        border: `1px solid hsla(${String(h)}, 70%, 60%, 0.3)`,
        boxShadow:
          `0 0 10px 2px hsla(${String(h)}, 70%, 50%, 0.08)`,
        opacity: 0.5,
      };
    case "eliminated":
      return {
        border: "1px solid hsla(0, 0%, 50%, 0.1)",
        boxShadow: "none",
        opacity: 0.2,
        filter: "grayscale(1)",
      };
  }
}

function MiniNextPiece({
  piece,
  hudCell,
}: {
  piece: { shape: number[][]; color: string };
  hudCell: number;
}) {
  const cols = piece.shape[0]?.length ?? 0;

  return (
    <div
      style={{
        display: "inline-grid",
        gridTemplateColumns: `repeat(${String(cols)}, ${String(hudCell)}px)`,
        gap: 1,
      }}
    >
      {piece.shape.map((row, y) =>
        row.map((cell, x) => (
          <div
            key={`${String(y)}-${String(x)}`}
            style={{
              width: hudCell,
              height: hudCell,
              backgroundColor: cell ? piece.color : "transparent",
              borderRadius: 2,
              boxShadow: cell
                ? "inset 0 0 4px rgba(255,255,255,0.3)"
                : "none",
            }}
          />
        )),
      )}
    </div>
  );
}

function LatencyBadge({ latency }: { latency: number }) {
  const colorClass =
    latency < 80
      ? "text-green"
      : latency < 150
        ? "text-amber"
        : "text-red";

  return (
    <>
      <span style={{ margin: "0 6px", color: "#555" }}>|</span>
      <span style={{ color: "#888" }}>Ping: </span>
      <span className={colorClass}>{latency}ms</span>
    </>
  );
}

function tintAlpha(level: GlowLevel): number {
  switch (level) {
    case "self":
      return 0.08;
    case "target":
      return 0.05;
    case "other":
      return 0.03;
    case "eliminated":
      return 0;
  }
}

export default function PlayerBoard({
  board,
  cellSize,
  nickname,
  score,
  lines,
  pendingGarbage,
  playerHue,
  glowLevel,
  isMe,
  nextPiece,
  targetNickname,
  level,
  latency,
}: PlayerBoardProps) {
  const fontSize = Math.max(8, Math.round(cellSize * 0.4));
  const alpha = tintAlpha(glowLevel);
  const glow = glowStyles(playerHue, glowLevel);
  const dimmed = glowLevel === "eliminated";
  const hudCell = Math.round(cellSize * 0.5);
  const boardPx = BOARD_WIDTH * cellSize;

  return (
    <div style={{ display: "flex", flexDirection: "column" }}>
      {isMe ? (
        <div
          style={{
            marginBottom: 6,
            fontSize,
            lineHeight: 1.3,
            width: boardPx + 8,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
            }}
          >
            <div
              style={{
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              <span
                style={{
                  fontSize: Math.max(7, fontSize - 2),
                  backgroundColor:
                    `hsl(${String(playerHue)}, 70%, 50%)`,
                  color: "#fff",
                  borderRadius: 3,
                  padding: "1px 4px",
                  marginRight: 4,
                  verticalAlign: "middle",
                  fontWeight: "bold",
                  letterSpacing: 1,
                  textTransform: "uppercase",
                }}
              >
                You
              </span>
              <span
                style={{
                  fontWeight: "bold",
                  color:
                    `hsl(${String(playerHue)}, 70%, 70%)`,
                }}
              >
                {nickname}
              </span>
            </div>
            {nextPiece && (
              <MiniNextPiece
                piece={nextPiece}
                hudCell={hudCell}
              />
            )}
          </div>
          <div
            style={{
              textAlign: "center",
              color: "#888",
              marginTop: 2,
            }}
          >
            Score: {score.toLocaleString()} | Lines: {lines} |
            Lvl: {level ?? 1}
          </div>
          <div
            style={{
              textAlign: "center",
              marginTop: 1,
              fontSize: Math.max(7, fontSize - 1),
            }}
          >
            <span className="text-cyan">
              Target: {targetNickname ?? "\u2014"}
            </span>
            <span style={{ color: "#555" }}> [Tab]</span>
            {latency != null && (
              <LatencyBadge latency={latency} />
            )}
          </div>
          <div
            style={{
              textAlign: "center",
              marginTop: 1,
              fontSize: Math.max(7, fontSize - 2),
              color: "#555",
            }}
          >
            [&larr; &rarr;] Move [&uarr;] Rotate [Space]
            Drop [&darr;] Soft drop
          </div>
        </div>
      ) : (
        <div
          style={{
            textAlign: "center",
            marginBottom: 6,
            fontSize,
            lineHeight: 1.3,
            opacity: dimmed ? 0.3 : 1,
          }}
        >
          <div
            style={{
              fontWeight: "bold",
              color:
                `hsl(${String(playerHue)}, 70%, 70%)`,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {nickname}
          </div>
          <div style={{ color: "#888" }}>
            {score} pts / {lines} lines
          </div>
        </div>
      )}

      <div
        style={{
          position: "relative",
          ...glow,
          borderRadius: 4,
        }}
      >
        <div
          style={{ display: "flex", alignItems: "flex-end" }}
        >
          <GarbageMeter
            count={pendingGarbage}
            cellSize={cellSize}
            totalRows={BOARD_HEIGHT}
          />
          <div
            style={{
              display: "grid",
              gridTemplateColumns:
                `repeat(${String(BOARD_WIDTH)}, ${String(cellSize)}px)`,
              gridTemplateRows:
                `repeat(${String(BOARD_HEIGHT)}, ${String(cellSize)}px)`,
              position: "relative",
            }}
          >
            {board.map((row, y) =>
              row.map((cell, x) => (
                <PlayerCell
                  key={`${String(y)}-${String(x)}`}
                  color={cell}
                  size={cellSize}
                />
              )),
            )}
          </div>
        </div>

        {alpha > 0 && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              backgroundColor:
                `hsla(${String(playerHue)}, 70%, 50%, ${String(alpha)})`,
              borderRadius: 4,
              pointerEvents: "none",
            }}
          />
        )}

        {glowLevel === "target" && (
          <>
            <CornerBrackets
              hue={playerHue}
              fontSize={fontSize}
            />
            <div
              style={{
                position: "absolute",
                inset: 0,
                border:
                  `2px solid hsl(${String(playerHue)}, 70%, 60%)`,
                borderRadius: 4,
                pointerEvents: "none",
                animation:
                  "pulse-border 1.5s ease-in-out infinite",
              }}
            />
          </>
        )}

        {glowLevel === "eliminated" && (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              backgroundColor: "rgba(0, 0, 0, 0.6)",
              borderRadius: 4,
              pointerEvents: "none",
            }}
          >
            <span
              style={{
                color: "#ff4757",
                fontWeight: "bold",
                fontSize: Math.max(
                  10,
                  Math.round(cellSize * 0.6),
                ),
                textTransform: "uppercase",
                letterSpacing: 2,
              }}
            >
              Eliminated
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

interface CornerBracketsProps {
  hue: number;
  fontSize: number;
}

function CornerBrackets({
  hue,
  fontSize,
}: CornerBracketsProps) {
  const color = `hsl(${String(hue)}, 70%, 65%)`;
  const size = Math.max(10, fontSize * 1.5);
  const offset = -Math.round(size * 0.3);
  const base: React.CSSProperties = {
    position: "absolute",
    color,
    fontSize: size,
    lineHeight: 1,
    pointerEvents: "none",
    fontWeight: "bold",
  };

  return (
    <>
      <span style={{ ...base, top: offset, left: offset }}>
        &#x250F;
      </span>
      <span style={{ ...base, top: offset, right: offset }}>
        &#x2513;
      </span>
      <span style={{ ...base, bottom: offset, left: offset }}>
        &#x2517;
      </span>
      <span style={{ ...base, bottom: offset, right: offset }}>
        &#x251B;
      </span>
    </>
  );
}
