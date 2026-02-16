defmodule Tetris.PieceTest do
  use ExUnit.Case, async: true

  alias Tetris.Piece

  describe "types/0" do
    test "returns all 7 tetromino types" do
      types = Piece.types()
      assert length(types) == 7
      assert :I in types
      assert :O in types
      assert :T in types
      assert :S in types
      assert :Z in types
      assert :J in types
      assert :L in types
    end
  end

  describe "new/1" do
    test "creates an I piece with correct shape, color, and rotation" do
      piece = Piece.new(:I)
      assert %Piece{type: :I, color: "#00f0f0", rotation: 0} = piece

      assert piece.shape == [
               [0, 0, 0, 0],
               [1, 1, 1, 1],
               [0, 0, 0, 0],
               [0, 0, 0, 0]
             ]
    end

    test "creates an O piece with correct shape, color, and rotation" do
      piece = Piece.new(:O)
      assert %Piece{type: :O, color: "#f0f000", rotation: 0} = piece

      assert piece.shape == [
               [1, 1],
               [1, 1]
             ]
    end

    test "creates a T piece with correct shape, color, and rotation" do
      piece = Piece.new(:T)
      assert %Piece{type: :T, color: "#a000f0", rotation: 0} = piece

      assert piece.shape == [
               [0, 1, 0],
               [1, 1, 1],
               [0, 0, 0]
             ]
    end

    test "creates an S piece with correct shape, color, and rotation" do
      piece = Piece.new(:S)
      assert %Piece{type: :S, color: "#00f000", rotation: 0} = piece

      assert piece.shape == [
               [0, 1, 1],
               [1, 1, 0],
               [0, 0, 0]
             ]
    end

    test "creates a Z piece with correct shape, color, and rotation" do
      piece = Piece.new(:Z)
      assert %Piece{type: :Z, color: "#f00000", rotation: 0} = piece

      assert piece.shape == [
               [1, 1, 0],
               [0, 1, 1],
               [0, 0, 0]
             ]
    end

    test "creates a J piece with correct shape, color, and rotation" do
      piece = Piece.new(:J)
      assert %Piece{type: :J, color: "#0000f0", rotation: 0} = piece

      assert piece.shape == [
               [1, 0, 0],
               [1, 1, 1],
               [0, 0, 0]
             ]
    end

    test "creates an L piece with correct shape, color, and rotation" do
      piece = Piece.new(:L)
      assert %Piece{type: :L, color: "#f0a000", rotation: 0} = piece

      assert piece.shape == [
               [0, 0, 1],
               [1, 1, 1],
               [0, 0, 0]
             ]
    end

    test "rotation defaults to 0" do
      for type <- Piece.types() do
        piece = Piece.new(type)
        assert piece.rotation == 0
      end
    end
  end

  describe "rotate/1" do
    test "rotates a T piece 90 degrees clockwise" do
      piece = Piece.new(:T)
      rotated = Piece.rotate(piece)

      # Original T:
      # [0, 1, 0]
      # [1, 1, 1]
      # [0, 0, 0]
      #
      # After 90 CW rotation (rotated[i][j] = original[N-1-j][i]):
      # [0, 1, 0]
      # [0, 1, 1]
      # [0, 1, 0]
      assert rotated.shape == [
               [0, 1, 0],
               [0, 1, 1],
               [0, 1, 0]
             ]
    end

    test "increments rotation field" do
      piece = Piece.new(:T)
      assert piece.rotation == 0

      rotated1 = Piece.rotate(piece)
      assert rotated1.rotation == 1

      rotated2 = Piece.rotate(rotated1)
      assert rotated2.rotation == 2

      rotated3 = Piece.rotate(rotated2)
      assert rotated3.rotation == 3
    end

    test "rotation wraps around mod 4" do
      piece = Piece.new(:T)

      rotated =
        piece
        |> Piece.rotate()
        |> Piece.rotate()
        |> Piece.rotate()
        |> Piece.rotate()

      assert rotated.rotation == 0
    end

    test "four rotations returns to original shape" do
      for type <- Piece.types() do
        piece = Piece.new(type)

        full_rotation =
          piece
          |> Piece.rotate()
          |> Piece.rotate()
          |> Piece.rotate()
          |> Piece.rotate()

        assert full_rotation.shape == piece.shape,
               "Four rotations of #{type} should return to original shape"
      end
    end

    test "rotates an I piece 90 degrees clockwise" do
      piece = Piece.new(:I)
      rotated = Piece.rotate(piece)

      # Original I:
      # [0, 0, 0, 0]
      # [1, 1, 1, 1]
      # [0, 0, 0, 0]
      # [0, 0, 0, 0]
      #
      # After 90 CW rotation (rotated[i][j] = original[N-1-j][i]):
      # row 0: original[3][0]=0, original[2][0]=0, original[1][0]=1, original[0][0]=0
      # [0, 0, 1, 0]
      # [0, 0, 1, 0]
      # [0, 0, 1, 0]
      # [0, 0, 1, 0]
      assert rotated.shape == [
               [0, 0, 1, 0],
               [0, 0, 1, 0],
               [0, 0, 1, 0],
               [0, 0, 1, 0]
             ]
    end

    test "O piece remains the same after rotation" do
      piece = Piece.new(:O)
      rotated = Piece.rotate(piece)

      assert rotated.shape == [
               [1, 1],
               [1, 1]
             ]

      assert rotated.rotation == 1
    end

    test "preserves type and color after rotation" do
      piece = Piece.new(:S)
      rotated = Piece.rotate(piece)

      assert rotated.type == :S
      assert rotated.color == "#00f000"
    end
  end

  describe "random/0" do
    test "returns a valid piece" do
      piece = Piece.random()
      assert %Piece{} = piece
      assert piece.type in Piece.types()
      assert piece.rotation == 0
    end

    test "returns pieces with valid shapes" do
      # Call random multiple times to increase confidence
      for _ <- 1..20 do
        piece = Piece.random()
        expected = Piece.new(piece.type)
        assert piece.shape == expected.shape
        assert piece.color == expected.color
      end
    end
  end
end
