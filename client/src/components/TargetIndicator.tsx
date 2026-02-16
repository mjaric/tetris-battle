interface TargetIndicatorProps {
  targetNickname: string | undefined;
}

export default function TargetIndicator({
  targetNickname,
}: TargetIndicatorProps) {
  return (
    <div className="mb-3 rounded-md border border-cyan bg-bg-tertiary px-4 py-2 text-center">
      <div className="text-[10px] uppercase tracking-widest text-muted">
        Target
      </div>
      <div className="text-base font-bold text-cyan">
        {targetNickname ?? "\u2014"}
      </div>
      <div className="mt-1 text-[10px] text-gray-600">
        [Tab] to switch
      </div>
    </div>
  );
}
