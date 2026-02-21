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

  describe "sign_registration/1 and verify_registration/1" do
    @registration_data %{
      provider: "google",
      provider_id: "google_123",
      name: "John Smith",
      email: "john@example.com",
      avatar_url: "https://example.com/photo.jpg"
    }

    test "round-trips registration data" do
      token = Token.sign_registration(@registration_data)
      assert {:ok, data} = Token.verify_registration(token)
      assert data.provider == "google"
      assert data.provider_id == "google_123"
      assert data.name == "John Smith"
      assert data.email == "john@example.com"
      assert data.avatar_url == "https://example.com/photo.jpg"
    end

    test "rejects expired registration token" do
      token = Token.sign_registration(@registration_data, ttl: -1)
      assert {:error, :token_expired} = Token.verify_registration(token)
    end

    test "rejects tampered registration token" do
      token = Token.sign_registration(@registration_data)
      assert {:error, :invalid_token} = Token.verify_registration(token <> "x")
    end

    test "verify_registration rejects a normal auth token" do
      token = Token.sign(@test_user_id)
      assert {:error, :invalid_token} = Token.verify_registration(token)
    end

    test "verify rejects a registration token" do
      token = Token.sign_registration(@registration_data)
      assert {:error, :invalid_token} = Token.verify(token)
    end

    test "handles nil email and avatar_url" do
      data = %{@registration_data | email: nil, avatar_url: nil}
      token = Token.sign_registration(data)
      assert {:ok, decoded} = Token.verify_registration(token)
      assert decoded.email == nil
      assert decoded.avatar_url == nil
    end
  end
end
