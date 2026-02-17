import { useState, useEffect, type FormEvent } from 'react';
import { useNavigate } from 'react-router';
import { useGameContext } from '../context/GameContext.tsx';

const STORAGE_KEY = 'tetris_nickname';
const VALID_PATTERN = /^[a-zA-Z0-9_]+$/;

export default function NicknameForm() {
  const [input, setInput] = useState('');
  const navigate = useNavigate();
  const { setNickname } = useGameContext();

  useEffect(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) setInput(saved);
  }, []);

  const trimmed = input.trim();
  const valid = trimmed.length >= 3 && trimmed.length <= 16 && VALID_PATTERN.test(trimmed);

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!valid) return;
    localStorage.setItem(STORAGE_KEY, trimmed);
    setNickname(trimmed);
    navigate('/lobby');
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-bg-primary">
      <h2 className="mb-6 text-lg text-gray-400">Enter Nickname</h2>
      <form onSubmit={handleSubmit} className="flex flex-col items-center">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="3-16 chars, a-z, 0-9, _"
          maxLength={16}
          className="mb-4 w-70 rounded-lg border-2 border-border bg-bg-tertiary px-5 py-3 text-lg text-white outline-none focus:border-accent"
          autoFocus
        />
        <div className="flex gap-3">
          <button
            type="button"
            onClick={() => navigate('/')}
            className="cursor-pointer rounded-lg border-none bg-border px-6 py-3 text-sm text-gray-400"
          >
            Back
          </button>
          <button
            type="submit"
            disabled={!valid}
            className={`rounded-lg border-none px-8 py-3 text-base font-bold text-white ${
              valid ? 'cursor-pointer bg-accent' : 'cursor-default bg-gray-700'
            }`}
          >
            Enter Lobby
          </button>
        </div>
      </form>
    </div>
  );
}
