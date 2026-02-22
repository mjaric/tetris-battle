interface StatProps {
  label: string;
  value: string | number;
  mono?: boolean;
  className?: string;
}

export default function Stat({ label, value, mono = true, className = '' }: StatProps) {
  return (
    <div className={`flex flex-col gap-0.5 ${className}`}>
      <span className="font-body text-xs uppercase tracking-wider text-text-muted">{label}</span>
      <span className={['text-lg font-bold text-text-primary', mono ? 'font-mono' : 'font-display'].join(' ')}>
        {value}
      </span>
    </div>
  );
}
