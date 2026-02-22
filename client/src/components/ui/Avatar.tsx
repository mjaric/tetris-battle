type AvatarSize = 'sm' | 'md' | 'lg';

interface AvatarProps {
  name: string;
  size?: AvatarSize;
  status?: boolean;
  className?: string;
}

const SIZE_CLASS: Record<AvatarSize, string> = {
  sm: 'h-7 w-7 text-xs',
  md: 'h-9 w-9 text-sm',
  lg: 'h-12 w-12 text-base',
};

function hashColor(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  const hue = Math.abs(hash) % 360;
  return `hsl(${hue}, 65%, 55%)`;
}

export default function Avatar({ name, size = 'md', status, className = '' }: AvatarProps) {
  const color = hashColor(name);
  const letter = name.charAt(0).toUpperCase();

  return (
    <div className={`relative inline-flex ${className}`}>
      <div
        className={[SIZE_CLASS[size], 'flex items-center justify-center', 'rounded-full font-display font-bold text-white'].join(
          ' '
        )}
        style={{
          background: `linear-gradient(135deg, ${color}, ${color}88)`,
        }}
        aria-label={name}
      >
        {letter}
      </div>
      {status != null && (
        <span
          className={[
            'absolute bottom-0 right-0',
            'h-2.5 w-2.5 rounded-full border-2 border-bg-primary',
            status ? 'bg-green' : 'bg-muted',
          ].join(' ')}
        />
      )}
    </div>
  );
}
