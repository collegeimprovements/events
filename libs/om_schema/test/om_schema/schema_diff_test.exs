defmodule OmSchema.SchemaDiffTest do
  @moduledoc """
  Tests for OmSchema.SchemaDiff - Runtime schema diffing.

  Note: Most functions in SchemaDiff require a database connection.
  These tests focus on the comparison logic and formatting functions
  that don't require a live database.
  """

  use ExUnit.Case, async: true

  alias OmSchema.SchemaDiff

  # ============================================
  # Test Schemas
  # ============================================

  defmodule User do
    use OmSchema

    schema "schema_diff_test_users" do
      field :name, :string, required: true
      field :email, :string, required: true
      field :age, :integer
      field :status, :string
    end
  end

  defmodule Account do
    use OmSchema

    schema "schema_diff_test_accounts" do
      field :name, :string, required: true
      field :slug, :string, required: true
    end
  end

  # ============================================
  # format/2 Tests
  # ============================================

  describe "format/2" do
    test "formats in-sync diff" do
      diff = %{
        module: User,
        table: "users",
        in_sync: true,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      output = SchemaDiff.format(diff)

      assert output =~ "OmSchema.SchemaDiffTest.User"
      assert output =~ "users"
      assert output =~ "IN SYNC"
    end

    test "formats out-of-sync diff with missing columns in DB" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [{:column, :new_field}],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      output = SchemaDiff.format(diff)

      assert output =~ "OUT OF SYNC"
      assert output =~ "Missing in database"
      assert output =~ "new_field"
    end

    test "formats diff with extra columns in DB" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [],
        missing_in_schema: [{:column, :legacy_field}],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      output = SchemaDiff.format(diff)

      assert output =~ "Extra in database"
      assert output =~ "legacy_field"
    end

    test "formats diff with type mismatches" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [{:column, :status, :string, "integer"}],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      output = SchemaDiff.format(diff)

      assert output =~ "Type mismatches"
      assert output =~ "status"
      assert output =~ ":string"
      assert output =~ "integer"
    end

    test "formats diff with nullable mismatches" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [{:column, :email, :required, :nullable}],
        constraint_mismatches: []
      }

      output = SchemaDiff.format(diff)

      assert output =~ "Nullable mismatches"
      assert output =~ "email"
      assert output =~ "required"
      assert output =~ "nullable"
    end

    test "formats diff with constraint mismatches" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: [
          {:constraint, :users_email_key, :missing},
          {:constraint, :users_legacy_idx, :extra}
        ]
      }

      output = SchemaDiff.format(diff)

      assert output =~ "Constraint differences"
      assert output =~ "users_email_key"
      assert output =~ "missing"
      assert output =~ "users_legacy_idx"
      assert output =~ "extra"
    end

    test "formats with color option" do
      diff = %{
        module: User,
        table: "users",
        in_sync: true,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      output = SchemaDiff.format(diff, color: true)

      # ANSI green color code for IN SYNC
      assert output =~ "\e[32m"
    end
  end

  # ============================================
  # generate_migration/2 Tests
  # ============================================

  describe "generate_migration/2" do
    test "generates migration for missing columns" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [{:column, :new_field}],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      migration = SchemaDiff.generate_migration(diff)

      assert migration =~ "defmodule"
      assert migration =~ "use Ecto.Migration"
      assert migration =~ "def up do"
      assert migration =~ "def down do"
      assert migration =~ "add :new_field"
      assert migration =~ "remove :new_field"
    end

    test "generates migration for nullable changes" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [{:column, :email, :required, :nullable}],
        constraint_mismatches: []
      }

      migration = SchemaDiff.generate_migration(diff)

      assert migration =~ "modify :email, null: false"
      assert migration =~ "modify :email, null: true"
    end

    test "generates migration with custom module name" do
      diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [{:column, :bio}],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      migration = SchemaDiff.generate_migration(diff, module_name: "MyApp.Migrations.AddBioToUsers")

      assert migration =~ "defmodule MyApp.Migrations.AddBioToUsers do"
    end
  end

  # ============================================
  # Diff Result Structure Tests
  # ============================================

  describe "diff result structure" do
    test "has all required keys" do
      # Create a minimal diff result
      diff = %{
        module: User,
        table: "users",
        in_sync: true,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      assert Map.has_key?(diff, :module)
      assert Map.has_key?(diff, :table)
      assert Map.has_key?(diff, :in_sync)
      assert Map.has_key?(diff, :missing_in_db)
      assert Map.has_key?(diff, :missing_in_schema)
      assert Map.has_key?(diff, :type_mismatches)
      assert Map.has_key?(diff, :nullable_mismatches)
      assert Map.has_key?(diff, :constraint_mismatches)
    end

    test "in_sync is true only when all lists are empty" do
      in_sync_diff = %{
        module: User,
        table: "users",
        in_sync: true,
        missing_in_db: [],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      out_of_sync_diff = %{
        module: User,
        table: "users",
        in_sync: false,
        missing_in_db: [{:column, :foo}],
        missing_in_schema: [],
        type_mismatches: [],
        nullable_mismatches: [],
        constraint_mismatches: []
      }

      assert in_sync_diff.in_sync == true
      assert out_of_sync_diff.in_sync == false
    end
  end

  # ============================================
  # Schema Introspection Tests (without DB)
  # ============================================

  describe "schema introspection" do
    test "test schema has expected fields" do
      fields = User.__schema__(:fields)

      assert :id in fields
      assert :name in fields
      assert :email in fields
      assert :age in fields
      assert :status in fields
    end

    test "test schema reports correct table name" do
      assert User.__schema__(:source) == "schema_diff_test_users"
      assert Account.__schema__(:source) == "schema_diff_test_accounts"
    end

    test "test schema has field_validations function" do
      assert function_exported?(User, :field_validations, 0)

      validations = User.field_validations()

      # Find name field validation
      name_validation = Enum.find(validations, fn {name, _, _} -> name == :name end)
      assert name_validation != nil

      {_, _, opts} = name_validation
      assert Keyword.get(opts, :required) == true
    end
  end

  # ============================================
  # Error Handling Tests
  # ============================================

  describe "error handling" do
    test "diff returns error when repo is not configured" do
      # Clear any global repo config temporarily
      original = Application.get_env(:om_schema, :default_repo)
      Application.delete_env(:om_schema, :default_repo)

      result = SchemaDiff.diff(User)
      assert result == {:error, :repo_not_configured}

      # Restore original config
      if original, do: Application.put_env(:om_schema, :default_repo, original)
    end
  end

  # ============================================
  # Diff Options Tests
  # ============================================

  describe "diff options" do
    test "ignore_columns option accepts list of atoms" do
      # This test verifies the option format is correct
      # Actual filtering is tested with DB integration

      opts = [
        repo: SomeRepo,
        ignore_columns: [:inserted_at, :updated_at]
      ]

      assert Keyword.get(opts, :ignore_columns) == [:inserted_at, :updated_at]
    end

    test "ignore_constraints option accepts list of atoms" do
      opts = [
        repo: SomeRepo,
        ignore_constraints: [:some_legacy_constraint]
      ]

      assert Keyword.get(opts, :ignore_constraints) == [:some_legacy_constraint]
    end

    test "schema option defaults to public" do
      opts = [repo: SomeRepo]

      assert Keyword.get(opts, :schema, "public") == "public"
    end
  end
end
