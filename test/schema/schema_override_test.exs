defmodule Events.Core.SchemaOverrideTest do
  @moduledoc """
  Test to verify we can override schema macro itself, not just field.
  """
  use Events.TestCase, async: true

  defmodule CustomSchema do
    @moduledoc """
    Module that overrides both schema and field macros.
    """

    defmacro __using__(opts) do
      quote do
        use Ecto.Schema
        import Ecto.Changeset
        # ← Exclude Ecto's schema!
        import Ecto.Schema, except: [schema: 2]
        import Events.Core.SchemaOverrideTest.CustomSchema

        @primary_key {:id, :binary_id, autogenerate: true}
        @foreign_key_type :binary_id
        @schema_opts unquote(opts)
      end
    end

    # Override schema macro
    defmacro schema(source, do: block) do
      quote do
        Ecto.Schema.schema unquote(source) do
          # Auto-add fields BEFORE user fields
          field :type, :string
          field :metadata, :map, default: %{}

          # User's fields
          unquote(block)

          # Auto-add fields AFTER user fields
          field :created_by_urm_id, :binary_id
          timestamps(type: :utc_datetime_usec)
        end
      end
    end
  end

  # Test it works
  defmodule TestUser do
    use Events.Core.SchemaOverrideTest.CustomSchema

    # Just use schema! Not events_schema!
    schema "users" do
      field :name, :string
      field :email, :string
    end
  end

  test "schema override adds automatic fields" do
    user = %TestUser{}

    # Check user fields exist
    assert Map.has_key?(user, :name)
    assert Map.has_key?(user, :email)

    # Check auto-added fields exist
    assert Map.has_key?(user, :type)
    assert Map.has_key?(user, :metadata)
    assert Map.has_key?(user, :created_by_urm_id)
    assert Map.has_key?(user, :inserted_at)
    assert Map.has_key?(user, :updated_at)
  end

  test "schema reflection works" do
    fields = TestUser.__schema__(:fields)

    assert :name in fields
    assert :email in fields
    assert :type in fields
    assert :metadata in fields
    assert :created_by_urm_id in fields
  end

  test "default values work" do
    user = %TestUser{}
    assert user.metadata == %{}
  end
end
