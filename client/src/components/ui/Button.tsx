import type { ReactNode, ButtonHTMLAttributes } from 'react';

type ButtonVariant = 'primary' | 'secondary' | 'danger' | 'ghost';
type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  fullWidth?: boolean;
  icon?: ReactNode;
  children: ReactNode;
}

const VARIANT_CLASS: Record<ButtonVariant, string> = {
  primary: [
    'text-white font-semibold',
    'bg-gradient-to-r from-accent to-cyan/80',
    'hover:brightness-110 hover:scale-[1.02]',
    'active:scale-[0.98]',
    'shadow-[0_0_16px_rgba(124,108,255,0.3)]',
    'hover:shadow-[0_0_24px_rgba(124,108,255,0.5)]',
  ].join(' '),
  secondary: ['glass-subtle text-text-primary', 'hover:brightness-110 hover:scale-[1.02]', 'active:scale-[0.98]'].join(
    ' '
  ),
  danger: [
    'text-white font-semibold',
    'bg-red/20 border border-red/40',
    'hover:bg-red/30 hover:scale-[1.02]',
    'active:scale-[0.98]',
  ].join(' '),
  ghost: ['text-text-muted', 'hover:text-text-primary hover:bg-white/[0.03]', 'active:scale-[0.98]'].join(' '),
};

const SIZE_CLASS: Record<ButtonSize, string> = {
  sm: 'px-3 py-1.5 text-sm rounded-lg gap-1.5',
  md: 'px-5 py-2.5 text-base rounded-xl gap-2',
  lg: 'px-8 py-3.5 text-lg rounded-xl gap-2.5',
};

export default function Button({
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  icon,
  children,
  disabled,
  className = '',
  ...rest
}: ButtonProps) {
  return (
    <button
      className={[
        'inline-flex items-center justify-center',
        'transition-all duration-150',
        'focus-visible:outline-2 focus-visible:outline-accent',
        'focus-visible:outline-offset-2',
        VARIANT_CLASS[variant],
        SIZE_CLASS[size],
        fullWidth ? 'w-full' : '',
        disabled ? 'cursor-not-allowed opacity-50' : '',
        className,
      ]
        .filter(Boolean)
        .join(' ')}
      disabled={disabled}
      {...rest}
    >
      {icon && <span className="shrink-0">{icon}</span>}
      {children}
    </button>
  );
}
