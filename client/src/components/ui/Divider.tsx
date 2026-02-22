interface DividerProps {
  label?: string;
  className?: string;
}

export default function Divider({ label, className = '' }: DividerProps) {
  if (label) {
    return (
      <div className={`flex items-center gap-3 ${className}`}>
        <div className="h-px flex-1 bg-glass-border" />
        <span className="text-xs text-text-muted">{label}</span>
        <div className="h-px flex-1 bg-glass-border" />
      </div>
    );
  }

  return <div className={`h-px bg-glass-border ${className}`} />;
}
