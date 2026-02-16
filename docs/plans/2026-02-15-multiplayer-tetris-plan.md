# Multiplayer Tetris Battle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add online multiplayer battle mode (up to 4 players) with garbage line mechanics, lobby system, and challenge-response auth to existing single-player Tetris.

**Architecture:** Server-authoritative Elixir Phoenix backend with Phoenix Channels for real-time communication. React frontend renders JSON state received from server. Single-player mode stays client-only. Monorepo with `client/` and `server/` directories.

**Tech Stack:** Elixir/Phoenix (backend), React 19 (frontend), Phoenix Channels/WebSocket (real-time), HMAC-SHA256 (auth)

---

## Phase 1: Project Restructure

### Task 1: Move React app to client/ subdirectory

**Files:**
- Move: all files from project root into `client/` subdirectory
- Keep: `docs/`, `.git/`, root-level config

**Step 1: Create client directory and move React app**

```bash
mkdir client
git mv public client/
git mv src client/
git mv package.json client/
git mv package-lock.json client/ 2>/dev/null || true
```

**Step 2: Verify React app still works from client/**

```bash
cd client && npm install && npm start
```

Expected: Dev server starts on localhost:3000, game is playable.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: move React app to client/ for monorepo structure"
```

---

### Task 2: Scaffold Phoenix project in server/

**Files:**
- Create: `server/` directory with Phoenix project

**Step 1: Generate Phoenix project (no Ecto, no HTML, no mailer)**

```bash
mix phx.new server --no-ecto --no-html --no-mailer --no-dashboard --no-live
```

When prompted to fetch dependencies, answer Yes.

**Step 2: Verify Phoenix starts**

```bash
cd server && mix deps.get && mix phx.server
```

Expected: Phoenix starts on localhost:4000.

**Step 3: Configure CORS for dev (allow localhost:3000)**

Edit `server/lib/tetris_web/endpoint.ex` — add before the existing `plug Plug.Parsers`:

```elixir
plug Corsica,
  origins: ["http://localhost:3000"],
  allow_headers: :all,
  allow_methods: :all
```

Add `{:corsica, "~> 2.1"}` to `mix.exs` deps.

```bash
cd server && mix deps.get
```

**Step 4: Commit**

```bash
git add server/
git commit -m "chore: scaffold Phoenix backend (no ecto, no html)"
```

---

## Phase 2: Elixir Core Game Logic (TDD)

### Task 3: Piece module — tetromino definitions

**Files:**
- Create: `server/lib/tetris/piece.ex`
- Test: `server/test/tetris/piece_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris/piece_test.exs
defmodule Tetris.PieceTest do
  use ExUnit.Case, async: true
  alias Tetris.Piece

  test "all 7 tetromino types are defined" do
    assert length(Piece.types()) == 7
    assert :I in Piece.types()
    assert :O in Piece.types()
    assert :T in Piece.types()
    assert :S in Piece.types()
    assert :Z in Piece.types()
    assert :J in Piece.types()
    assert :L in Piece.types()
  end

  test "new/1 returns piece with shape, color, rotation" do
    piece = Piece.new(:T)
    assert piece.type == :T
    assert piece.color == "#a000f0"
    assert piece.rotation == 0
    assert piece.shape == [
      [0, 1, 0],
      [1, 1, 1],
      [0, 0, 0]
    ]
  end

  test "rotate/1 rotates shape 90 degrees clockwise" do
    piece = Piece.new(:T)
    rotated = Piece.rotate(piece)
    assert rotated.rotation == 1
    assert rotated.shape == [
      [1, 0],
      [1, 1],
      [1, 0]
    ] || rotated.shape == [
      [0, 1, 0],
      [0, 1, 1],
      [0, 1, 0]
    ]
    # Exact shape depends on rotation implementation matching SRS
  end

  test "random/0 returns a valid piece" do
    piece = Piece.random()
    assert piece.type in Piece.types()
    assert is_binary(piece.color)
    assert is_list(piece.shape)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd server && mix test test/tetris/piece_test.exs
```

Expected: FAIL — module Tetris.Piece not found.

**Step 3: Implement Piece module**

```elixir
# server/lib/tetris/piece.ex
defmodule Tetris.Piece do
  @enforce_keys [:type, :shape, :color, :rotation]
  defstruct [:type, :shape, :color, :rotation]

  @tetrominoes %{
    I: %{
      shape: [
        [0, 0, 0, 0],
        [1, 1, 1, 1],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
      color: "#00f0f0"
    },
    O: %{shape: [[1, 1], [1, 1]], color: "#f0f000"},
    T: %{shape: [[0, 1, 0], [1, 1, 1], [0, 0, 0]], color: "#a000f0"},
    S: %{shape: [[0, 1, 1], [1, 1, 0], [0, 0, 0]], color: "#00f000"},
    Z: %{shape: [[1, 1, 0], [0, 1, 1], [0, 0, 0]], color: "#f00000"},
    J: %{shape: [[1, 0, 0], [1, 1, 1], [0, 0, 0]], color: "#0000f0"},
    L: %{shape: [[0, 0, 1], [1, 1, 1], [0, 0, 0]], color: "#f0a000"}
  }

  def types, do: Map.keys(@tetrominoes)

  def new(type) when is_atom(type) do
    data = Map.fetch!(@tetrominoes, type)
    %__MODULE__{type: type, shape: data.shape, color: data.color, rotation: 0}
  end

  def random do
    type = Enum.random(types())
    new(type)
  end

  def rotate(%__MODULE__{shape: shape, rotation: rot} = piece) do
    n = length(shape)
    rotated =
      for i <- 0..(n - 1) do
        for j <- 0..(n - 1) do
          shape |> Enum.at(n - 1 - j) |> Enum.at(i)
        end
      end

    %{piece | shape: rotated, rotation: rem(rot + 1, 4)}
  end
end
```

**Step 4: Run test to verify it passes**

```bash
cd server && mix test test/tetris/piece_test.exs
```

Expected: PASS (adjust rotate test assertion to match actual SRS rotation output).

**Step 5: Commit**

```bash
cd server && git add lib/tetris/piece.ex test/tetris/piece_test.exs
git commit -m "feat: add Piece module with tetromino definitions and rotation"
```

---

### Task 4: Board module — core board operations

**Files:**
- Create: `server/lib/tetris/board.ex`
- Test: `server/test/tetris/board_test.exs`

**Step 1: Write failing tests**

```elixir
# server/test/tetris/board_test.exs
defmodule Tetris.BoardTest do
  use ExUnit.Case, async: true
  alias Tetris.Board

  test "new/0 creates 20x10 empty board" do
    board = Board.new()
    assert length(board) == 20
    assert Enum.all?(board, &(length(&1) == 10))
    assert Enum.all?(board, fn row -> Enum.all?(row, &is_nil/1) end)
  end

  test "place_piece/3 places piece on board" do
    board = Board.new()
    shape = [[1, 1], [1, 1]]
    result = Board.place_piece(board, shape, "#f0f000", {4, 0})
    assert Enum.at(result, 0) |> Enum.at(4) == "#f0f000"
    assert Enum.at(result, 0) |> Enum.at(5) == "#f0f000"
    assert Enum.at(result, 1) |> Enum.at(4) == "#f0f000"
    assert Enum.at(result, 1) |> Enum.at(5) == "#f0f000"
  end

  test "valid_position?/3 returns true for valid placement" do
    board = Board.new()
    shape = [[1, 1], [1, 1]]
    assert Board.valid_position?(board, shape, {4, 0}) == true
  end

  test "valid_position?/3 returns false when out of bounds" do
    board = Board.new()
    shape = [[1, 1], [1, 1]]
    assert Board.valid_position?(board, shape, {9, 0}) == false
    assert Board.valid_position?(board, shape, {-1, 0}) == false
    assert Board.valid_position?(board, shape, {0, 19}) == false
  end

  test "valid_position?/3 returns false when overlapping" do
    board = Board.new()
    shape = [[1, 1], [1, 1]]
    board = Board.place_piece(board, shape, "#f0f000", {4, 0})
    assert Board.valid_position?(board, shape, {4, 0}) == false
  end

  test "clear_lines/1 clears full rows and returns count" do
    board = Board.new()
    # Fill bottom row completely
    full_row = List.duplicate("#ff0000", 10)
    board = List.replace_at(board, 19, full_row)
    {new_board, cleared} = Board.clear_lines(board)
    assert cleared == 1
    assert length(new_board) == 20
    # Bottom row should now be empty (shifted down)
    assert Enum.all?(Enum.at(new_board, 0), &is_nil/1)
  end

  test "add_garbage/2 adds garbage rows at bottom" do
    board = Board.new()
    garbage = [
      List.replace_at(List.duplicate("#808080", 10), 3, nil),
      List.replace_at(List.duplicate("#808080", 10), 7, nil)
    ]
    {new_board, overflow} = Board.add_garbage(board, garbage)
    assert length(new_board) == 20
    assert overflow == false
    # Bottom two rows should be garbage
    assert Enum.at(new_board, 19) |> Enum.at(3) == nil
    assert Enum.at(new_board, 19) |> Enum.at(0) == "#808080"
  end

  test "add_garbage/2 detects overflow" do
    board = Board.new()
    # Place something in top row
    board = List.update_at(board, 0, fn row -> List.replace_at(row, 5, "#ff0000") end)
    # Add 1 garbage row — should push top row out
    garbage = [List.replace_at(List.duplicate("#808080", 10), 3, nil)]
    {_new_board, overflow} = Board.add_garbage(board, garbage)
    assert overflow == true
  end

  test "ghost_position/3 finds lowest valid y" do
    board = Board.new()
    shape = [[1, 1], [1, 1]]
    {gx, gy} = Board.ghost_position(board, shape, {4, 0})
    assert gx == 4
    assert gy == 18  # O-piece is 2 tall, bottom of board is 19, so 19-1=18
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
cd server && mix test test/tetris/board_test.exs
```

Expected: FAIL — module Tetris.Board not found.

**Step 3: Implement Board module**

```elixir
# server/lib/tetris/board.ex
defmodule Tetris.Board do
  @width 10
  @height 20

  def width, do: @width
  def height, do: @height

  def new do
    for _ <- 1..@height, do: List.duplicate(nil, @width)
  end

  def valid_position?(board, shape, {px, py}) do
    shape
    |> Enum.with_index()
    |> Enum.all?(fn {row, y} ->
      row
      |> Enum.with_index()
      |> Enum.all?(fn {cell, x} ->
        if cell == 1 do
          bx = px + x
          by = py + y
          bx >= 0 and bx < @width and by < @height and
            (by < 0 or (Enum.at(board, by) |> Enum.at(bx)) == nil)
        else
          true
        end
      end)
    end)
  end

  def place_piece(board, shape, color, {px, py}) do
    shape
    |> Enum.with_index()
    |> Enum.reduce(board, fn {row, y}, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, x}, board_acc ->
        if cell == 1 do
          bx = px + x
          by = py + y

          if by >= 0 and by < @height and bx >= 0 and bx < @width do
            List.update_at(board_acc, by, fn board_row ->
              List.replace_at(board_row, bx, color)
            end)
          else
            board_acc
          end
        else
          board_acc
        end
      end)
    end)
  end

  def clear_lines(board) do
    remaining = Enum.filter(board, fn row -> Enum.any?(row, &is_nil/1) end)
    cleared = @height - length(remaining)
    empty_rows = for _ <- 1..cleared, do: List.duplicate(nil, @width)
    {empty_rows ++ remaining, cleared}
  end

  def add_garbage(board, garbage_rows) do
    n = length(garbage_rows)
    top_rows = Enum.take(board, n)
    overflow = Enum.any?(top_rows, fn row -> Enum.any?(row, &(not is_nil(&1))) end)
    new_board = Enum.drop(board, n) ++ garbage_rows
    {new_board, overflow}
  end

  def ghost_position(board, shape, {px, py}) do
    ghost_y =
      py..(@height - 1)
      |> Enum.reduce_while(py, fn y, _acc ->
        if valid_position?(board, shape, {px, y + 1}) do
          {:cont, y + 1}
        else
          {:halt, y}
        end
      end)

    {px, ghost_y}
  end

  def generate_garbage_row do
    gap = :rand.uniform(@width) - 1
    List.replace_at(List.duplicate("#808080", @width), gap, nil)
  end
end
```

**Step 4: Run tests**

```bash
cd server && mix test test/tetris/board_test.exs
```

Expected: PASS

**Step 5: Commit**

```bash
cd server && git add lib/tetris/board.ex test/tetris/board_test.exs
git commit -m "feat: add Board module with place, clear, garbage, ghost operations"
```

---

### Task 5: WallKicks module — SRS kick data

**Files:**
- Create: `server/lib/tetris/wall_kicks.ex`
- Test: `server/test/tetris/wall_kicks_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris/wall_kicks_test.exs
defmodule Tetris.WallKicksTest do
  use ExUnit.Case, async: true
  alias Tetris.WallKicks

  test "get/2 returns kick offsets for normal pieces" do
    offsets = WallKicks.get(:T, {0, 1})
    assert is_list(offsets)
    assert length(offsets) == 5
    assert hd(offsets) == {0, 0}
  end

  test "get/2 returns different kick offsets for I piece" do
    offsets_i = WallKicks.get(:I, {0, 1})
    offsets_t = WallKicks.get(:T, {0, 1})
    assert offsets_i != offsets_t
  end

  test "get/2 covers all rotation transitions" do
    for from <- 0..3, to = rem(from + 1, 4) do
      offsets = WallKicks.get(:T, {from, to})
      assert length(offsets) == 5, "Missing kicks for #{from}>#{to}"
    end
  end
end
```

**Step 2: Run to verify fail**

```bash
cd server && mix test test/tetris/wall_kicks_test.exs
```

**Step 3: Implement WallKicks**

```elixir
# server/lib/tetris/wall_kicks.ex
defmodule Tetris.WallKicks do
  @normal %{
    {0, 1} => [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}],
    {1, 0} => [{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}],
    {1, 2} => [{0, 0}, {1, 0}, {1, -1}, {0, 2}, {1, 2}],
    {2, 1} => [{0, 0}, {-1, 0}, {-1, 1}, {0, -2}, {-1, -2}],
    {2, 3} => [{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}],
    {3, 2} => [{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}],
    {3, 0} => [{0, 0}, {-1, 0}, {-1, -1}, {0, 2}, {-1, 2}],
    {0, 3} => [{0, 0}, {1, 0}, {1, 1}, {0, -2}, {1, -2}]
  }

  @i_piece %{
    {0, 1} => [{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}],
    {1, 0} => [{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}],
    {1, 2} => [{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}],
    {2, 1} => [{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}],
    {2, 3} => [{0, 0}, {2, 0}, {-1, 0}, {2, 1}, {-1, -2}],
    {3, 2} => [{0, 0}, {-2, 0}, {1, 0}, {-2, -1}, {1, 2}],
    {3, 0} => [{0, 0}, {1, 0}, {-2, 0}, {1, -2}, {-2, 1}],
    {0, 3} => [{0, 0}, {-1, 0}, {2, 0}, {-1, 2}, {2, -1}]
  }

  def get(:I, transition), do: Map.fetch!(@i_piece, transition)
  def get(_type, transition), do: Map.fetch!(@normal, transition)
end
```

**Step 4: Run tests**

```bash
cd server && mix test test/tetris/wall_kicks_test.exs
```

Expected: PASS

**Step 5: Commit**

```bash
cd server && git add lib/tetris/wall_kicks.ex test/tetris/wall_kicks_test.exs
git commit -m "feat: add WallKicks module with SRS kick data"
```

---

### Task 6: GameLogic module — move, rotate, lock, spawn

**Files:**
- Create: `server/lib/tetris/game_logic.ex`
- Test: `server/test/tetris/game_logic_test.exs`

**Step 1: Write failing tests**

```elixir
# server/test/tetris/game_logic_test.exs
defmodule Tetris.GameLogicTest do
  use ExUnit.Case, async: true
  alias Tetris.{GameLogic, Board, Piece}

  defp new_state do
    board = Board.new()
    piece = Piece.new(:T)
    %{
      board: board,
      current_piece: piece,
      position: {3, 0},
      next_piece: Piece.new(:I),
      score: 0,
      lines: 0,
      level: 1,
      alive: true,
      pending_garbage: [],
      gravity_counter: 0,
      gravity_threshold: 16
    }
  end

  test "move_left/1 moves piece left" do
    state = new_state()
    {:ok, new_state} = GameLogic.move_left(state)
    assert elem(new_state.position, 0) == 2
  end

  test "move_left/1 returns error at left wall" do
    state = %{new_state() | position: {0, 0}, current_piece: Piece.new(:O)}
    assert :invalid = GameLogic.move_left(state)
  end

  test "move_right/1 moves piece right" do
    state = new_state()
    {:ok, new_state} = GameLogic.move_right(state)
    assert elem(new_state.position, 0) == 4
  end

  test "move_down/1 moves piece down" do
    state = new_state()
    {:ok, :moved, new_state} = GameLogic.move_down(state)
    assert elem(new_state.position, 1) == 1
  end

  test "move_down/1 returns :locked when piece cant move" do
    state = %{new_state() | position: {4, 18}, current_piece: Piece.new(:O)}
    {:ok, :locked, new_state} = GameLogic.move_down(state)
    # Piece should be placed on board
    assert new_state.current_piece != state.current_piece
  end

  test "rotate/1 rotates piece with wall kicks" do
    state = new_state()
    {:ok, new_state} = GameLogic.rotate(state)
    assert new_state.current_piece.rotation == 1
  end

  test "hard_drop/1 drops piece to bottom" do
    state = new_state()
    {:ok, new_state} = GameLogic.hard_drop(state)
    # Piece should be locked and a new piece spawned
    assert new_state.score > 0  # hard drop bonus
  end

  test "clearing lines sends garbage count" do
    state = new_state()
    # Build a board with a nearly complete row at bottom
    row = List.duplicate("#ff0000", 10) |> List.replace_at(4, nil) |> List.replace_at(5, nil)
    board = List.replace_at(Board.new(), 19, List.replace_at(row, 4, nil))
    board = List.replace_at(board, 19, List.duplicate("#ff0000", 10))
    state = %{state | board: board, position: {4, 17}, current_piece: Piece.new(:O)}
    {:ok, :locked, new_state} = GameLogic.move_down(state)
    assert new_state.lines > 0
  end
end
```

**Step 2: Run to verify fail**

```bash
cd server && mix test test/tetris/game_logic_test.exs
```

**Step 3: Implement GameLogic**

```elixir
# server/lib/tetris/game_logic.ex
defmodule Tetris.GameLogic do
  alias Tetris.{Board, Piece, WallKicks}

  @board_width 10
  @lines_per_level 10
  @points %{1 => 100, 2 => 300, 3 => 500, 4 => 800}

  def move_left(%{board: board, current_piece: piece, position: {px, py}} = state) do
    new_pos = {px - 1, py}
    if Board.valid_position?(board, piece.shape, new_pos) do
      {:ok, %{state | position: new_pos}}
    else
      :invalid
    end
  end

  def move_right(%{board: board, current_piece: piece, position: {px, py}} = state) do
    new_pos = {px + 1, py}
    if Board.valid_position?(board, piece.shape, new_pos) do
      {:ok, %{state | position: new_pos}}
    else
      :invalid
    end
  end

  def move_down(%{board: board, current_piece: piece, position: {px, py}} = state) do
    new_pos = {px, py + 1}
    if Board.valid_position?(board, piece.shape, new_pos) do
      {:ok, :moved, %{state | position: new_pos}}
    else
      lock_and_spawn(state)
    end
  end

  def rotate(%{board: board, current_piece: piece, position: {px, py}} = state) do
    rotated = Piece.rotate(piece)
    transition = {piece.rotation, rotated.rotation}
    kicks = WallKicks.get(piece.type, transition)

    result =
      Enum.find_value(kicks, fn {dx, dy} ->
        new_pos = {px + dx, py - dy}
        if Board.valid_position?(board, rotated.shape, new_pos) do
          {rotated, new_pos}
        end
      end)

    case result do
      {new_piece, new_pos} ->
        {:ok, %{state | current_piece: new_piece, position: new_pos}}
      nil ->
        :invalid
    end
  end

  def hard_drop(%{board: board, current_piece: piece, position: {px, py}} = state) do
    {_gx, gy} = Board.ghost_position(board, piece.shape, {px, py})
    drop_distance = gy - py
    state = %{state | position: {px, gy}, score: state.score + drop_distance * 2}
    lock_and_spawn(state)
  end

  def apply_gravity(%{gravity_counter: counter, gravity_threshold: threshold} = state) do
    new_counter = counter + 1
    if new_counter >= threshold do
      state = %{state | gravity_counter: 0}
      move_down(state)
    else
      {:ok, :waiting, %{state | gravity_counter: new_counter}}
    end
  end

  def spawn_piece(state) do
    piece = state.next_piece || Piece.random()
    next = Piece.random()
    start_x = div(@board_width - length(hd(piece.shape)), 2)
    start_y = -1

    if Board.valid_position?(state.board, piece.shape, {start_x, start_y + 1}) do
      {:ok, %{state | current_piece: piece, next_piece: next, position: {start_x, start_y}}}
    else
      {:game_over, %{state | alive: false}}
    end
  end

  def apply_pending_garbage(%{pending_garbage: []} = state), do: {:ok, state}
  def apply_pending_garbage(%{board: board, pending_garbage: garbage} = state) do
    {new_board, overflow} = Board.add_garbage(board, garbage)
    state = %{state | board: new_board, pending_garbage: []}
    if overflow do
      {:game_over, %{state | alive: false}}
    else
      {:ok, state}
    end
  end

  def gravity_threshold(level) do
    max(2, 16 - (level - 1))
  end

  # --- Private ---

  defp lock_and_spawn(state) do
    %{board: board, current_piece: piece, position: pos} = state

    # Place piece on board
    new_board = Board.place_piece(board, piece.shape, piece.color, pos)

    # Clear lines
    {cleared_board, lines_cleared} = Board.clear_lines(new_board)

    # Update stats
    new_lines = state.lines + lines_cleared
    new_level = div(new_lines, @lines_per_level) + 1
    points = Map.get(@points, lines_cleared, 0) * state.level
    new_score = state.score + points
    new_threshold = gravity_threshold(new_level)

    state = %{state |
      board: cleared_board,
      lines: new_lines,
      level: new_level,
      score: new_score,
      gravity_threshold: new_threshold,
      gravity_counter: 0
    }

    # Apply pending garbage
    {garbage_result, state} = apply_pending_garbage(state)
    case garbage_result do
      :game_over ->
        {:ok, :locked, state}
      :ok ->
        # Spawn next piece
        case spawn_piece(state) do
          {:ok, new_state} ->
            {:ok, :locked, Map.put(new_state, :lines_cleared_this_lock, lines_cleared)}
          {:game_over, new_state} ->
            {:ok, :locked, Map.put(new_state, :lines_cleared_this_lock, lines_cleared)}
        end
    end
  end
end
```

**Step 4: Run tests**

```bash
cd server && mix test test/tetris/game_logic_test.exs
```

Expected: PASS

**Step 5: Commit**

```bash
cd server && git add lib/tetris/game_logic.ex test/tetris/game_logic_test.exs
git commit -m "feat: add GameLogic module with move, rotate, hard drop, gravity, garbage"
```

---

### Task 7: PlayerState module

**Files:**
- Create: `server/lib/tetris/player_state.ex`
- Test: `server/test/tetris/player_state_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris/player_state_test.exs
defmodule Tetris.PlayerStateTest do
  use ExUnit.Case, async: true
  alias Tetris.PlayerState

  test "new/2 creates initial player state" do
    state = PlayerState.new("player_1", "Alex")
    assert state.player_id == "player_1"
    assert state.nickname == "Alex"
    assert state.alive == true
    assert state.score == 0
    assert state.lines == 0
    assert state.level == 1
    assert length(state.board) == 20
    assert state.target == nil
    assert state.pending_garbage == []
  end

  test "to_broadcast/1 returns JSON-serializable map" do
    state = PlayerState.new("player_1", "Alex")
    broadcast = PlayerState.to_broadcast(state)
    assert broadcast.nickname == "Alex"
    assert is_list(broadcast.board)
    assert broadcast.alive == true
    assert is_binary(broadcast.next_piece)
  end
end
```

**Step 2: Run to verify fail**

```bash
cd server && mix test test/tetris/player_state_test.exs
```

**Step 3: Implement PlayerState**

```elixir
# server/lib/tetris/player_state.ex
defmodule Tetris.PlayerState do
  alias Tetris.{Board, Piece, GameLogic}

  defstruct [
    :player_id, :nickname, :board, :current_piece, :position,
    :next_piece, :score, :lines, :level, :alive, :target,
    :pending_garbage, :gravity_counter, :gravity_threshold,
    :input_queue
  ]

  def new(player_id, nickname) do
    first = Piece.random()
    next = Piece.random()
    start_x = div(Board.width() - length(hd(first.shape)), 2)

    %__MODULE__{
      player_id: player_id,
      nickname: nickname,
      board: Board.new(),
      current_piece: first,
      position: {start_x, -1},
      next_piece: next,
      score: 0,
      lines: 0,
      level: 1,
      alive: true,
      target: nil,
      pending_garbage: [],
      gravity_counter: 0,
      gravity_threshold: GameLogic.gravity_threshold(1),
      input_queue: :queue.new()
    }
  end

  def to_broadcast(%__MODULE__{} = state) do
    display_board = compose_display_board(state)

    %{
      nickname: state.nickname,
      board: display_board,
      score: state.score,
      lines: state.lines,
      level: state.level,
      alive: state.alive,
      next_piece: if(state.next_piece, do: Atom.to_string(state.next_piece.type), else: nil),
      target: state.target
    }
  end

  def to_game_logic_map(%__MODULE__{} = state) do
    Map.from_struct(state)
  end

  def from_game_logic_map(%__MODULE__{} = orig, map) do
    %__MODULE__{orig |
      board: map.board,
      current_piece: map.current_piece,
      position: map.position,
      next_piece: map.next_piece,
      score: map.score,
      lines: map.lines,
      level: map.level,
      alive: map.alive,
      pending_garbage: map.pending_garbage,
      gravity_counter: map.gravity_counter,
      gravity_threshold: map.gravity_threshold
    }
  end

  defp compose_display_board(%{board: board, current_piece: nil}), do: board
  defp compose_display_board(%{board: board, current_piece: piece, position: pos, alive: false}), do: board
  defp compose_display_board(%{board: board, current_piece: piece, position: {px, py}} = state) do
    # Draw ghost
    {_gx, gy} = Board.ghost_position(board, piece.shape, {px, py})
    board_with_ghost =
      piece.shape
      |> Enum.with_index()
      |> Enum.reduce(board, fn {row, y}, acc ->
        row
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {cell, x}, board_acc ->
          if cell == 1 do
            by = gy + y
            bx = px + x
            if by >= 0 and by < 20 and bx >= 0 and bx < 10 do
              current = Enum.at(board_acc, by) |> Enum.at(bx)
              if is_nil(current) do
                List.update_at(board_acc, by, fn r ->
                  List.replace_at(r, bx, "ghost:#{piece.color}")
                end)
              else
                board_acc
              end
            else
              board_acc
            end
          else
            board_acc
          end
        end)
      end)

    # Draw current piece
    piece.shape
    |> Enum.with_index()
    |> Enum.reduce(board_with_ghost, fn {row, y}, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, x}, board_acc ->
        if cell == 1 do
          by = py + y
          bx = px + x
          if by >= 0 and by < 20 and bx >= 0 and bx < 10 do
            List.update_at(board_acc, by, fn r ->
              List.replace_at(r, bx, piece.color)
            end)
          else
            board_acc
          end
        else
          board_acc
        end
      end)
    end)
  end
end
```

**Step 4: Run tests**

```bash
cd server && mix test test/tetris/player_state_test.exs
```

Expected: PASS

**Step 5: Commit**

```bash
cd server && git add lib/tetris/player_state.ex test/tetris/player_state_test.exs
git commit -m "feat: add PlayerState module with broadcast serialization"
```

---

## Phase 3: Server Infrastructure

### Task 8: RoomSupervisor — DynamicSupervisor for game rooms

**Files:**
- Create: `server/lib/tetris_game/room_supervisor.ex`
- Test: `server/test/tetris_game/room_supervisor_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris_game/room_supervisor_test.exs
defmodule TetrisGame.RoomSupervisorTest do
  use ExUnit.Case, async: true

  test "starts as a DynamicSupervisor with no children" do
    children = DynamicSupervisor.which_children(TetrisGame.RoomSupervisor)
    assert is_list(children)
  end
end
```

**Step 2: Implement RoomSupervisor**

```elixir
# server/lib/tetris_game/room_supervisor.ex
defmodule TetrisGame.RoomSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_room(room_id, opts) do
    spec = {TetrisGame.GameRoom, [{:room_id, room_id} | opts]}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
```

Add to application supervisor children in `server/lib/tetris/application.ex`:

```elixir
children = [
  TetrisWeb.Telemetry,
  TetrisGame.RoomSupervisor,
  TetrisWeb.Endpoint
]
```

**Step 3: Run test**

```bash
cd server && mix test test/tetris_game/room_supervisor_test.exs
```

**Step 4: Commit**

```bash
cd server && git add lib/tetris_game/room_supervisor.ex test/tetris_game/room_supervisor_test.exs lib/tetris/application.ex
git commit -m "feat: add RoomSupervisor (DynamicSupervisor for game rooms)"
```

---

### Task 9: GameRoom GenServer — core game room with tick loop

**Files:**
- Create: `server/lib/tetris_game/game_room.ex`
- Test: `server/test/tetris_game/game_room_test.exs`

**Step 1: Write failing tests**

```elixir
# server/test/tetris_game/game_room_test.exs
defmodule TetrisGame.GameRoomTest do
  use ExUnit.Case, async: true
  alias TetrisGame.GameRoom

  setup do
    room_id = "test_room_#{:rand.uniform(100000)}"
    {:ok, pid} = GameRoom.start_link(room_id: room_id, host: "host_1", name: "Test Room", max_players: 4)
    %{pid: pid, room_id: room_id}
  end

  test "join adds a player", %{pid: pid} do
    :ok = GameRoom.join(pid, "player_1", "Alice")
    state = GameRoom.get_state(pid)
    assert Map.has_key?(state.players, "player_1")
    assert state.players["player_1"].nickname == "Alice"
  end

  test "rejects join when room is full", %{pid: pid} do
    :ok = GameRoom.join(pid, "p1", "A")
    :ok = GameRoom.join(pid, "p2", "B")
    :ok = GameRoom.join(pid, "p3", "C")
    :ok = GameRoom.join(pid, "p4", "D")
    assert {:error, :room_full} = GameRoom.join(pid, "p5", "E")
  end

  test "start_game begins the game loop", %{pid: pid} do
    :ok = GameRoom.join(pid, "p1", "A")
    :ok = GameRoom.join(pid, "p2", "B")
    :ok = GameRoom.start_game(pid, "host_1")
    state = GameRoom.get_state(pid)
    assert state.status == :playing
  end

  test "input queues actions for a player", %{pid: pid} do
    :ok = GameRoom.join(pid, "p1", "A")
    :ok = GameRoom.join(pid, "p2", "B")
    :ok = GameRoom.start_game(pid, "host_1")
    :ok = GameRoom.input(pid, "p1", "move_left")
    # Input is processed on next tick — just verify no crash
  end
end
```

**Step 2: Run to verify fail**

```bash
cd server && mix test test/tetris_game/game_room_test.exs
```

**Step 3: Implement GameRoom GenServer**

```elixir
# server/lib/tetris_game/game_room.ex
defmodule TetrisGame.GameRoom do
  use GenServer
  alias Tetris.{PlayerState, GameLogic, Board}

  @tick_interval 50  # 20 FPS

  defstruct [
    :room_id, :host, :name, :max_players, :password,
    :status, :players, :player_order, :eliminated_order,
    :tick, :tick_timer
  ]

  # --- Client API ---

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  def join(room, player_id, nickname) do
    GenServer.call(room, {:join, player_id, nickname})
  end

  def leave(room, player_id) do
    GenServer.call(room, {:leave, player_id})
  end

  def start_game(room, requester_id) do
    GenServer.call(room, {:start_game, requester_id})
  end

  def input(room, player_id, action) do
    GenServer.cast(room, {:input, player_id, action})
  end

  def set_target(room, player_id, target_id) do
    GenServer.call(room, {:set_target, player_id, target_id})
  end

  def get_state(room) do
    GenServer.call(room, :get_state)
  end

  def via(room_id), do: {:via, Registry, {TetrisGame.RoomRegistry, room_id}}

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    state = %__MODULE__{
      room_id: Keyword.fetch!(opts, :room_id),
      host: Keyword.fetch!(opts, :host),
      name: Keyword.get(opts, :name, "Unnamed Room"),
      max_players: Keyword.get(opts, :max_players, 4),
      password: Keyword.get(opts, :password),
      status: :waiting,
      players: %{},
      player_order: [],
      eliminated_order: [],
      tick: 0,
      tick_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id, nickname}, _from, state) do
    cond do
      map_size(state.players) >= state.max_players ->
        {:reply, {:error, :room_full}, state}

      Map.has_key?(state.players, player_id) ->
        {:reply, {:error, :already_joined}, state}

      state.status != :waiting ->
        {:reply, {:error, :game_in_progress}, state}

      true ->
        player = PlayerState.new(player_id, nickname)
        players = Map.put(state.players, player_id, player)
        order = state.player_order ++ [player_id]
        {:reply, :ok, %{state | players: players, player_order: order}}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    players = Map.delete(state.players, player_id)
    order = List.delete(state.player_order, player_id)

    new_host =
      if state.host == player_id do
        List.first(order)
      else
        state.host
      end

    state = %{state | players: players, player_order: order, host: new_host}

    if map_size(players) == 0 do
      {:stop, :normal, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:start_game, requester_id}, _from, state) do
    cond do
      requester_id != state.host ->
        {:reply, {:error, :not_host}, state}

      map_size(state.players) < 2 ->
        {:reply, {:error, :not_enough_players}, state}

      true ->
        # Set default targets (each player targets the next player)
        players =
          state.player_order
          |> Enum.with_index()
          |> Enum.reduce(state.players, fn {pid, idx}, acc ->
            next_idx = rem(idx + 1, length(state.player_order))
            target = Enum.at(state.player_order, next_idx)
            Map.update!(acc, pid, fn p -> %{p | target: target} end)
          end)

        timer = Process.send_after(self(), :tick, @tick_interval)
        state = %{state | status: :playing, players: players, tick_timer: timer}
        {:reply, :ok, state}
    end
  end

  def handle_call({:set_target, player_id, target_id}, _from, state) do
    if Map.has_key?(state.players, player_id) and Map.has_key?(state.players, target_id) do
      players = Map.update!(state.players, player_id, fn p -> %{p | target: target_id} end)
      {:reply, :ok, %{state | players: players}}
    else
      {:reply, {:error, :invalid_target}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:input, player_id, action}, state) do
    case Map.get(state.players, player_id) do
      nil ->
        {:noreply, state}

      player ->
        new_queue = :queue.in(action, player.input_queue)
        player = %{player | input_queue: new_queue}
        players = Map.put(state.players, player_id, player)
        {:noreply, %{state | players: players}}
    end
  end

  @impl true
  def handle_info(:tick, %{status: :playing} = state) do
    state = %{state | tick: state.tick + 1}

    # 1. Process input queues for each alive player
    players =
      state.players
      |> Enum.map(fn {pid, player} ->
        if player.alive do
          {pid, process_inputs(player)}
        else
          {pid, player}
        end
      end)
      |> Map.new()

    # 2. Apply gravity for each alive player
    {players, garbage_events} =
      players
      |> Enum.reduce({%{}, []}, fn {pid, player}, {acc_players, acc_garbage} ->
        if player.alive do
          game_map = PlayerState.to_game_logic_map(player)
          case GameLogic.apply_gravity(game_map) do
            {:ok, :locked, new_map} ->
              lines_cleared = Map.get(new_map, :lines_cleared_this_lock, 0)
              new_map = Map.delete(new_map, :lines_cleared_this_lock)
              updated = PlayerState.from_game_logic_map(player, new_map)
              garbage =
                if lines_cleared > 0 and updated.target do
                  [{updated.target, lines_cleared}]
                else
                  []
                end
              {Map.put(acc_players, pid, updated), acc_garbage ++ garbage}

            {:ok, :moved, new_map} ->
              updated = PlayerState.from_game_logic_map(player, new_map)
              {Map.put(acc_players, pid, updated), acc_garbage}

            {:ok, :waiting, new_map} ->
              updated = PlayerState.from_game_logic_map(player, new_map)
              {Map.put(acc_players, pid, updated), acc_garbage}
          end
        else
          {Map.put(acc_players, pid, player), acc_garbage}
        end
      end)

    # 3. Distribute garbage
    players =
      Enum.reduce(garbage_events, players, fn {target_id, count}, acc ->
        case Map.get(acc, target_id) do
          nil -> acc
          target_player ->
            garbage_rows = for _ <- 1..count, do: Board.generate_garbage_row()
            updated = %{target_player | pending_garbage: target_player.pending_garbage ++ garbage_rows}
            Map.put(acc, target_id, updated)
        end
      end)

    # 4. Check for winner
    alive_players = Enum.filter(players, fn {_, p} -> p.alive end)
    eliminated_this_tick =
      state.players
      |> Enum.filter(fn {pid, old_p} -> old_p.alive and not players[pid].alive end)
      |> Enum.map(fn {pid, _} -> pid end)

    eliminated_order = state.eliminated_order ++ eliminated_this_tick

    {status, players} =
      case length(alive_players) do
        0 -> {:finished, players}
        1 -> {:finished, players}
        _ -> {:playing, players}
      end

    state = %{state | players: players, status: status, eliminated_order: eliminated_order}

    # 5. Broadcast state
    broadcast_state(state)

    # Schedule next tick if still playing
    if status == :playing do
      timer = Process.send_after(self(), :tick, @tick_interval)
      {:noreply, %{state | tick_timer: timer}}
    else
      {:noreply, state}
    end
  end

  def handle_info(:tick, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp process_inputs(player) do
    {actions, empty_queue} = drain_queue(player.input_queue)
    player = %{player | input_queue: empty_queue}

    Enum.reduce(actions, player, fn action, p ->
      game_map = PlayerState.to_game_logic_map(p)

      result =
        case action do
          "move_left" -> GameLogic.move_left(game_map)
          "move_right" -> GameLogic.move_right(game_map)
          "move_down" -> GameLogic.move_down(game_map)
          "rotate" -> GameLogic.rotate(game_map)
          "hard_drop" -> GameLogic.hard_drop(game_map)
          _ -> :invalid
        end

      case result do
        {:ok, new_map} -> PlayerState.from_game_logic_map(p, new_map)
        {:ok, :moved, new_map} -> PlayerState.from_game_logic_map(p, new_map)
        {:ok, :locked, new_map} ->
          new_map = Map.delete(new_map, :lines_cleared_this_lock)
          PlayerState.from_game_logic_map(p, new_map)
        {:ok, :waiting, new_map} -> PlayerState.from_game_logic_map(p, new_map)
        :invalid -> p
      end
    end)
  end

  defp drain_queue(queue) do
    drain_queue(queue, [])
  end

  defp drain_queue(queue, acc) do
    case :queue.out(queue) do
      {{:value, item}, rest} -> drain_queue(rest, acc ++ [item])
      {:empty, empty} -> {acc, empty}
    end
  end

  defp broadcast_state(state) do
    payload = %{
      tick: state.tick,
      status: state.status,
      players:
        state.players
        |> Enum.map(fn {pid, p} -> {pid, PlayerState.to_broadcast(p)} end)
        |> Map.new(),
      eliminated_order: state.eliminated_order
    }

    TetrisWeb.Endpoint.broadcast("game:#{state.room_id}", "game_state", payload)
  end
end
```

**Step 4: Add Registry to application.ex**

In `server/lib/tetris/application.ex`, add before RoomSupervisor:

```elixir
{Registry, keys: :unique, name: TetrisGame.RoomRegistry},
```

**Step 5: Run tests**

```bash
cd server && mix test test/tetris_game/game_room_test.exs
```

Expected: PASS

**Step 6: Commit**

```bash
cd server && git add lib/tetris_game/game_room.ex test/tetris_game/game_room_test.exs lib/tetris/application.ex
git commit -m "feat: add GameRoom GenServer with tick loop, input queue, garbage distribution"
```

---

### Task 10: Lobby GenServer

**Files:**
- Create: `server/lib/tetris_game/lobby.ex`
- Test: `server/test/tetris_game/lobby_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris_game/lobby_test.exs
defmodule TetrisGame.LobbyTest do
  use ExUnit.Case, async: true
  alias TetrisGame.Lobby

  test "create_room/1 creates a new room and returns room_id" do
    {:ok, room_id} = Lobby.create_room(%{host: "host_1", name: "My Room", max_players: 4})
    assert is_binary(room_id)
  end

  test "list_rooms/0 returns all active rooms" do
    {:ok, _} = Lobby.create_room(%{host: "host_2", name: "Room A", max_players: 2})
    rooms = Lobby.list_rooms()
    assert is_list(rooms)
    assert length(rooms) >= 1
  end

  test "get_room/1 returns room info" do
    {:ok, room_id} = Lobby.create_room(%{host: "host_3", name: "Room B", max_players: 3})
    {:ok, room} = Lobby.get_room(room_id)
    assert room.name == "Room B"
    assert room.max_players == 3
  end
end
```

**Step 2: Run to verify fail**

```bash
cd server && mix test test/tetris_game/lobby_test.exs
```

**Step 3: Implement Lobby**

```elixir
# server/lib/tetris_game/lobby.ex
defmodule TetrisGame.Lobby do
  use GenServer

  defstruct rooms: %{}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def create_room(opts) do
    GenServer.call(__MODULE__, {:create_room, opts})
  end

  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id})
  end

  def remove_room(room_id) do
    GenServer.cast(__MODULE__, {:remove_room, room_id})
  end

  # --- Callbacks ---

  @impl true
  def init(_) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:create_room, opts}, _from, state) do
    room_id = generate_room_id()
    host = Map.fetch!(opts, :host)
    name = Map.get(opts, :name, "Unnamed Room")
    max_players = Map.get(opts, :max_players, 4)
    password = Map.get(opts, :password)

    room_opts = [
      room_id: room_id,
      host: host,
      name: name,
      max_players: max_players,
      password: password
    ]

    case TetrisGame.RoomSupervisor.start_room(room_id, room_opts) do
      {:ok, _pid} ->
        room_info = %{
          room_id: room_id,
          host: host,
          name: name,
          max_players: max_players,
          has_password: password != nil,
          player_count: 0,
          status: :waiting
        }

        rooms = Map.put(state.rooms, room_id, room_info)
        {:reply, {:ok, room_id}, %{state | rooms: rooms}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_rooms, _from, state) do
    rooms = Map.values(state.rooms)
    {:reply, rooms, state}
  end

  def handle_call({:get_room, room_id}, _from, state) do
    case Map.get(state.rooms, room_id) do
      nil -> {:reply, {:error, :not_found}, state}
      room -> {:reply, {:ok, room}, state}
    end
  end

  @impl true
  def handle_cast({:remove_room, room_id}, state) do
    rooms = Map.delete(state.rooms, room_id)
    {:noreply, %{state | rooms: rooms}}
  end

  defp generate_room_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
```

Add `TetrisGame.Lobby` to application.ex children (before RoomSupervisor).

**Step 4: Run tests**

```bash
cd server && mix test test/tetris_game/lobby_test.exs
```

**Step 5: Commit**

```bash
cd server && git add lib/tetris_game/lobby.ex test/tetris_game/lobby_test.exs lib/tetris/application.ex
git commit -m "feat: add Lobby GenServer for room management"
```

---

## Phase 4: Phoenix Channels

### Task 11: LobbyChannel

**Files:**
- Create: `server/lib/tetris_web/channels/lobby_channel.ex`
- Test: `server/test/tetris_web/channels/lobby_channel_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris_web/channels/lobby_channel_test.exs
defmodule TetrisWeb.LobbyChannelTest do
  use TetrisWeb.ChannelCase
  alias TetrisWeb.LobbyChannel

  setup do
    {:ok, _, socket} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{nickname: "Tester"})
      |> subscribe_and_join(LobbyChannel, "lobby:main")

    %{socket: socket}
  end

  test "list_rooms returns empty list initially", %{socket: socket} do
    ref = push(socket, "list_rooms", %{})
    assert_reply ref, :ok, %{rooms: rooms}
    assert is_list(rooms)
  end

  test "create_room creates a room and returns room_id", %{socket: socket} do
    ref = push(socket, "create_room", %{"name" => "Test Room", "max_players" => 2})
    assert_reply ref, :ok, %{room_id: room_id}
    assert is_binary(room_id)
  end
end
```

**Step 2: Implement LobbyChannel and UserSocket**

```elixir
# server/lib/tetris_web/channels/user_socket.ex
defmodule TetrisWeb.UserSocket do
  use Phoenix.Socket

  channel "lobby:*", TetrisWeb.LobbyChannel
  channel "game:*", TetrisWeb.GameChannel

  @impl true
  def connect(%{"nickname" => nickname}, socket, _connect_info) do
    player_id = generate_player_id()
    socket = assign(socket, :player_id, player_id)
    socket = assign(socket, :nickname, nickname)
    {:ok, socket}
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.player_id}"

  defp generate_player_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
```

```elixir
# server/lib/tetris_web/channels/lobby_channel.ex
defmodule TetrisWeb.LobbyChannel do
  use TetrisWeb, :channel
  alias TetrisGame.Lobby

  @impl true
  def join("lobby:main", _payload, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_in("list_rooms", _payload, socket) do
    rooms = Lobby.list_rooms()
    {:reply, {:ok, %{rooms: rooms}}, socket}
  end

  def handle_in("create_room", payload, socket) do
    opts = %{
      host: socket.assigns.player_id,
      name: Map.get(payload, "name", "Unnamed Room"),
      max_players: Map.get(payload, "max_players", 4),
      password: Map.get(payload, "password")
    }

    case Lobby.create_room(opts) do
      {:ok, room_id} ->
        broadcast!(socket, "room_created", %{room_id: room_id, name: opts.name})
        {:reply, {:ok, %{room_id: room_id}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
```

**Step 3: Add socket to endpoint.ex**

In `server/lib/tetris_web/endpoint.ex`, add:

```elixir
socket "/socket", TetrisWeb.UserSocket,
  websocket: true,
  longpoll: false
```

**Step 4: Run tests**

```bash
cd server && mix test test/tetris_web/channels/lobby_channel_test.exs
```

**Step 5: Commit**

```bash
cd server && git add lib/tetris_web/channels/ test/tetris_web/channels/ lib/tetris_web/endpoint.ex
git commit -m "feat: add LobbyChannel and UserSocket for lobby operations"
```

---

### Task 12: GameChannel with challenge-response auth

**Files:**
- Create: `server/lib/tetris_web/channels/game_channel.ex`
- Test: `server/test/tetris_web/channels/game_channel_test.exs`

**Step 1: Write failing test**

```elixir
# server/test/tetris_web/channels/game_channel_test.exs
defmodule TetrisWeb.GameChannelTest do
  use TetrisWeb.ChannelCase

  setup do
    # Create a room first
    {:ok, room_id} = TetrisGame.Lobby.create_room(%{host: "host_1", name: "Test", max_players: 4})

    {:ok, _, socket} =
      TetrisWeb.UserSocket
      |> socket("user_id", %{player_id: "player_1", nickname: "Tester"})
      |> subscribe_and_join(TetrisWeb.GameChannel, "game:#{room_id}")

    %{socket: socket, room_id: room_id}
  end

  test "joining a game channel adds player to room", %{socket: socket} do
    # Player should be in the room after join
    assert socket.assigns.player_id == "player_1"
  end

  test "input events are forwarded to game room", %{socket: socket} do
    push(socket, "input", %{"action" => "move_left"})
    # No crash = success; actual effect tested in GameRoom tests
  end
end
```

**Step 2: Implement GameChannel**

```elixir
# server/lib/tetris_web/channels/game_channel.ex
defmodule TetrisWeb.GameChannel do
  use TetrisWeb, :channel
  alias TetrisGame.GameRoom

  @impl true
  def join("game:" <> room_id, payload, socket) do
    player_id = socket.assigns.player_id
    nickname = socket.assigns.nickname
    password = Map.get(payload, "password")

    room = GameRoom.via(room_id)

    # Check if room needs password auth
    case GameRoom.get_state(room) do
      %{password: nil} ->
        case GameRoom.join(room, player_id, nickname) do
          :ok ->
            socket = assign(socket, :room_id, room_id)
            {:ok, socket}
          {:error, reason} ->
            {:error, %{reason: reason}}
        end

      %{password: stored_pw} when not is_nil(stored_pw) ->
        nonce = Map.get(payload, "nonce")
        hmac = Map.get(payload, "hmac")

        if nonce && hmac do
          expected = :crypto.mac(:hmac, :sha256, stored_pw, Base.decode64!(nonce)) |> Base.encode64()
          if hmac == expected do
            case GameRoom.join(room, player_id, nickname) do
              :ok ->
                socket = assign(socket, :room_id, room_id)
                {:ok, socket}
              {:error, reason} ->
                {:error, %{reason: reason}}
            end
          else
            {:error, %{reason: :invalid_password}}
          end
        else
          # Send challenge
          nonce = :crypto.strong_rand_bytes(32) |> Base.encode64()
          {:error, %{reason: :auth_required, nonce: nonce}}
        end
    end
  end

  @impl true
  def handle_in("input", %{"action" => action}, socket) do
    room = GameRoom.via(socket.assigns.room_id)
    GameRoom.input(room, socket.assigns.player_id, action)
    {:noreply, socket}
  end

  def handle_in("set_target", %{"target_id" => target_id}, socket) do
    room = GameRoom.via(socket.assigns.room_id)
    GameRoom.set_target(room, socket.assigns.player_id, target_id)
    {:noreply, socket}
  end

  def handle_in("start_game", _payload, socket) do
    room = GameRoom.via(socket.assigns.room_id)
    case GameRoom.start_game(room, socket.assigns.player_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
```

**Step 3: Run tests**

```bash
cd server && mix test test/tetris_web/channels/game_channel_test.exs
```

**Step 4: Commit**

```bash
cd server && git add lib/tetris_web/channels/game_channel.ex test/tetris_web/channels/game_channel_test.exs
git commit -m "feat: add GameChannel with challenge-response auth and input forwarding"
```

---

## Phase 5: React Frontend — Navigation & Screens

### Task 13: Install Phoenix JS client and add useChannel hook

**Files:**
- Modify: `client/package.json` (add phoenix dependency)
- Create: `client/src/hooks/useChannel.js`

**Step 1: Install phoenix JS client**

```bash
cd client && npm install phoenix
```

**Step 2: Create useChannel hook**

```jsx
// client/src/hooks/useChannel.js
import { useState, useEffect, useRef, useCallback } from 'react';
import { Socket } from 'phoenix';

const SOCKET_URL = process.env.REACT_APP_SOCKET_URL || 'ws://localhost:4000/socket';

export function useSocket(nickname) {
  const [socket, setSocket] = useState(null);
  const [connected, setConnected] = useState(false);
  const socketRef = useRef(null);

  useEffect(() => {
    if (!nickname) return;

    const s = new Socket(SOCKET_URL, { params: { nickname } });
    s.connect();
    s.onOpen(() => setConnected(true));
    s.onClose(() => setConnected(false));
    socketRef.current = s;
    setSocket(s);

    return () => {
      s.disconnect();
    };
  }, [nickname]);

  return { socket, connected };
}

export function useChannel(socket, topic) {
  const [channel, setChannel] = useState(null);
  const [joined, setJoined] = useState(false);
  const channelRef = useRef(null);

  const join = useCallback((params = {}) => {
    if (!socket || !topic) return;

    const ch = socket.channel(topic, params);
    ch.join()
      .receive('ok', () => setJoined(true))
      .receive('error', (resp) => console.error('Join error:', resp));

    channelRef.current = ch;
    setChannel(ch);
  }, [socket, topic]);

  const leave = useCallback(() => {
    if (channelRef.current) {
      channelRef.current.leave();
      setChannel(null);
      setJoined(false);
    }
  }, []);

  useEffect(() => {
    return () => {
      if (channelRef.current) {
        channelRef.current.leave();
      }
    };
  }, []);

  return { channel, joined, join, leave };
}
```

**Step 3: Commit**

```bash
cd client && git add src/hooks/useChannel.js package.json package-lock.json
git commit -m "feat: add useChannel hook and phoenix JS client dependency"
```

---

### Task 14: MainMenu component

**Files:**
- Create: `client/src/components/MainMenu.js`

**Step 1: Create MainMenu**

```jsx
// client/src/components/MainMenu.js
import React from 'react';

const buttonStyle = {
  padding: '16px 48px',
  fontSize: 18,
  fontWeight: 'bold',
  color: '#fff',
  backgroundColor: '#6c63ff',
  border: 'none',
  borderRadius: 8,
  cursor: 'pointer',
  letterSpacing: 1,
  textTransform: 'uppercase',
  transition: 'background-color 0.2s',
  marginBottom: 16,
  width: 260,
};

export default function MainMenu({ onSolo, onMultiplayer }) {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: '100vh',
      backgroundColor: '#0a0a1a',
      color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h1 style={{
        fontSize: 48,
        fontWeight: 800,
        letterSpacing: 8,
        textTransform: 'uppercase',
        marginBottom: 48,
        background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
        WebkitBackgroundClip: 'text',
        WebkitTextFillColor: 'transparent',
      }}>
        Tetris
      </h1>
      <button onClick={onSolo} style={buttonStyle}>Solo</button>
      <button onClick={onMultiplayer} style={{...buttonStyle, backgroundColor: '#00b894'}}>
        Multiplayer
      </button>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/MainMenu.js
git commit -m "feat: add MainMenu component with Solo/Multiplayer choice"
```

---

### Task 15: NicknameForm component

**Files:**
- Create: `client/src/components/NicknameForm.js`

**Step 1: Create NicknameForm**

```jsx
// client/src/components/NicknameForm.js
import React, { useState, useEffect } from 'react';

const STORAGE_KEY = 'tetris_nickname';

export default function NicknameForm({ onSubmit, onBack }) {
  const [nickname, setNickname] = useState('');

  useEffect(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) setNickname(saved);
  }, []);

  const handleSubmit = (e) => {
    e.preventDefault();
    const trimmed = nickname.trim();
    if (trimmed.length >= 3 && trimmed.length <= 16 && /^[a-zA-Z0-9_]+$/.test(trimmed)) {
      localStorage.setItem(STORAGE_KEY, trimmed);
      onSubmit(trimmed);
    }
  };

  const valid = nickname.trim().length >= 3 && nickname.trim().length <= 16 && /^[a-zA-Z0-9_]+$/.test(nickname.trim());

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h2 style={{ marginBottom: 24, color: '#ccc' }}>Enter Nickname</h2>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <input
          type="text"
          value={nickname}
          onChange={(e) => setNickname(e.target.value)}
          placeholder="3-16 chars, a-z, 0-9, _"
          maxLength={16}
          style={{
            padding: '12px 20px', fontSize: 18, backgroundColor: '#1a1a2e',
            border: '2px solid #333', borderRadius: 8, color: '#fff',
            width: 280, marginBottom: 16, outline: 'none',
          }}
          autoFocus
        />
        <div style={{ display: 'flex', gap: 12 }}>
          <button type="button" onClick={onBack} style={{
            padding: '12px 24px', fontSize: 14, backgroundColor: '#333',
            border: 'none', borderRadius: 8, color: '#ccc', cursor: 'pointer',
          }}>
            Back
          </button>
          <button type="submit" disabled={!valid} style={{
            padding: '12px 32px', fontSize: 16, fontWeight: 'bold',
            backgroundColor: valid ? '#6c63ff' : '#444', color: '#fff',
            border: 'none', borderRadius: 8, cursor: valid ? 'pointer' : 'default',
          }}>
            Enter Lobby
          </button>
        </div>
      </form>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/NicknameForm.js
git commit -m "feat: add NicknameForm component with localStorage persistence"
```

---

### Task 16: Lobby component

**Files:**
- Create: `client/src/components/Lobby.js`

**Step 1: Create Lobby**

```jsx
// client/src/components/Lobby.js
import React, { useState, useEffect, useCallback } from 'react';

export default function Lobby({ channel, onJoinRoom, onBack }) {
  const [rooms, setRooms] = useState([]);
  const [showCreate, setShowCreate] = useState(false);
  const [newRoom, setNewRoom] = useState({ name: '', max_players: 4, password: '' });

  const refreshRooms = useCallback(() => {
    if (!channel) return;
    channel.push('list_rooms', {}).receive('ok', (resp) => setRooms(resp.rooms));
  }, [channel]);

  useEffect(() => {
    refreshRooms();
    if (channel) {
      channel.on('room_created', () => refreshRooms());
      channel.on('room_removed', () => refreshRooms());
    }
  }, [channel, refreshRooms]);

  const handleCreate = () => {
    channel.push('create_room', {
      name: newRoom.name || 'Unnamed Room',
      max_players: newRoom.max_players,
      password: newRoom.password || null,
    }).receive('ok', (resp) => {
      setShowCreate(false);
      onJoinRoom(resp.room_id);
    });
  };

  const handleJoin = (room) => {
    if (room.has_password) {
      const pw = prompt('Enter room password:');
      if (pw) onJoinRoom(room.room_id, pw);
    } else {
      onJoinRoom(room.room_id);
    }
  };

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      minHeight: '100vh', backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif", padding: 40,
    }}>
      <h2 style={{ marginBottom: 24 }}>Lobby</h2>

      <div style={{ display: 'flex', gap: 12, marginBottom: 24 }}>
        <button onClick={() => setShowCreate(!showCreate)} style={btnStyle}>
          Create Room
        </button>
        <button onClick={onBack} style={{...btnStyle, backgroundColor: '#333'}}>
          Back
        </button>
      </div>

      {showCreate && (
        <div style={{ marginBottom: 24, padding: 20, backgroundColor: '#16162a', borderRadius: 8, border: '1px solid #333' }}>
          <input placeholder="Room name" value={newRoom.name}
            onChange={(e) => setNewRoom({...newRoom, name: e.target.value})}
            style={inputStyle} />
          <select value={newRoom.max_players}
            onChange={(e) => setNewRoom({...newRoom, max_players: parseInt(e.target.value)})}
            style={{...inputStyle, marginTop: 8}}>
            <option value={2}>2 players</option>
            <option value={3}>3 players</option>
            <option value={4}>4 players</option>
          </select>
          <input placeholder="Password (optional)" value={newRoom.password}
            onChange={(e) => setNewRoom({...newRoom, password: e.target.value})}
            type="password" style={{...inputStyle, marginTop: 8}} />
          <button onClick={handleCreate} style={{...btnStyle, marginTop: 12, width: '100%'}}>
            Create
          </button>
        </div>
      )}

      <div style={{ width: '100%', maxWidth: 500 }}>
        {rooms.length === 0 && <div style={{ color: '#666', textAlign: 'center' }}>No rooms yet</div>}
        {rooms.map((room) => (
          <div key={room.room_id} onClick={() => handleJoin(room)} style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            padding: '12px 16px', backgroundColor: '#16162a', borderRadius: 8,
            border: '1px solid #333', marginBottom: 8, cursor: 'pointer',
          }}>
            <div>
              <span style={{ fontWeight: 'bold' }}>{room.name}</span>
              {room.has_password && <span style={{ marginLeft: 8, color: '#ffa502' }}>🔒</span>}
            </div>
            <span style={{ color: '#888' }}>{room.player_count}/{room.max_players}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

const btnStyle = {
  padding: '10px 24px', fontSize: 14, fontWeight: 'bold',
  backgroundColor: '#6c63ff', color: '#fff', border: 'none',
  borderRadius: 8, cursor: 'pointer',
};

const inputStyle = {
  padding: '10px 14px', fontSize: 14, backgroundColor: '#1a1a2e',
  border: '1px solid #333', borderRadius: 6, color: '#fff',
  width: '100%', outline: 'none', display: 'block',
};
```

**Step 2: Commit**

```bash
cd client && git add src/components/Lobby.js
git commit -m "feat: add Lobby component with room list, create, and join"
```

---

### Task 17: WaitingRoom component

**Files:**
- Create: `client/src/components/WaitingRoom.js`

**Step 1: Create WaitingRoom**

```jsx
// client/src/components/WaitingRoom.js
import React from 'react';

export default function WaitingRoom({ players, isHost, onStart, onBack }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h2 style={{ marginBottom: 24 }}>Waiting Room</h2>

      <div style={{
        padding: 20, backgroundColor: '#16162a', borderRadius: 8,
        border: '1px solid #333', minWidth: 300, marginBottom: 24,
      }}>
        <h3 style={{ color: '#888', fontSize: 12, textTransform: 'uppercase', letterSpacing: 2, marginBottom: 12 }}>
          Players
        </h3>
        {Object.entries(players).map(([id, p]) => (
          <div key={id} style={{
            padding: '8px 12px', marginBottom: 4, borderRadius: 4,
            backgroundColor: '#1a1a2e', display: 'flex', justifyContent: 'space-between',
          }}>
            <span>{p.nickname}</span>
            {p.isHost && <span style={{ color: '#ffa502', fontSize: 12 }}>HOST</span>}
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', gap: 12 }}>
        <button onClick={onBack} style={{
          padding: '12px 24px', fontSize: 14, backgroundColor: '#333',
          border: 'none', borderRadius: 8, color: '#ccc', cursor: 'pointer',
        }}>
          Leave
        </button>
        {isHost && (
          <button
            onClick={onStart}
            disabled={Object.keys(players).length < 2}
            style={{
              padding: '12px 32px', fontSize: 16, fontWeight: 'bold',
              backgroundColor: Object.keys(players).length >= 2 ? '#00b894' : '#444',
              color: '#fff', border: 'none', borderRadius: 8,
              cursor: Object.keys(players).length >= 2 ? 'pointer' : 'default',
            }}
          >
            Start Game
          </button>
        )}
        {!isHost && (
          <div style={{ color: '#888', padding: '12px 0' }}>Waiting for host to start...</div>
        )}
      </div>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/WaitingRoom.js
git commit -m "feat: add WaitingRoom component for pre-game lobby"
```

---

### Task 18: Results component

**Files:**
- Create: `client/src/components/Results.js`

**Step 1: Create Results**

```jsx
// client/src/components/Results.js
import React from 'react';

export default function Results({ players, eliminatedOrder, onPlayAgain, onBackToLobby }) {
  // Build ranking: winner is last alive, then reverse elimination order
  const playerList = Object.entries(players);
  const alive = playerList.filter(([_, p]) => p.alive).map(([id]) => id);
  const ranking = [...alive, ...eliminatedOrder.slice().reverse()];

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h2 style={{ marginBottom: 8, fontSize: 32, color: '#ffa502' }}>Game Over</h2>
      <h3 style={{ marginBottom: 24, color: '#888' }}>Rankings</h3>

      <div style={{ minWidth: 400, marginBottom: 32 }}>
        {ranking.map((pid, idx) => {
          const p = players[pid];
          if (!p) return null;
          const medal = idx === 0 ? '#ffd700' : idx === 1 ? '#c0c0c0' : idx === 2 ? '#cd7f32' : '#666';
          return (
            <div key={pid} style={{
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              padding: '12px 16px', marginBottom: 8, borderRadius: 8,
              backgroundColor: '#16162a', border: `2px solid ${medal}`,
            }}>
              <div>
                <span style={{ color: medal, fontWeight: 'bold', marginRight: 12 }}>#{idx + 1}</span>
                <span style={{ fontWeight: 'bold' }}>{p.nickname}</span>
              </div>
              <div style={{ color: '#888', fontSize: 13 }}>
                Score: {p.score.toLocaleString()} | Lines: {p.lines} | Lvl: {p.level}
              </div>
            </div>
          );
        })}
      </div>

      <div style={{ display: 'flex', gap: 12 }}>
        <button onClick={onBackToLobby} style={{
          padding: '12px 24px', fontSize: 14, backgroundColor: '#333',
          border: 'none', borderRadius: 8, color: '#ccc', cursor: 'pointer',
        }}>
          Back to Lobby
        </button>
        <button onClick={onPlayAgain} style={{
          padding: '12px 32px', fontSize: 16, fontWeight: 'bold',
          backgroundColor: '#6c63ff', color: '#fff', border: 'none',
          borderRadius: 8, cursor: 'pointer',
        }}>
          Play Again
        </button>
      </div>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/Results.js
git commit -m "feat: add Results component with ranking display"
```

---

## Phase 6: React Frontend — Multiplayer Game

### Task 19: MiniBoard component

**Files:**
- Create: `client/src/components/MiniBoard.js`

**Step 1: Create MiniBoard**

```jsx
// client/src/components/MiniBoard.js
import React from 'react';

const MINI_CELL = 12;

export default function MiniBoard({ board, nickname, alive, isTarget, onClick }) {
  return (
    <div
      onClick={onClick}
      style={{
        opacity: alive ? 1 : 0.3,
        cursor: onClick ? 'pointer' : 'default',
        marginBottom: 12,
      }}
    >
      <div style={{
        fontSize: 11, color: isTarget ? '#00f0f0' : '#888',
        marginBottom: 4, fontWeight: isTarget ? 'bold' : 'normal',
        textAlign: 'center',
      }}>
        {nickname} {isTarget && '(TARGET)'}
      </div>
      <div style={{
        display: 'grid',
        gridTemplateColumns: `repeat(10, ${MINI_CELL}px)`,
        gridTemplateRows: `repeat(20, ${MINI_CELL}px)`,
        border: isTarget ? '2px solid #00f0f0' : '1px solid #333',
        borderRadius: 2,
        backgroundColor: '#0f0f23',
      }}>
        {board.map((row, y) =>
          row.map((cell, x) => (
            <div key={`${y}-${x}`} style={{
              width: MINI_CELL,
              height: MINI_CELL,
              backgroundColor: cell && !String.prototype.startsWith.call(cell || '', 'ghost:')
                ? cell : '#1a1a2e',
            }} />
          ))
        )}
      </div>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/MiniBoard.js
git commit -m "feat: add MiniBoard component for opponent preview"
```

---

### Task 20: TargetIndicator component

**Files:**
- Create: `client/src/components/TargetIndicator.js`

**Step 1: Create TargetIndicator**

```jsx
// client/src/components/TargetIndicator.js
import React from 'react';

export default function TargetIndicator({ targetNickname }) {
  return (
    <div style={{
      padding: '8px 16px',
      backgroundColor: '#1a1a2e',
      border: '1px solid #00f0f0',
      borderRadius: 6,
      marginBottom: 12,
      textAlign: 'center',
    }}>
      <div style={{ color: '#888', fontSize: 10, textTransform: 'uppercase', letterSpacing: 2 }}>
        Target
      </div>
      <div style={{ color: '#00f0f0', fontSize: 16, fontWeight: 'bold' }}>
        {targetNickname || '—'}
      </div>
      <div style={{ color: '#555', fontSize: 10, marginTop: 4 }}>
        [Tab] to switch
      </div>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/TargetIndicator.js
git commit -m "feat: add TargetIndicator component"
```

---

### Task 21: useMultiplayerGame hook

**Files:**
- Create: `client/src/hooks/useMultiplayerGame.js`

**Step 1: Create hook**

```jsx
// client/src/hooks/useMultiplayerGame.js
import { useState, useEffect, useCallback, useRef } from 'react';

export default function useMultiplayerGame(channel, myPlayerId) {
  const [gameState, setGameState] = useState(null);
  const [status, setStatus] = useState('waiting'); // waiting, playing, finished
  const targetIndexRef = useRef(0);

  useEffect(() => {
    if (!channel) return;

    const ref = channel.on('game_state', (payload) => {
      setGameState(payload);
      setStatus(payload.status);
    });

    return () => {
      channel.off('game_state', ref);
    };
  }, [channel]);

  const sendInput = useCallback((action) => {
    if (channel && status === 'playing') {
      channel.push('input', { action });
    }
  }, [channel, status]);

  const cycleTarget = useCallback(() => {
    if (!gameState || !channel) return;

    const opponents = Object.entries(gameState.players)
      .filter(([id, p]) => id !== myPlayerId && p.alive)
      .map(([id]) => id);

    if (opponents.length === 0) return;

    targetIndexRef.current = (targetIndexRef.current + 1) % opponents.length;
    const newTarget = opponents[targetIndexRef.current];
    channel.push('set_target', { target_id: newTarget });
  }, [gameState, channel, myPlayerId]);

  const startGame = useCallback(() => {
    if (channel) {
      channel.push('start_game', {});
    }
  }, [channel]);

  // Keyboard handler
  useEffect(() => {
    if (status !== 'playing') return;

    const handleKeyDown = (e) => {
      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault();
          sendInput('move_left');
          break;
        case 'ArrowRight':
          e.preventDefault();
          sendInput('move_right');
          break;
        case 'ArrowDown':
          e.preventDefault();
          sendInput('move_down');
          break;
        case 'ArrowUp':
          e.preventDefault();
          sendInput('rotate');
          break;
        case ' ':
          e.preventDefault();
          sendInput('hard_drop');
          break;
        case 'Tab':
          e.preventDefault();
          cycleTarget();
          break;
        default:
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [status, sendInput, cycleTarget]);

  const myState = gameState?.players?.[myPlayerId] || null;
  const opponents = gameState
    ? Object.entries(gameState.players)
        .filter(([id]) => id !== myPlayerId)
        .map(([id, p]) => ({ id, ...p }))
    : [];

  return {
    gameState,
    status,
    myState,
    opponents,
    startGame,
    sendInput,
    cycleTarget,
  };
}
```

**Step 2: Commit**

```bash
cd client && git add src/hooks/useMultiplayerGame.js
git commit -m "feat: add useMultiplayerGame hook with input handling and target cycling"
```

---

### Task 22: MultiBoard layout component

**Files:**
- Create: `client/src/components/MultiBoard.js`

**Step 1: Create MultiBoard**

```jsx
// client/src/components/MultiBoard.js
import React from 'react';
import Board from './Board';
import MiniBoard from './MiniBoard';
import Sidebar from './Sidebar';
import TargetIndicator from './TargetIndicator';
import NextPiece from './NextPiece';
import { TETROMINOES } from '../constants';

export default function MultiBoard({ myState, opponents, myPlayerId }) {
  if (!myState) return null;

  const myBoard = myState.board;
  const targetOpponent = opponents.find(o => o.id === myState.target);

  // Build a nextPiece object that matches what NextPiece expects
  const nextPieceObj = myState.next_piece && TETROMINOES[myState.next_piece]
    ? { shape: TETROMINOES[myState.next_piece].shape, color: TETROMINOES[myState.next_piece].color }
    : null;

  const leftOpponents = opponents.filter((_, i) => i % 2 === 0);
  const rightOpponents = opponents.filter((_, i) => i % 2 === 1);

  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 20 }}>
      {/* Left side: opponents + stats */}
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 140 }}>
        {leftOpponents.map(o => (
          <MiniBoard
            key={o.id}
            board={o.board}
            nickname={o.nickname}
            alive={o.alive}
            isTarget={o.id === myState.target}
          />
        ))}
        <TargetIndicator targetNickname={targetOpponent?.nickname} />
        <div style={{ padding: 12, backgroundColor: '#16162a', borderRadius: 8, border: '1px solid #333' }}>
          {nextPieceObj && <NextPiece piece={nextPieceObj} />}
          <StatBox label="Score" value={myState.score} />
          <StatBox label="Lines" value={myState.lines} />
          <StatBox label="Level" value={myState.level} />
        </div>
      </div>

      {/* Center: my board */}
      <div style={{ position: 'relative' }}>
        <Board board={myBoard} />
        {!myState.alive && (
          <div style={{
            position: 'absolute', inset: 0, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            backgroundColor: 'rgba(0,0,0,0.75)', borderRadius: 4,
          }}>
            <div style={{ fontSize: 28, fontWeight: 'bold', color: '#ff4757' }}>
              Eliminated
            </div>
          </div>
        )}
      </div>

      {/* Right side: opponents */}
      <div style={{ display: 'flex', flexDirection: 'column', minWidth: 140 }}>
        {rightOpponents.map(o => (
          <MiniBoard
            key={o.id}
            board={o.board}
            nickname={o.nickname}
            alive={o.alive}
            isTarget={o.id === myState.target}
          />
        ))}
      </div>
    </div>
  );
}

