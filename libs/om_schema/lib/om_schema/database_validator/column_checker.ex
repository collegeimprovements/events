defmodule OmSchema.DatabaseValidator.ColumnChecker do
  @moduledoc """
  Validates Ecto schema fields against PostgreSQL database columns.

  Checks that:
  - All schema fields exist in the database
  - Field types are compatible with column types
  - Nullability matches between schema and database (warning)
  - Optionally reports extra database columns not in schema
  """

  alias OmSchema.DatabaseValidator.{PgIntrospection, TypeMapper}

  @doc """
  Validates schema fields against database columns.

  Returns a validation result with errors and warnings.

  ## Options

    * `:repo` - The Ecto repo to use (required)
    * `:table` - The table name (required)
    * `:schema_module` - The schema module (required)
    * `:check_extra_columns` - Report extra DB columns as errors (default: false)
    * `:check_nullable` - Check nullability mismatches (default: true)

  ## Returns

      {:ok, %{validated: count, warnings: [...]}}
      {:error, %{errors: [...], warnings: [...]}}
  """
  @spec validate(keyword()) :: {:ok, map()} | {:error, map()}
  def validate(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)
    schema_module = Keyword.fetch!(opts, :schema_module)
    check_extra = Keyword.get(opts, :check_extra_columns, false)
    check_nullable = Keyword.get(opts, :check_nullable, true)

    # Get schema fields
    schema_fields = get_schema_fields(schema_module)

    # Get database columns
    db_columns = PgIntrospection.columns(repo, table)

    # Build lookup map for DB columns
    db_column_map = Map.new(db_columns, &{&1.name, &1})

    # Validate each schema field
    {errors, warnings, validated} =
      Enum.reduce(schema_fields, {[], [], 0}, fn {field_name, field_type, field_opts},
                                                 {errs, warns, count} ->
        case validate_field(field_name, field_type, field_opts, db_column_map, check_nullable) do
          :ok ->
            {errs, warns, count + 1}

          {:warning, msg} ->
            {errs, [{field_name, msg} | warns], count + 1}

          {:error, msg} ->
            {[{field_name, msg} | errs], warns, count}
        end
      end)

    # Check for extra columns if requested
    warnings =
      if check_extra do
        schema_field_names = MapSet.new(schema_fields, fn {name, _, _} -> name end)

        extra_warnings =
          db_columns
          |> Enum.reject(&MapSet.member?(schema_field_names, &1.name))
          |> Enum.map(&{&1.name, "exists in database but not in schema"})

        warnings ++ extra_warnings
      else
        warnings
      end

    if errors == [] do
      {:ok, %{validated: validated, warnings: Enum.reverse(warnings)}}
    else
      {:error, %{errors: Enum.reverse(errors), warnings: Enum.reverse(warnings)}}
    end
  end

  defp get_schema_fields(schema_module) do
    # Get virtual fields from Ecto's schema introspection
    virtual_fields = MapSet.new(schema_module.__schema__(:virtual_fields))

    if function_exported?(schema_module, :field_validations, 0) do
      # Merge virtual: true into validation opts for virtual fields
      schema_module.field_validations()
      |> Enum.map(fn {name, type, opts} ->
        if MapSet.member?(virtual_fields, name) do
          {name, type, Keyword.put(opts, :virtual, true)}
        else
          {name, type, opts}
        end
      end)
    else
      # Fallback to Ecto schema introspection
      schema_module.__schema__(:fields)
      |> Enum.map(fn field ->
        type = schema_module.__schema__(:type, field)
        is_virtual = MapSet.member?(virtual_fields, field)
        {field, type, [virtual: is_virtual]}
      end)
    end
  end

  defp validate_field(field_name, field_type, field_opts, db_column_map, check_nullable) do
    case Map.get(db_column_map, field_name) do
      nil ->
        # Virtual fields don't need to exist in DB
        if Keyword.get(field_opts, :virtual, false) do
          :ok
        else
          {:error, "column does not exist in database"}
        end

      db_column ->
        # Check type compatibility
        case validate_type(field_type, db_column) do
          :ok ->
            # Check nullability if requested
            if check_nullable do
              validate_nullable(field_opts, db_column)
            else
              :ok
            end

          error ->
            error
        end
    end
  end

  defp validate_type(field_type, db_column) do
    pg_type = db_column.data_type
    udt_name = db_column.udt_name

    # For arrays, check the underlying type
    cond do
      pg_type == "ARRAY" && is_tuple(field_type) && elem(field_type, 0) == :array ->
        # Check array element type
        {_, inner_type} = field_type
        element_pg_type = String.trim_leading(udt_name, "_")

        if TypeMapper.compatible?(inner_type, element_pg_type) do
          :ok
        else
          expected = TypeMapper.expected_types_description(inner_type)
          {:error, "array element type mismatch: expected #{expected}, got #{element_pg_type}"}
        end

      TypeMapper.compatible?(field_type, pg_type) ->
        :ok

      # Also check udt_name for custom types
      TypeMapper.compatible?(field_type, udt_name) ->
        :ok

      true ->
        expected = TypeMapper.expected_types_description(field_type)
        {:error, "type mismatch: expected #{expected}, got #{pg_type}"}
    end
  end

  defp validate_nullable(field_opts, db_column) do
    is_required = Keyword.get(field_opts, :required, false)
    db_is_nullable = db_column.is_nullable

    if TypeMapper.nullable_mismatch?(is_required, db_is_nullable) do
      {:warning, "field is required but column allows NULL"}
    else
      :ok
    end
  end

  @doc """
  Gets a summary of column validation for a schema.

  Returns a map with:
    - `:schema_fields` - Number of fields in schema
    - `:db_columns` - Number of columns in database
    - `:matched` - Number of matching field/column pairs
    - `:missing_in_db` - Fields in schema but not in DB
    - `:missing_in_schema` - Columns in DB but not in schema
  """
  @spec summary(keyword()) :: map()
  def summary(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)
    schema_module = Keyword.fetch!(opts, :schema_module)

    schema_fields = get_schema_fields(schema_module)

    schema_field_names =
      schema_fields
      |> Enum.reject(fn {_, _, opts} -> Keyword.get(opts, :virtual, false) end)
      |> Enum.map(fn {name, _, _} -> name end)
      |> MapSet.new()

    db_columns = PgIntrospection.columns(repo, table)
    db_column_names = MapSet.new(db_columns, & &1.name)

    matched = MapSet.intersection(schema_field_names, db_column_names)
    missing_in_db = MapSet.difference(schema_field_names, db_column_names)
    missing_in_schema = MapSet.difference(db_column_names, schema_field_names)

    %{
      schema_fields: MapSet.size(schema_field_names),
      db_columns: MapSet.size(db_column_names),
      matched: MapSet.size(matched),
      missing_in_db: MapSet.to_list(missing_in_db),
      missing_in_schema: MapSet.to_list(missing_in_schema)
    }
  end
end
