defmodule OmCrud.SchemaTest do
  use ExUnit.Case, async: true

  describe "use OmCrud.Schema" do
    test "module can be used without errors" do
      defmodule TestSchemaUsage do
        use Ecto.Schema
        use OmCrud.Schema

        schema "test_table" do
          field :name, :string
        end
      end

      assert Code.ensure_loaded?(TestSchemaUsage)
    end

    test "defines __crud_changeset__ when @crud_changeset is set" do
      defmodule SchemaWithCrudChangeset do
        use Ecto.Schema
        use OmCrud.Schema

        @crud_changeset :custom_changeset

        schema "test_table" do
          field :name, :string
        end
      end

      assert function_exported?(SchemaWithCrudChangeset, :__crud_changeset__, 0)
      assert SchemaWithCrudChangeset.__crud_changeset__() == :custom_changeset
    end

    test "defines __crud_config__ when @crud_config is set" do
      defmodule SchemaWithCrudConfig do
        use Ecto.Schema
        use OmCrud.Schema

        @crud_config preload: [:account], changeset: :admin_changeset

        schema "test_table" do
          field :name, :string
        end
      end

      assert function_exported?(SchemaWithCrudConfig, :__crud_config__, 0)
      config = SchemaWithCrudConfig.__crud_config__()
      assert config[:preload] == [:account]
      assert config[:changeset] == :admin_changeset
    end
  end

  describe "crud_changeset macro" do
    test "sets crud changeset via macro" do
      defmodule SchemaWithMacro do
        use Ecto.Schema
        use OmCrud.Schema

        crud_changeset :registration_changeset

        schema "test_table" do
          field :name, :string
        end
      end

      assert SchemaWithMacro.__crud_changeset__() == :registration_changeset
    end
  end

  describe "crud_config macro" do
    test "sets crud config via macro" do
      defmodule SchemaWithConfigMacro do
        use Ecto.Schema
        use OmCrud.Schema

        crud_config preload: [:user], timeout: 30_000

        schema "test_table" do
          field :name, :string
        end
      end

      config = SchemaWithConfigMacro.__crud_config__()
      assert config[:preload] == [:user]
      assert config[:timeout] == 30_000
    end
  end
end
