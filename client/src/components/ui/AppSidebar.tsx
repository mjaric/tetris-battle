import { useState } from 'react';
import NavItem from './NavItem.tsx';
import Avatar from './Avatar.tsx';
import { useAuthContext } from '../../platform/auth/AuthProvider.tsx';

interface AppSidebarProps {
  hidden?: boolean;
}

export default function AppSidebar({ hidden = false }: AppSidebarProps) {
  const [collapsed, setCollapsed] = useState(true);
  const { user } = useAuthContext();

  if (hidden) return null;

  const displayName = user?.nickname ?? user?.displayName ?? 'Player';

  return (
    <aside
      className={[
        'glass fixed left-0 top-0 z-40 flex h-screen flex-col',
        'border-r border-glass-border rounded-none rounded-r-2xl',
        'transition-all duration-200',
        collapsed ? 'w-[72px]' : 'w-[220px]',
      ].join(' ')}
      onMouseEnter={() => setCollapsed(false)}
      onMouseLeave={() => setCollapsed(true)}
    >
      {/* Logo */}
      <div className="flex h-16 items-center justify-center border-b border-glass-border">
        <span className="font-display text-xl font-bold text-accent">{collapsed ? 'T' : 'TETRIS'}</span>
      </div>

      {/* Navigation */}
      <nav className="flex flex-1 flex-col gap-1 p-3">
        <NavItem icon="🏠" label="Home" to="/" collapsed={collapsed} />
        <NavItem icon="🎮" label="Solo Play" to="/solo" collapsed={collapsed} />
        <NavItem icon="⚔️" label="Lobby" to="/lobby" collapsed={collapsed} />
      </nav>

      {/* User */}
      <div className="border-t border-glass-border p-3">
        <div className={['flex items-center gap-3', collapsed ? 'justify-center' : ''].join(' ')}>
          <Avatar name={displayName} size="sm" />
          {!collapsed && <span className="truncate font-body text-sm text-text-primary">{displayName}</span>}
        </div>
      </div>
    </aside>
  );
}