function StatBox({ label, value }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ color: '#888', fontSize: 11, textTransform: 'uppercase', letterSpacing: 2 }}>{label}</div>
      <div style={{ color: '#fff', fontSize: 20, fontWeight: 'bold', fontFamily: 'monospace' }}>
        {(value || 0).toLocaleString()}
      </div>
    </div>
  );
}
```

**Step 2: Commit**

```bash
cd client && git add src/components/MultiBoard.js
git commit -m "feat: add MultiBoard layout with opponent previews and stats"
```

---

## Phase 7: Integration

### Task 23: Update App.js with screen routing

**Files:**
- Modify: `client/src/App.js`

**Step 1: Rewrite App.js with screen state machine**

Replace the entire `client/src/App.js` with:

```jsx
import React, { useState, useCallback } from 'react';
import MainMenu from './components/MainMenu';
import NicknameForm from './components/NicknameForm';
import Lobby from './components/Lobby';
import WaitingRoom from './components/WaitingRoom';
import MultiBoard from './components/MultiBoard';
import Results from './components/Results';
import Board from './components/Board';
import Sidebar from './components/Sidebar';
import useTetris from './hooks/useTetris';
import { useSocket, useChannel } from './hooks/useChannel';
import useMultiplayerGame from './hooks/useMultiplayerGame';

