defmodule TetrisGame.BotNamesTest do
  use ExUnit.Case, async: true

  alias TetrisGame.BotNames

  describe "pick/1" do
    test "returns a name from the predefined list" do
      name = BotNames.pick()
      assert name in BotNames.all()
    end

    test "excludes names in the exclusion list" do
      excluded = Enum.take(BotNames.all(), 19)
      remaining = BotNames.all() -- excluded
      name = BotNames.pick(excluded)
      assert name in remaining
    end

    test "falls back to Bot-N when all names taken" do
      name = BotNames.pick(BotNames.all())
      assert String.starts_with?(name, "Bot-")
    end

    test "returns different names on repeated calls" do
      names = for _ <- 1..20, do: BotNames.pick()
      unique = Enum.uniq(names)
      assert length(unique) > 1
    end
  end

  describe "all/0" do
    test "returns 20 names" do
      assert length(BotNames.all()) == 20
    end

    test "all names are strings" do
      Enum.each(BotNames.all(), fn name ->
        assert is_binary(name)
      end)
    end
  end
end
