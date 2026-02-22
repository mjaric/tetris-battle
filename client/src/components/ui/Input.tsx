import type { InputHTMLAttributes, ReactNode } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  icon?: ReactNode;
  error?: string | undefined;
  label?: string;
}

export default function Input({ icon, error, label, className = '', id, ...rest }: InputProps) {
  const inputId = id ?? label?.toLowerCase().replace(/\s+/g, '-');

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label htmlFor={inputId} className="font-body text-sm text-text-muted">
          {label}
        </label>
      )}
      <div className="relative">
        {icon && (
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-text-muted">{icon}</span>
        )}
        <input
          id={inputId}
          className={[
            'glass-subtle w-full px-3 py-2.5 text-text-primary',
            'placeholder:text-text-muted/50',
            'transition-all duration-150',
            'focus:border-accent/50 focus:outline-none',
            'focus:shadow-[0_0_0_2px_rgba(124,108,255,0.2)]',
            icon ? 'pl-10' : '',
            error ? 'border-red/50' : '',
            className,
          ]
            .filter(Boolean)
            .join(' ')}
          {...rest}
        />
      </div>
      {error && <p className="text-sm text-red">{error}</p>}
    </div>
  );
}