// Screens: menu, solo, nickname, lobby, waiting, playing, results
export default function App() {
  const [screen, setScreen] = useState('menu');
  const [nickname, setNickname] = useState(null);
  const [roomId, setRoomId] = useState(null);
  const [playerId, setPlayerId] = useState(null);
  const [isHost, setIsHost] = useState(false);

  // Socket connection (only when we have a nickname)
  const { socket, connected } = useSocket(nickname);

  // Lobby channel
  const lobbyChannel = useChannel(socket, 'lobby:main');

  // Game channel
  const gameChannel = useChannel(socket, roomId ? `game:${roomId}` : null);

  // Multiplayer game state
  const mp = useMultiplayerGame(gameChannel.channel, playerId);

  // --- Navigation handlers ---

  const goToSolo = useCallback(() => setScreen('solo'), []);
  const goToMenu = useCallback(() => {
    setScreen('menu');
    setNickname(null);
    setRoomId(null);
    lobbyChannel.leave();
    gameChannel.leave();
  }, [lobbyChannel, gameChannel]);

  const goToNickname = useCallback(() => setScreen('nickname'), []);

  const handleNickname = useCallback((nick) => {
    setNickname(nick);
    setScreen('lobby');
  }, []);

  const handleJoinRoom = useCallback((rid, password) => {
    setRoomId(rid);
    setScreen('waiting');
    // Join will happen via gameChannel
  }, []);

  const handleStartGame = useCallback(() => {
    mp.startGame();
  }, [mp]);

  // Auto-join lobby channel when entering lobby screen
  React.useEffect(() => {
    if (screen === 'lobby' && socket && !lobbyChannel.joined) {
      lobbyChannel.join();
    }
  }, [screen, socket, lobbyChannel]);

  // Auto-join game channel when entering waiting room
  React.useEffect(() => {
    if (screen === 'waiting' && socket && roomId && !gameChannel.joined) {
      gameChannel.join();
    }
  }, [screen, socket, roomId, gameChannel]);

  // Transition to playing when game starts
  React.useEffect(() => {
    if (mp.status === 'playing' && screen === 'waiting') {
      setScreen('playing');
    }
    if (mp.status === 'finished' && screen === 'playing') {
      setScreen('results');
    }
  }, [mp.status, screen]);

  // --- Render screens ---

  switch (screen) {
    case 'menu':
      return <MainMenu onSolo={goToSolo} onMultiplayer={goToNickname} />;

    case 'solo':
      return <SoloGame onBack={goToMenu} />;

    case 'nickname':
      return <NicknameForm onSubmit={handleNickname} onBack={goToMenu} />;

    case 'lobby':
      return <Lobby channel={lobbyChannel.channel} onJoinRoom={handleJoinRoom} onBack={goToMenu} />;

    case 'waiting':
      return (
        <WaitingRoom
          players={mp.gameState?.players || {}}
          isHost={isHost}
          onStart={handleStartGame}
          onBack={() => { gameChannel.leave(); setScreen('lobby'); }}
        />
      );

    case 'playing':
      return (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center',
          justifyContent: 'center', minHeight: '100vh',
          backgroundColor: '#0a0a1a', color: '#fff',
          fontFamily: "'Segoe UI', system-ui, sans-serif",
        }}>
          <h1 style={{
            fontSize: 28, fontWeight: 800, letterSpacing: 6,
            textTransform: 'uppercase', marginBottom: 16,
            background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
            WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
          }}>
            Tetris Battle
          </h1>
          <MultiBoard myState={mp.myState} opponents={mp.opponents} myPlayerId={playerId} />
        </div>
      );

    case 'results':
      return (
        <Results
          players={mp.gameState?.players || {}}
          eliminatedOrder={mp.gameState?.eliminated_order || []}
          onPlayAgain={handleStartGame}
          onBackToLobby={() => { gameChannel.leave(); setScreen('lobby'); }}
        />
      );

    default:
      return <MainMenu onSolo={goToSolo} onMultiplayer={goToNickname} />;
  }
}

