import type { ReactNode } from 'react';
import AppSidebar from './AppSidebar.tsx';
import AmbientBackground from './AmbientBackground.tsx';

interface AppShellProps {
  children: ReactNode;
  hideSidebar?: boolean;
}

export default function AppShell({ children, hideSidebar = false }: AppShellProps) {
  return (
    <div className="flex min-h-screen">
      <AmbientBackground />
      <AppSidebar hidden={hideSidebar} />
      <main className={['flex-1 overflow-auto', hideSidebar ? '' : 'ml-[72px]'].filter(Boolean).join(' ')}>
        {children}
      </main>
    </div>
  );
}
