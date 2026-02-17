interface LatencyIndicatorProps {
  latency: number | null;
}

export default function LatencyIndicator({ latency }: LatencyIndicatorProps) {
  if (latency === null) return null;

  const colorClass = latency < 80 ? 'text-green' : latency < 150 ? 'text-amber' : 'text-red';

  return (
    <div className="mt-2 text-center text-xs">
      <span className="text-muted">Ping: </span>
      <span className={colorClass}>{latency}ms</span>
    </div>
  );
}