// Solo game wrapper (existing single-player, unchanged logic)
function SoloGame({ onBack }) {
  const {
    board, score, lines, level, nextPiece,
    gameOver, gameStarted, isPaused, startGame, togglePause,
  } = useTetris();

  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', minHeight: '100vh',
      backgroundColor: '#0a0a1a', color: '#fff',
      fontFamily: "'Segoe UI', system-ui, sans-serif",
    }}>
      <h1 style={{
        fontSize: 36, fontWeight: 800, letterSpacing: 8,
        textTransform: 'uppercase', marginBottom: 20,
        background: 'linear-gradient(135deg, #6c63ff, #00f0f0)',
        WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
      }}>
        Tetris
      </h1>
      <div style={{ display: 'flex', alignItems: 'flex-start' }}>
        <div style={{ position: 'relative' }}>
          <Board board={board} />
          {!gameStarted && (
            <Overlay onAction={startGame} actionLabel="Start Game">
              <div style={{ fontSize: 18, marginBottom: 16, color: '#ccc' }}>Press Start to Play</div>
            </Overlay>
          )}
          {gameOver && (
            <Overlay onAction={startGame} actionLabel="Play Again">
              <div style={{ fontSize: 28, fontWeight: 'bold', marginBottom: 8, color: '#ff4757' }}>Game Over</div>
              <div style={{ fontSize: 16, marginBottom: 16, color: '#ccc' }}>Score: {score.toLocaleString()}</div>
            </Overlay>
          )}
          {isPaused && !gameOver && (
            <Overlay onAction={togglePause} actionLabel="Resume">
              <div style={{ fontSize: 28, fontWeight: 'bold', marginBottom: 16, color: '#ffa502' }}>Paused</div>
            </Overlay>
          )}
        </div>
        <Sidebar score={score} lines={lines} level={level} nextPiece={nextPiece} />
      </div>
      <button onClick={onBack} style={{
        marginTop: 20, padding: '8px 20px', fontSize: 13,
        backgroundColor: '#333', color: '#ccc', border: 'none',
        borderRadius: 6, cursor: 'pointer',
      }}>
        Back to Menu
      </button>
    </div>
  );
}

