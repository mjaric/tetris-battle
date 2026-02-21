defmodule Platform.Auth.TokenTest do
  use ExUnit.Case, async: true

  alias Platform.Auth.Token

  @test_user_id "550e8400-e29b-41d4-a716-446655440000"

  describe "sign/1 and verify/1" do
    test "round-trips a user_id" do
      token = Token.sign(@test_user_id)
      assert {:ok, @test_user_id} = Token.verify(token)
    end

    test "rejects a tampered token" do
      token = Token.sign(@test_user_id)
      tampered = token <> "x"
      assert {:error, :invalid_token} = Token.verify(tampered)
    end

    test "rejects a completely invalid string" do
      assert {:error, :invalid_token} = Token.verify("not.a.jwt")
    end

    test "rejects nil" do
      assert {:error, :invalid_token} = Token.verify(nil)
    end
  end

  describe "sign/2 with custom ttl" do
    test "rejects an expired token" do
      token = Token.sign(@test_user_id, ttl: -1)
      assert {:error, :token_expired} = Token.verify(token)
    end
  end
end
