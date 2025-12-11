defmodule OmSchema.DatabaseValidator.ConstraintChecker do
  @moduledoc """
  Validates Ecto schema constraint declarations against PostgreSQL database constraints.

  Checks that:
  - Primary key constraints exist
  - Unique constraints declared in schema exist in database
  - Foreign key constraints exist with correct on_delete/on_update rules
  - Check constraints exist
  - Indexes exist (warning level)
  """

  alias OmSchema.DatabaseValidator.PgIntrospection

  @doc """
  Validates all constraint declarations against the database.

  ## Options

    * `:repo` - The Ecto repo to use (required)
    * `:table` - The table name (required)
    * `:schema_module` - The schema module (required)
    * `:check_indexes` - Check index existence (default: false, indexes are warnings)

  ## Returns

      {:ok, %{validated: count, warnings: [...]}}
      {:error, %{errors: [...], warnings: [...]}}
  """
  @spec validate(keyword()) :: {:ok, map()} | {:error, map()}
  def validate(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)
    schema_module = Keyword.fetch!(opts, :schema_module)
    check_indexes = Keyword.get(opts, :check_indexes, false)

    # Get schema constraints
    schema_constraints = get_schema_constraints(schema_module)

    # Get database constraints
    db_constraints = PgIntrospection.constraints(repo, table)
    db_fks = PgIntrospection.foreign_keys(repo, table)
    # Always fetch indexes for unique constraint validation (unique constraints are often indexes)
    db_indexes = PgIntrospection.indexes(repo, table)

    # Build lookup maps
    db_constraint_map = Map.new(db_constraints, &{&1.name, &1})
    db_fk_map = Map.new(db_fks, &{&1.name, &1})
    db_index_map = Map.new(db_indexes, &{&1.name, &1})

    # Validate primary key
    {pk_errors, pk_count} = validate_primary_key(schema_constraints.primary_key, db_constraint_map)

    # Validate unique constraints
    {unique_errors, unique_count} =
      validate_unique_constraints(schema_constraints.unique, db_constraint_map, db_index_map)

    # Validate foreign keys
    {fk_errors, fk_count} = validate_foreign_keys(schema_constraints.foreign_key, db_fk_map)

    # Validate check constraints
    {check_errors, check_count} =
      validate_check_constraints(schema_constraints.check, db_constraint_map)

    # Validate indexes (warnings only)
    index_warnings =
      if check_indexes do
        validate_indexes(schema_module, db_index_map, db_constraint_map)
      else
        []
      end

    errors = pk_errors ++ unique_errors ++ fk_errors ++ check_errors
    validated = pk_count + unique_count + fk_count + check_count

    if errors == [] do
      {:ok, %{validated: validated, warnings: index_warnings}}
    else
      {:error, %{errors: errors, warnings: index_warnings}}
    end
  end

  defp get_schema_constraints(schema_module) do
    if function_exported?(schema_module, :__constraints__, 0) do
      schema_module.__constraints__()
    else
      %{
        unique: [],
        foreign_key: [],
        check: [],
        exclude: [],
        primary_key: %{fields: [:id], name: nil}
      }
    end
  end

  # Primary Key Validation
  defp validate_primary_key(pk_spec, db_constraint_map) do
    pk_name = pk_spec[:name]

    cond do
      is_nil(pk_name) ->
        {[], 0}

      Map.has_key?(db_constraint_map, pk_name) ->
        {[], 1}

      true ->
        {[{:primary_key, "constraint #{pk_name} not found in database"}], 0}
    end
  end

  # Unique Constraint Validation
  defp validate_unique_constraints(unique_specs, db_constraint_map, db_index_map) do
    Enum.reduce(unique_specs, {[], 0}, fn spec, {errs, count} ->
      name = spec[:name]

      cond do
        is_nil(name) ->
          {errs, count}

        Map.has_key?(db_constraint_map, name) ->
          # Verify columns match
          db_constraint = db_constraint_map[name]

          if columns_match?(spec[:fields], db_constraint.columns) do
            {errs, count + 1}
          else
            error =
              {:unique,
               "constraint #{name} has different columns: expected #{inspect(spec[:fields])}, got #{inspect(db_constraint.columns)}"}

            {[error | errs], count}
          end

        # Also check if it exists as an index (unique indexes are often not in pg_constraint)
        Map.has_key?(db_index_map, name) ->
          db_index = db_index_map[name]

          if db_index.unique && columns_match?(spec[:fields], db_index.columns) do
            {errs, count + 1}
          else
            error = {:unique, "index #{name} is not unique or has different columns"}
            {[error | errs], count}
          end

        true ->
          error = {:unique, "constraint/index #{name} not found in database"}
          {[error | errs], count}
      end
    end)
  end

  defp columns_match?(expected, actual) do
    MapSet.new(expected) == MapSet.new(actual)
  end

  # Foreign Key Validation
  defp validate_foreign_keys(fk_specs, db_fk_map) do
    Enum.reduce(fk_specs, {[], 0}, fn spec, {errs, count} ->
      name = spec[:name]

      cond do
        is_nil(name) ->
          {errs, count}

        Map.has_key?(db_fk_map, name) ->
          db_fk = db_fk_map[name]

          case validate_fk_details(spec, db_fk) do
            :ok ->
              {errs, count + 1}

            {:error, msg} ->
              {[{:foreign_key, msg} | errs], count}
          end

        true ->
          error = {:foreign_key, "constraint #{name} not found in database"}
          {[error | errs], count}
      end
    end)
  end

  defp validate_fk_details(spec, db_fk) do
    errors = []

    # Check column
    errors =
      if spec[:field] != db_fk.column do
        ["column mismatch: expected #{spec[:field]}, got #{db_fk.column}" | errors]
      else
        errors
      end

    # Check on_delete
    schema_on_delete = normalize_fk_action(spec[:on_delete])
    db_on_delete = db_fk.on_delete

    errors =
      if schema_on_delete != db_on_delete do
        ["on_delete mismatch: schema declares #{schema_on_delete}, DB has #{db_on_delete}" | errors]
      else
        errors
      end

    # Check on_update (if specified)
    errors =
      if spec[:on_update] && spec[:on_update] != :nothing do
        schema_on_update = normalize_fk_action(spec[:on_update])
        db_on_update = db_fk.on_update

        if schema_on_update != db_on_update do
          [
            "on_update mismatch: schema declares #{schema_on_update}, DB has #{db_on_update}"
            | errors
          ]
        else
          errors
        end
      else
        errors
      end

    case errors do
      [] -> :ok
      _ -> {:error, "FK #{spec[:name]}: #{Enum.join(errors, "; ")}"}
    end
  end

  defp normalize_fk_action(nil), do: :nothing
  defp normalize_fk_action(:nothing), do: :nothing
  defp normalize_fk_action(:no_action), do: :nothing
  defp normalize_fk_action(:cascade), do: :cascade
  defp normalize_fk_action(:delete_all), do: :cascade
  defp normalize_fk_action(:restrict), do: :restrict
  defp normalize_fk_action(:nilify_all), do: :set_null
  defp normalize_fk_action(:set_null), do: :set_null
  defp normalize_fk_action(:set_default), do: :set_default
  defp normalize_fk_action(other), do: other

  # Check Constraint Validation
  defp validate_check_constraints(check_specs, db_constraint_map) do
    Enum.reduce(check_specs, {[], 0}, fn spec, {errs, count} ->
      name = spec[:name]

      cond do
        is_nil(name) ->
          {errs, count}

        Map.has_key?(db_constraint_map, name) ->
          {errs, count + 1}

        true ->
          error = {:check, "constraint #{name} not found in database"}
          {[error | errs], count}
      end
    end)
  end

  # Index Validation (warnings only)
  defp validate_indexes(schema_module, db_index_map, db_constraint_map) do
    if function_exported?(schema_module, :__indexes__, 0) do
      schema_module.__indexes__()
      # Skip unique indexes (checked as constraints)
      |> Enum.reject(fn idx -> idx.unique end)
      |> Enum.flat_map(fn idx ->
        name = idx[:name]

        cond do
          is_nil(name) ->
            []

          Map.has_key?(db_index_map, name) || Map.has_key?(db_constraint_map, name) ->
            []

          true ->
            [{:index, "index #{name} not found in database"}]
        end
      end)
    else
      []
    end
  end

  @doc """
  Gets a summary of constraint validation for a schema.
  """
  @spec summary(keyword()) :: map()
  def summary(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)
    schema_module = Keyword.fetch!(opts, :schema_module)

    schema_constraints = get_schema_constraints(schema_module)
    db_constraints = PgIntrospection.constraints(repo, table)
    db_fks = PgIntrospection.foreign_keys(repo, table)

    %{
      schema_unique: length(schema_constraints.unique),
      schema_foreign_keys: length(schema_constraints.foreign_key),
      schema_check: length(schema_constraints.check),
      db_constraints: length(db_constraints),
      db_foreign_keys: length(db_fks)
    }
  end
end
