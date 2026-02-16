import { useNavigate } from "react-router";

export default function MainMenu() {
  const navigate = useNavigate();

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h1 className="mb-12 text-5xl font-extrabold uppercase tracking-widest bg-gradient-to-br from-accent to-cyan bg-clip-text text-transparent">
        Tetris
      </h1>
      <button
        onClick={() => navigate("/solo")}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-accent px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Solo
      </button>
      <button
        onClick={() => navigate("/multiplayer")}
        className="mb-4 w-65 cursor-pointer rounded-lg bg-green px-12 py-4 text-lg font-bold uppercase tracking-wide text-white transition-colors hover:brightness-110"
      >
        Multiplayer
      </button>
    </div>
  );
}