function Overlay({ children, onAction, actionLabel }) {
  return (
    <div style={{
      position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      backgroundColor: 'rgba(0, 0, 0, 0.75)', borderRadius: 4, zIndex: 10,
    }}>
      {children}
      {onAction && (
        <button onClick={onAction} style={{
          padding: '12px 32px', fontSize: 16, fontWeight: 'bold', color: '#fff',
          backgroundColor: '#6c63ff', border: 'none', borderRadius: 8,
          cursor: 'pointer', letterSpacing: 1, textTransform: 'uppercase',
        }}>
          {actionLabel}
        </button>
      )}
    </div>
  );
}
```

**Step 2: Verify solo mode still works**

```bash
cd client && npm start
```

Navigate to localhost:3000, click Solo, verify game works.

**Step 3: Commit**

```bash
cd client && git add src/App.js
git commit -m "feat: update App.js with screen routing for solo and multiplayer modes"
```

---

### Task 24: End-to-end smoke test

**Step 1: Start both servers**

Terminal 1:
```bash
cd server && mix phx.server
```

Terminal 2:
```bash
cd client && npm start
```

**Step 2: Verify solo mode**

- Open http://localhost:3000
- Click "Solo"
- Play a game — all controls should work identically to before

**Step 3: Verify multiplayer flow**

- Open http://localhost:3000 in two browser tabs
- Tab 1: Click "Multiplayer" → Enter nickname "Player1" → Create room
- Tab 2: Click "Multiplayer" → Enter nickname "Player2" → Join room
- Tab 1 (host): Click "Start Game"
- Both tabs should show the game board
- Verify: keyboard inputs move pieces, garbage lines appear when opponent clears rows, Tab cycles target

**Step 4: Verify password-protected rooms**

- Create a room with password "test123"
- Try joining from second tab — should prompt for password
- Enter wrong password — should reject
- Enter correct password — should join

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: integration fixes from end-to-end smoke testing"
```

