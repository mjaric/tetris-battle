defmodule Platform.AccountsTest do
  use Platform.DataCase, async: true

  alias Platform.Accounts
  alias Platform.Accounts.User

  describe "create_user/1" do
    test "creates a user with valid attrs" do
      attrs = %{
        provider: "google",
        provider_id: "google_123",
        display_name: "TestUser",
        email: "test@example.com"
      }

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.provider == "google"
      assert user.provider_id == "google_123"
      assert user.display_name == "TestUser"
      assert user.is_anonymous == false
    end

    test "fails without required fields" do
      assert {:error, changeset} = Accounts.create_user(%{})
      errors = errors_on(changeset)
      assert errors[:provider_id]
      assert errors[:display_name]
    end

    test "fails on duplicate provider + provider_id" do
      attrs = %{
        provider: "google",
        provider_id: "dup_id",
        display_name: "User1"
      }

      assert {:ok, _} = Accounts.create_user(attrs)

      assert {:error, changeset} =
               Accounts.create_user(%{attrs | display_name: "User2"})

      assert %{provider: _} = errors_on(changeset)
    end
  end

  describe "find_or_create_user/1" do
    test "creates new user when not found" do
      attrs = %{
        provider: "github",
        provider_id: "new_uid",
        display_name: "NewUser"
      }

      assert {:ok, %User{}} = Accounts.find_or_create_user(attrs)
    end

    test "returns existing user when found" do
      attrs = %{
        provider: "github",
        provider_id: "existing_uid",
        display_name: "Existing"
      }

      {:ok, original} = Accounts.create_user(attrs)
      {:ok, found} = Accounts.find_or_create_user(attrs)
      assert found.id == original.id
    end
  end

  describe "get_user/1" do
    test "returns user by id" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "google",
          provider_id: "get_test",
          display_name: "GetTest"
        })

      assert %User{} = Accounts.get_user(user.id)
    end

    test "returns nil for nonexistent id" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "upgrade_anonymous_user/2" do
    test "upgrades anonymous user in-place" do
      {:ok, anon} =
        Accounts.create_user(%{
          provider: "anonymous",
          provider_id: Ecto.UUID.generate(),
          display_name: "Guest_abc",
          is_anonymous: true
        })

      upgrade_attrs = %{
        provider: "google",
        provider_id: "google_456",
        display_name: "RealUser",
        email: "real@example.com",
        is_anonymous: false
      }

      assert {:ok, upgraded} =
               Accounts.upgrade_anonymous_user(anon, upgrade_attrs)

      assert upgraded.id == anon.id
      assert upgraded.provider == "google"
      assert upgraded.provider_id == "google_456"
      assert upgraded.is_anonymous == false
    end

    test "no-op for non-anonymous user" do
      {:ok, user} =
        Accounts.create_user(%{
          provider: "google",
          provider_id: "already_real",
          display_name: "Already"
        })

      assert {:ok, same} =
               Accounts.upgrade_anonymous_user(user, %{provider: "github"})

      assert same.id == user.id
      assert same.provider == "google"
    end
  end

  describe "registration_changeset/2" do
    test "valid nickname" do
      user = %User{}

      changeset =
        User.registration_changeset(user, %{
          provider: "google",
          provider_id: "reg_1",
          display_name: "Test User",
          nickname: "TestNick"
        })

      assert changeset.valid?
      assert get_change(changeset, :nickname) == "TestNick"
    end

    test "rejects nickname shorter than 3 chars" do
      changeset =
        User.registration_changeset(%User{}, %{
          provider: "google",
          provider_id: "reg_2",
          display_name: "Test",
          nickname: "ab"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:nickname]
    end

    test "rejects nickname longer than 20 chars" do
      changeset =
        User.registration_changeset(%User{}, %{
          provider: "google",
          provider_id: "reg_3",
          display_name: "Test",
          nickname: String.duplicate("a", 21)
        })

      refute changeset.valid?
      assert errors_on(changeset)[:nickname]
    end

    test "rejects nickname starting with a digit" do
      changeset =
        User.registration_changeset(%User{}, %{
          provider: "google",
          provider_id: "reg_4",
          display_name: "Test",
          nickname: "1BadNick"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:nickname]
    end

    test "rejects nickname with special characters" do
      changeset =
        User.registration_changeset(%User{}, %{
          provider: "google",
          provider_id: "reg_5",
          display_name: "Test",
          nickname: "bad-nick!"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:nickname]
    end

    test "accepts nickname with underscores" do
      changeset =
        User.registration_changeset(%User{}, %{
          provider: "google",
          provider_id: "reg_6",
          display_name: "Test",
          nickname: "good_nick_1"
        })

      assert changeset.valid?
    end

    test "requires nickname" do
      changeset =
        User.registration_changeset(%User{}, %{
          provider: "google",
          provider_id: "reg_7",
          display_name: "Test"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:nickname]
    end
  end

  describe "search_users_by_name/2" do
    test "finds users by partial name match" do
      Accounts.create_user(%{
        provider: "a",
        provider_id: "u1",
        display_name: "AliceSmith"
      })

      Accounts.create_user(%{
        provider: "a",
        provider_id: "u2",
        display_name: "BobAlice"
      })

      Accounts.create_user(%{
        provider: "a",
        provider_id: "u3",
        display_name: "Charlie"
      })

      results = Accounts.search_users_by_name("Alice")
      assert length(results) == 2
    end

    test "excludes anonymous users" do
      Accounts.create_user(%{
        provider: "anonymous",
        provider_id: "anon1",
        display_name: "Alice",
        is_anonymous: true
      })

      assert Accounts.search_users_by_name("Alice") == []
    end

    test "sanitizes ILIKE special characters" do
      Accounts.create_user(%{
        provider: "a",
        provider_id: "u4",
        display_name: "Normal"
      })

      # These should not act as SQL wildcards
      assert Accounts.search_users_by_name("100%") == []
      assert Accounts.search_users_by_name("a_b") == []
    end
  end

  describe "register_user/1" do
    test "creates a user with nickname" do
      attrs = %{
        provider: "google",
        provider_id: "reg_new_1",
        display_name: "New User",
        email: "new@example.com",
        nickname: "NewPlayer"
      }

      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.nickname == "NewPlayer"
      assert user.display_name == "New User"
      assert user.is_anonymous == false
    end

    test "fails with duplicate nickname" do
      base = %{
        provider: "google",
        provider_id: "reg_dup_1",
        display_name: "User1",
        nickname: "TakenNick"
      }

      assert {:ok, _} = Accounts.register_user(base)

      assert {:error, changeset} =
               Accounts.register_user(%{
                 base
                 | provider_id: "reg_dup_2",
                   display_name: "User2"
               })

      assert errors_on(changeset)[:nickname]
    end

    test "fails with invalid nickname format" do
      assert {:error, changeset} =
               Accounts.register_user(%{
                 provider: "google",
                 provider_id: "reg_bad",
                 display_name: "Bad",
                 nickname: "1bad"
               })

      assert errors_on(changeset)[:nickname]
    end
  end

  describe "register_guest_upgrade/2" do
    test "upgrades anonymous user with nickname" do
      {:ok, anon} =
        Accounts.create_user(%{
          provider: "anonymous",
          provider_id: Ecto.UUID.generate(),
          display_name: "Guest_abc",
          is_anonymous: true
        })

      upgrade_attrs = %{
        provider: "google",
        provider_id: "google_upgrade_1",
        display_name: "Real Name",
        email: "real@example.com",
        nickname: "RealPlayer",
        is_anonymous: false
      }

      assert {:ok, upgraded} =
               Accounts.register_guest_upgrade(anon, upgrade_attrs)

      assert upgraded.id == anon.id
      assert upgraded.nickname == "RealPlayer"
      assert upgraded.provider == "google"
      assert upgraded.is_anonymous == false
    end

    test "rejects upgrade for non-anonymous user" do
      {:ok, user} =
        Accounts.register_user(%{
          provider: "google",
          provider_id: "not_anon_1",
          display_name: "NotAnon",
          nickname: "NotAnon"
        })

      assert {:error, :not_anonymous} =
               Accounts.register_guest_upgrade(user, %{
                 nickname: "NewNick"
               })
    end
  end

  describe "nickname_available?/1" do
    test "returns true for available nickname" do
      assert Accounts.nickname_available?("FreshNick")
    end

    test "returns false for taken nickname" do
      Accounts.register_user(%{
        provider: "google",
        provider_id: "taken_1",
        display_name: "Taken",
        nickname: "TakenName"
      })

      refute Accounts.nickname_available?("TakenName")
    end

    test "returns false for invalid format" do
      refute Accounts.nickname_available?("1bad")
    end

    test "returns false for too short" do
      refute Accounts.nickname_available?("ab")
    end
  end
end
