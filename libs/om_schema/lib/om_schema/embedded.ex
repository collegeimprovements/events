defmodule OmSchema.Embedded do
  @moduledoc """
  Utility functions for embedded schema validation propagation.

  The `embeds_one/3` and `embeds_many/3` macros are defined in `OmSchema`
  and support the `propagate_validations: true` option.

  This module provides utility functions for:
  - Casting embeds with validation (`cast_embed_with_validation/3`)
  - Validating all embeds (`validate_embeds/2`)
  - Introspecting embedded schemas (`get_embedded_schemas/1`)

  ## Usage Example

      defmodule MyApp.User do
        use OmSchema

        schema "users" do
          field :name, :string, required: true

          # Automatically use Address.base_changeset/2 for validation
          embeds_one :address, MyApp.Address, propagate_validations: true
        end
      end

      # Manual validation
      def changeset(user, attrs) do
        user
        |> base_changeset(attrs)
        |> cast_embed(:address, with: &Address.base_changeset/2)
        |> OmSchema.Embedded.validate_embeds()
      end

  """

  @doc """
  Casts and validates embedded schemas using the embedded module's `base_changeset/2`.

  This function is useful when you need to manually trigger embedded validation
  or when you want to customize the changeset function used.

  ## Options

    * `:with` - Custom changeset function to use (default: `:base_changeset`)
    * `:required` - Whether the embed is required (default: `false`)

  ## Examples

      changeset
      |> cast_embed_with_validation(:address)

      changeset
      |> cast_embed_with_validation(:address, with: :admin_changeset)

      changeset
      |> cast_embed_with_validation(:address, required: true)

  """
  @spec cast_embed_with_validation(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def cast_embed_with_validation(changeset, embed_name, opts \\ []) do
    changeset_fn = Keyword.get(opts, :with, :base_changeset)
    required = Keyword.get(opts, :required, false)

    # Build the with function
    with_fn =
      if is_atom(changeset_fn) do
        fn embed_struct, attrs ->
          apply(embed_struct.__struct__, changeset_fn, [embed_struct, attrs])
        end
      else
        changeset_fn
      end

    cast_opts = [with: with_fn]
    cast_opts = if required, do: Keyword.put(cast_opts, :required, true), else: cast_opts

    Ecto.Changeset.cast_embed(changeset, embed_name, cast_opts)
  end

  @doc """
  Validates all embedded schemas that have `propagate_validations: true`.

  Call this function after `cast/3` to validate embedded schemas using
  their `base_changeset/2` function.

  ## Options

    * `:only` - List of embed names to validate (default: all with propagate_validations)
    * `:except` - List of embed names to skip

  ## Examples

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:name])
        |> cast_embed(:address)
        |> validate_embeds()
      end

      # Validate specific embeds only
      |> validate_embeds(only: [:address])

      # Skip certain embeds
      |> validate_embeds(except: [:tags])

  """
  @spec validate_embeds(Ecto.Changeset.t(), keyword()) :: Ecto.Changeset.t()
  def validate_embeds(changeset, opts \\ []) do
    schema_module = changeset.data.__struct__

    # Get embedded schemas metadata
    embedded_schemas =
      if function_exported?(schema_module, :embedded_schemas, 0) do
        schema_module.embedded_schemas()
      else
        []
      end

    # Filter by only/except options
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    embedded_schemas
    |> Enum.filter(fn {name, _cardinality, _schema, propagate} ->
      propagate &&
        (is_nil(only) || name in only) &&
        name not in except
    end)
    |> Enum.reduce(changeset, fn {name, cardinality, schema_mod, _propagate}, acc ->
      validate_embed(acc, name, cardinality, schema_mod)
    end)
  end

  @doc """
  Validates a single embedded schema recursively.

  ## Examples

      changeset
      |> validate_embed(:address, :one, MyApp.Address)

  """
  @spec validate_embed(Ecto.Changeset.t(), atom(), :one | :many, module()) :: Ecto.Changeset.t()
  def validate_embed(changeset, embed_name, cardinality, schema_module) do
    case Ecto.Changeset.get_change(changeset, embed_name) do
      nil ->
        changeset

      embed_changeset when cardinality == :one ->
        validated = validate_embedded_changeset(embed_changeset, schema_module)
        Ecto.Changeset.put_change(changeset, embed_name, validated)

      embed_changesets when is_list(embed_changesets) and cardinality == :many ->
        validated = Enum.map(embed_changesets, &validate_embedded_changeset(&1, schema_module))
        Ecto.Changeset.put_change(changeset, embed_name, validated)

      _ ->
        changeset
    end
  end

  # Validates a single embedded changeset
  defp validate_embedded_changeset(%Ecto.Changeset{} = changeset, schema_module) do
    if function_exported?(schema_module, :base_changeset, 2) do
      # Re-run validation through base_changeset
      # Extract changes and apply them through base_changeset
      data = changeset.data
      changes = changeset.changes

      # Apply base_changeset validations
      schema_module.base_changeset(data, changes)
    else
      changeset
    end
  end

  defp validate_embedded_changeset(changeset, _schema_module), do: changeset

  @doc """
  Returns embedded schema metadata for a module.

  Used internally for introspection and validation.

  ## Examples

      MyApp.User.embedded_schemas()
      # => [{:address, :one, MyApp.Address, true}, {:tags, :many, MyApp.Tag, false}]

  """
  @spec get_embedded_schemas(module()) :: [{atom(), :one | :many, module(), boolean()}]
  def get_embedded_schemas(module) do
    if function_exported?(module, :embedded_schemas, 0) do
      module.embedded_schemas()
    else
      []
    end
  end
end