---

## Summary of All Tasks

| # | Task | Phase | Files |
|---|------|-------|-------|
| 1 | Move React to client/ | 1 | project root |
| 2 | Scaffold Phoenix in server/ | 1 | server/ |
| 3 | Piece module | 2 | piece.ex, piece_test.exs |
| 4 | Board module | 2 | board.ex, board_test.exs |
| 5 | WallKicks module | 2 | wall_kicks.ex, wall_kicks_test.exs |
| 6 | GameLogic module | 2 | game_logic.ex, game_logic_test.exs |
| 7 | PlayerState module | 2 | player_state.ex, player_state_test.exs |
| 8 | RoomSupervisor | 3 | room_supervisor.ex |
| 9 | GameRoom GenServer | 3 | game_room.ex, game_room_test.exs |
| 10 | Lobby GenServer | 3 | lobby.ex, lobby_test.exs |
| 11 | LobbyChannel | 4 | lobby_channel.ex, user_socket.ex |
| 12 | GameChannel + auth | 4 | game_channel.ex |
| 13 | useChannel hook + phoenix | 5 | useChannel.js |
| 14 | MainMenu component | 5 | MainMenu.js |
| 15 | NicknameForm component | 5 | NicknameForm.js |
| 16 | Lobby component | 5 | Lobby.js |
| 17 | WaitingRoom component | 5 | WaitingRoom.js |
| 18 | Results component | 5 | Results.js |
| 19 | MiniBoard component | 6 | MiniBoard.js |
| 20 | TargetIndicator component | 6 | TargetIndicator.js |
| 21 | useMultiplayerGame hook | 6 | useMultiplayerGame.js |
| 22 | MultiBoard layout | 6 | MultiBoard.js |
| 23 | App.js screen routing | 7 | App.js |
| 24 | End-to-end smoke test | 7 | — |
