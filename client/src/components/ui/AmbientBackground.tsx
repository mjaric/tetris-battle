export default function AmbientBackground() {
  return (
    <div className="pointer-events-none fixed inset-0 -z-10 overflow-hidden">
      {/* Purple orb — top left */}
      <div
        className="absolute -left-32 -top-32 h-[500px] w-[500px] rounded-full opacity-15"
        style={{
          background: 'radial-gradient(circle, #7c6cff 0%, transparent 70%)',
          filter: 'blur(120px)',
        }}
      />
      {/* Cyan orb — bottom right */}
      <div
        className="absolute -bottom-40 -right-40 h-[400px] w-[400px] rounded-full opacity-10"
        style={{
          background: 'radial-gradient(circle, #00e0e0 0%, transparent 70%)',
          filter: 'blur(100px)',
        }}
      />
      {/* Warm orb — mid left */}
      <div
        className="absolute left-1/4 top-1/2 h-[300px] w-[300px] rounded-full opacity-[0.07]"
        style={{
          background: 'radial-gradient(circle, #ffa502 0%, transparent 70%)',
          filter: 'blur(80px)',
        }}
      />
    </div>
  );
}
