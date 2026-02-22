import { useNavigate, useLocation } from 'react-router';
import type { ReactNode } from 'react';

interface NavItemProps {
  icon: ReactNode;
  label: string;
  to: string;
  collapsed?: boolean;
}

export default function NavItem({ icon, label, to, collapsed = false }: NavItemProps) {
  const navigate = useNavigate();
  const location = useLocation();
  const active = location.pathname === to;

  return (
    <button
      onClick={() => navigate(to)}
      title={collapsed ? label : undefined}
      className={[
        'flex w-full items-center gap-3 rounded-lg px-3 py-2.5',
        'transition-all duration-150',
        'focus-visible:outline-2 focus-visible:outline-accent',
        active
          ? 'glass-subtle border-l-2 border-l-accent text-text-primary'
          : 'text-text-muted hover:text-text-primary hover:bg-white/[0.03]',
        collapsed ? 'justify-center' : '',
      ]
        .filter(Boolean)
        .join(' ')}
      aria-current={active ? 'page' : undefined}
    >
      <span className="shrink-0 text-lg">{icon}</span>
      {!collapsed && <span className="font-body text-sm font-medium">{label}</span>}
    </button>
  );
}
