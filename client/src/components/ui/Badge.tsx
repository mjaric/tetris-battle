import type { ReactNode } from 'react';

type BadgeVariant = 'player' | 'bot' | 'rank' | 'status';

interface BadgeProps {
  variant?: BadgeVariant;
  color?: string;
  children: ReactNode;
  className?: string;
}

const VARIANT_STYLES: Record<BadgeVariant, string> = {
  player: 'bg-accent/20 text-accent border-accent/30',
  bot: 'bg-amber/20 text-amber border-amber/30',
  rank: 'bg-gold/20 text-gold border-gold/30',
  status: 'bg-green/20 text-green border-green/30',
};

export default function Badge({ variant = 'status', color, children, className = '' }: BadgeProps) {
  const colorStyle = color
    ? {
        backgroundColor: `${color}20`,
        color,
        borderColor: `${color}4d`,
      }
    : undefined;

  return (
    <span
      className={[
        'inline-flex items-center gap-1',
        'rounded-full border px-2 py-0.5',
        'text-xs font-medium',
        !color ? VARIANT_STYLES[variant] : '',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      style={colorStyle}
    >
      {children}
    </span>
  );
}
