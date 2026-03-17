defmodule OmSchema.ConstraintsTest do
  @moduledoc """
  Tests for OmSchema.Constraints - Database constraint DSL.
  """

  use ExUnit.Case, async: true

  alias OmSchema.Constraints

  # ============================================
  # Test Schemas
  # ============================================

  defmodule UserWithConstraints do
    use OmSchema

    schema "constraints_test_users" do
      field :email, :string, unique: true
      field :username, :string, unique: :users_username_idx
      field :age, :integer, check: :users_age_positive
      field :status, :string

      constraints do
        unique [:account_id, :email], name: :users_account_email_idx
        check :valid_status, expr: "status IN ('active', 'inactive')"
        index :status, name: :users_status_idx
      end
    end
  end

  defmodule AccountWithForeignKeys do
    use OmSchema

    schema "constraints_test_accounts" do
      field :name, :string
    end
  end

  defmodule MembershipWithConstraints do
    use OmSchema

    schema "constraints_test_memberships" do
      field :role, :string

      constraints do
        foreign_key :user_id, references: :users, on_delete: :cascade
        foreign_key :account_id, references: :accounts, on_delete: :restrict
        exclude :no_overlap, using: :gist, expr: "room_id WITH =, tsrange(start_at, end_at) WITH &&"
      end
    end
  end

  # ============================================
  # normalize_unique_option/3 Tests
  # ============================================

  describe "normalize_unique_option/3" do
    test "normalizes true to default constraint name" do
      result = Constraints.normalize_unique_option(true, :users, :email)

      assert result == %{
               fields: [:email],
               name: :users_email_index,
               where: nil
             }
    end

    test "normalizes atom to custom constraint name" do
      result = Constraints.normalize_unique_option(:custom_idx, :users, :email)

      assert result == %{
               fields: [:email],
               name: :custom_idx,
               where: nil
             }
    end

    test "normalizes keyword list with name and where" do
      result =
        Constraints.normalize_unique_option(
          [name: :users_email_active_idx, where: "status = 'active'"],
          :users,
          :email
        )

      assert result == %{
               fields: [:email],
               name: :users_email_active_idx,
               where: "status = 'active'"
             }
    end

    test "normalizes keyword list with only where" do
      result = Constraints.normalize_unique_option([where: "deleted_at IS NULL"], :users, :slug)

      assert result == %{
               fields: [:slug],
               name: :users_slug_index,
               where: "deleted_at IS NULL"
             }
    end
  end

  # ============================================
  # normalize_check_option/3 Tests
  # ============================================

  describe "normalize_check_option/3" do
    test "normalizes atom to check constraint metadata" do
      result = Constraints.normalize_check_option(:users_age_positive, :users, :age)

      assert result == %{
               name: :users_age_positive,
               expr: nil,
               field: :age
             }
    end
  end

  # ============================================
  # normalize_belongs_to_constraint/4 Tests
  # ============================================

  describe "normalize_belongs_to_constraint/4" do
    test "normalizes constraint options list" do
      result =
        Constraints.normalize_belongs_to_constraint(
          [on_delete: :cascade, deferrable: :initially_deferred],
          :memberships,
          :user_id,
          :users
        )

      assert result == %{
               field: :user_id,
               references: :users,
               column: :id,
               on_delete: :cascade,
               on_update: :nothing,
               deferrable: :initially_deferred,
               name: :memberships_user_id_fkey
             }
    end

    test "normalizes nil to default FK constraint" do
      result = Constraints.normalize_belongs_to_constraint(nil, :memberships, :user_id, :users)

      assert result == %{
               field: :user_id,
               references: :users,
               column: :id,
               on_delete: :nothing,
               on_update: :nothing,
               deferrable: nil,
               name: :memberships_user_id_fkey
             }
    end

    test "returns nil for false (skip FK constraint)" do
      result = Constraints.normalize_belongs_to_constraint(false, :memberships, :user_id, :users)

      assert result == nil
    end

    test "respects custom name in options" do
      result =
        Constraints.normalize_belongs_to_constraint(
          [name: :custom_fk_name, on_delete: :cascade],
          :memberships,
          :user_id,
          :users
        )

      assert result.name == :custom_fk_name
    end
  end

  # ============================================
  # Schema Introspection Tests
  # ============================================

  describe "schema constraint introspection" do
    test "constraints/0 returns all constraint metadata" do
      constraints = UserWithConstraints.constraints()

      assert Map.has_key?(constraints, :unique)
      assert Map.has_key?(constraints, :foreign_key)
      assert Map.has_key?(constraints, :check)
      assert Map.has_key?(constraints, :exclude)
      assert Map.has_key?(constraints, :primary_key)
    end

    test "unique_constraints/0 returns unique constraints" do
      unique = UserWithConstraints.unique_constraints()

      assert is_list(unique)

      # Should have field-level unique from :email
      email_unique = Enum.find(unique, fn u -> :email in u.fields end)
      assert email_unique != nil

      # Should have field-level unique from :username
      username_unique = Enum.find(unique, fn u -> :username in u.fields end)
      assert username_unique != nil
      assert username_unique.name == :users_username_idx

      # Should have composite unique from constraints block
      composite_unique = Enum.find(unique, fn u -> u.name == :users_account_email_idx end)
      assert composite_unique != nil
      assert composite_unique.fields == [:account_id, :email]
    end

    test "check_constraints/0 returns check constraints" do
      checks = UserWithConstraints.check_constraints()

      assert is_list(checks)

      # Should have field-level check from :age
      age_check = Enum.find(checks, fn c -> c.name == :users_age_positive end)
      assert age_check != nil

      # Should have block-level check
      status_check = Enum.find(checks, fn c -> c.name == :valid_status end)
      assert status_check != nil
      assert status_check.expr == "status IN ('active', 'inactive')"
    end

    test "indexes/0 includes unique constraints as indexes" do
      indexes = UserWithConstraints.indexes()

      assert is_list(indexes)

      # Should include unique constraints as indexes
      email_idx = Enum.find(indexes, fn i -> :email in i.fields end)
      assert email_idx != nil
      assert email_idx.unique == true

      # Should include regular indexes from constraints block
      status_idx = Enum.find(indexes, fn i -> i.name == :users_status_idx end)
      assert status_idx != nil
      assert status_idx.unique == false
    end

    test "primary_key is included in constraints" do
      constraints = UserWithConstraints.constraints()

      assert constraints.primary_key == %{
               fields: [:id],
               name: :constraints_test_users_pkey
             }
    end
  end

  # ============================================
  # Foreign Key Constraints Tests
  # ============================================

  describe "foreign key constraints" do
    test "foreign_keys/0 returns FK constraints from constraints block" do
      fks = MembershipWithConstraints.foreign_keys()

      assert is_list(fks)

      user_fk = Enum.find(fks, fn fk -> fk.field == :user_id end)
      assert user_fk != nil
      assert user_fk.references == :users
      assert user_fk.on_delete == :cascade

      account_fk = Enum.find(fks, fn fk -> fk.field == :account_id end)
      assert account_fk != nil
      assert account_fk.references == :accounts
      assert account_fk.on_delete == :restrict
    end
  end

  # ============================================
  # Exclusion Constraints Tests
  # ============================================

  describe "exclusion constraints" do
    test "constraints include exclusion constraints" do
      constraints = MembershipWithConstraints.constraints()

      assert is_list(constraints.exclude)

      overlap = Enum.find(constraints.exclude, fn e -> e.name == :no_overlap end)
      assert overlap != nil
      assert overlap.using == :gist
      assert overlap.expr =~ "tsrange"
    end
  end
end
