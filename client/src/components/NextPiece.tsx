const PREVIEW_CELL = 22;

interface NextPieceProps {
  piece: { shape: number[][]; color: string } | null;
}

export default function NextPiece({ piece }: NextPieceProps) {
  if (!piece) return null;

  const cols = piece.shape[0]?.length ?? 0;

  return (
    <div className="mb-5">
      <h3 className="m-0 mb-2 text-sm uppercase tracking-widest text-gray-400">
        Next
      </h3>
      <div
        style={{
          display: "inline-grid",
          gridTemplateColumns: `repeat(${String(cols)}, ${String(PREVIEW_CELL)}px)`,
          gap: 1,
        }}
        className="rounded border border-border bg-bg-tertiary p-2.5"
      >
        {piece.shape.map((row, y) =>
          row.map((cell, x) => (
            <div
              key={`${String(y)}-${String(x)}`}
              style={{
                width: PREVIEW_CELL,
                height: PREVIEW_CELL,
                backgroundColor: cell ? piece.color : "transparent",
                boxShadow: cell
                  ? "inset 0 0 6px rgba(255,255,255,0.3)"
                  : "none",
              }}
              className="rounded-sm"
            />
          )),
        )}
      </div>
    </div>
  );
}
