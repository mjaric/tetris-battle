interface StatBoxProps {
  label: string;
  value: number;
}

export default function StatBox({ label, value }: StatBoxProps) {
  return (
    <div className="mb-3">
      <div className="text-xs uppercase tracking-widest text-muted">{label}</div>
      <div className="font-mono text-xl font-bold text-white">{value.toLocaleString()}</div>
    </div>
  );
}
