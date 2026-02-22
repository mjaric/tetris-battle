import { GlassCard, Button, Input, Badge, Avatar, Stat, Divider, PageTransition } from '../ui/index.ts';

function Section({
  title,
  description,
  children,
}: {
  title: string;
  description: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mb-12">
      <h2 className="mb-1 font-display text-2xl font-bold text-text-primary">{title}</h2>
      <p className="mb-4 text-sm text-text-muted">{description}</p>
      <div className="flex flex-wrap items-start gap-4">{children}</div>
    </section>
  );
}

export default function ComponentShowcase() {
  return (
    <PageTransition className="min-h-screen p-8">
      <h1 className="mb-2 font-display text-4xl font-bold text-text-primary">Component Library</h1>
      <p className="mb-10 text-text-muted">All reusable UI primitives with variants</p>

      {/* Typography */}
      <Section title="Typography" description="Font families: Space Grotesk (display), Inter (body), JetBrains Mono (mono)">
        <div className="flex flex-col gap-3">
          <span className="font-display text-4xl font-bold">Space Grotesk Display</span>
          <span className="font-body text-lg">Inter Body Text — The quick brown fox jumps</span>
          <span className="font-mono text-lg">JetBrains Mono — 1234567890</span>
        </div>
      </Section>

      {/* Colors */}
      <Section title="Colors" description="Design token color palette">
        <div className="flex flex-wrap gap-3">
          {[
            ['bg-accent', 'Accent'],
            ['bg-cyan', 'Cyan'],
            ['bg-green', 'Green'],
            ['bg-amber', 'Amber'],
            ['bg-red', 'Red'],
            ['bg-gold', 'Gold'],
            ['bg-silver', 'Silver'],
            ['bg-bronze', 'Bronze'],
          ].map(([bg, name]) => (
            <div key={name} className="flex flex-col items-center gap-1">
              <div className={`${bg} h-12 w-12 rounded-lg`} />
              <span className="text-xs text-text-muted">{name}</span>
            </div>
          ))}
        </div>
      </Section>

      {/* Glass Cards */}
      <Section title="GlassCard" description="Three glass levels: default, elevated, subtle">
        <GlassCard padding="md">
          <p className="text-sm">Default glass</p>
        </GlassCard>
        <GlassCard variant="elevated" padding="md">
          <p className="text-sm">Elevated glass</p>
        </GlassCard>
        <GlassCard variant="subtle" padding="md">
          <p className="text-sm">Subtle glass</p>
        </GlassCard>
        <GlassCard padding="md" glow="rgba(124, 108, 255, 0.3)">
          <p className="text-sm">With accent glow</p>
        </GlassCard>
        <GlassCard padding="md" onClick={() => {}}>
          <p className="text-sm">Clickable card</p>
        </GlassCard>
      </Section>

      {/* Buttons */}
      <Section title="Button" description="Variants: primary, secondary, danger, ghost. Sizes: sm, md, lg">
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="primary" size="sm">
              Primary SM
            </Button>
            <Button variant="primary" size="md">
              Primary MD
            </Button>
            <Button variant="primary" size="lg">
              Primary LG
            </Button>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="secondary">Secondary</Button>
            <Button variant="danger">Danger</Button>
            <Button variant="ghost">Ghost</Button>
            <Button variant="primary" disabled>
              Disabled
            </Button>
          </div>
          <Button variant="primary" fullWidth>
            Full Width
          </Button>
        </div>
      </Section>

      {/* Inputs */}
      <Section title="Input" description="Text input with optional label, icon, error state">
        <div className="flex w-full max-w-md flex-col gap-4">
          <Input label="Nickname" placeholder="Enter nickname..." />
          <Input label="With icon" placeholder="Search..." icon={<span>🔍</span>} />
          <Input label="Error state" placeholder="Invalid..." error="This field is required" />
        </div>
      </Section>

      {/* Badges */}
      <Section title="Badge" description="Variants: player, bot, rank, status">
        <Badge variant="player">Player</Badge>
        <Badge variant="bot">Bot</Badge>
        <Badge variant="rank">1st</Badge>
        <Badge variant="status">Online</Badge>
        <Badge color="#ff69b4">Custom</Badge>
      </Section>

      {/* Avatars */}
      <Section title="Avatar" description="Sizes: sm, md, lg. Deterministic color from name hash">
        <Avatar name="Alice" size="sm" />
        <Avatar name="Bob" size="md" />
        <Avatar name="Charlie" size="lg" />
        <Avatar name="Diana" size="md" status={true} />
        <Avatar name="Eve" size="md" status={false} />
      </Section>

      {/* Stats */}
      <Section title="Stat" description="Label + value display for scores and metrics">
        <Stat label="Score" value={12500} />
        <Stat label="Lines" value={42} />
        <Stat label="Level" value={7} />
        <Stat label="Time" value="02:34" />
        <Stat label="Player" value="Alice" mono={false} />
      </Section>

      {/* Dividers */}
      <Section title="Divider" description="Horizontal separator with optional label">
        <div className="flex w-full max-w-md flex-col gap-6">
          <Divider />
          <Divider label="OR" />
          <Divider label="SECTION" />
        </div>
      </Section>
    </PageTransition>
  );
}
