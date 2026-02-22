import type { ReactNode } from 'react';

type GlassVariant = 'default' | 'elevated' | 'subtle';
type PaddingSize = 'none' | 'sm' | 'md' | 'lg';

interface GlassCardProps {
  variant?: GlassVariant;
  padding?: PaddingSize;
  glow?: string | undefined;
  className?: string;
  children: ReactNode;
  onClick?: () => void;
}

const VARIANT_CLASS: Record<GlassVariant, string> = {
  default: 'glass',
  elevated: 'glass-elevated',
  subtle: 'glass-subtle',
};

const PADDING_CLASS: Record<PaddingSize, string> = {
  none: '',
  sm: 'p-3',
  md: 'p-5',
  lg: 'p-8',
};

export default function GlassCard({
  variant = 'default',
  padding = 'md',
  glow,
  className = '',
  children,
  onClick,
}: GlassCardProps) {
  const glowStyle = glow ? { boxShadow: `0 0 20px ${glow}` } : undefined;

  return (
    <div
      className={[
        VARIANT_CLASS[variant],
        PADDING_CLASS[padding],
        onClick ? 'cursor-pointer transition-all duration-150 hover:border-accent/30' : '',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      style={glowStyle}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={
        onClick
          ? (e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onClick();
              }
            }
          : undefined
      }
    >
      {children}
    </div>
  );
}
