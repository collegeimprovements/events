defmodule Events.Core.Schema.DatabaseValidator do
  @moduledoc """
  Validates Ecto schemas against PostgreSQL database structure.

  Ensures schemas don't drift from actual database columns, indexes, and constraints.
  Supports validation via mix task, test helper, and application startup.

  ## Usage

  ### Mix Task

      # Validate all schemas
      mix schema.validate

      # Validate specific schema
      mix schema.validate Events.Domains.Accounts.User

      # With options
      mix schema.validate --fail-on-extra-db-columns

  ### Programmatic

      alias Events.Core.Schema.DatabaseValidator

      # Validate all schemas
      DatabaseValidator.validate_all()

      # Validate single schema
      DatabaseValidator.validate(Events.Domains.Accounts.User)

      # Get detailed report
      DatabaseValidator.report(Events.Domains.Accounts.User)

  ### Startup Validation

      # In config/dev.exs
      config :events, :schema_validation,
        enabled: true,
        on_startup: true,
        fail_on_error: false

  ## Validation Checks

  | Check | Description | Default |
  |-------|-------------|---------|
  | `columns_exist` | Schema fields exist in DB | Error |
  | `column_types_match` | Ecto types compatible with PG types | Error |
  | `not_null_matches` | `required: true` matches `NOT NULL` | Warning |
  | `unique_constraints_exist` | Declared unique constraints exist | Error |
  | `foreign_keys_exist` | Declared FKs exist with correct rules | Error |
  | `check_constraints_exist` | Declared check constraints exist | Error |
  | `indexes_exist` | Declared indexes exist | Warning |
  | `has_many_fks_exist` | FK exists on related table for has_many | Error |
  """

  alias Events.Core.Schema.DatabaseValidator.{
    PgIntrospection,
    ColumnChecker,
    ConstraintChecker,
    AssociationChecker
  }

  require Logger

  @default_repo Events.Core.Repo

  @doc """
  Validates all schemas that use `Events.Core.Schema`.

  Discovers all modules that have the `__constraints__/0` function
  (indicating they use Events.Core.Schema with constraint support).

  ## Options

    * `:repo` - Ecto repo to use (default: `Events.Core.Repo`)
    * `:fail_on_extra_columns` - Treat extra DB columns as errors (default: false)
    * `:check_indexes` - Validate index existence (default: false)
    * `:quiet` - Only return errors, no logging (default: false)

  ## Returns

      {:ok, %{schemas: [...], summary: %{...}}}
      {:error, %{schemas: [...], summary: %{...}}}
  """
  @spec validate_all(keyword()) :: {:ok, map()} | {:error, map()}
  def validate_all(opts \\ []) do
    _repo = Keyword.get(opts, :repo, @default_repo)
    quiet = Keyword.get(opts, :quiet, false)

    schemas = discover_schemas()

    unless quiet do
      Logger.info("Validating #{length(schemas)} schemas against database...")
    end

    results =
      Enum.map(schemas, fn schema_module ->
        result = validate(schema_module, opts)
        {schema_module, result}
      end)

    errors = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)
    successes = Enum.filter(results, fn {_, result} -> match?({:ok, _}, result) end)

    summary = %{
      total: length(schemas),
      valid: length(successes),
      invalid: length(errors)
    }

    if errors == [] do
      {:ok, %{schemas: results, summary: summary}}
    else
      {:error, %{schemas: results, summary: summary}}
    end
  end

  @doc """
  Validates a single schema module against its database table.

  ## Options

    * `:repo` - Ecto repo to use (default: `Events.Core.Repo`)
    * `:fail_on_extra_columns` - Treat extra DB columns as errors (default: false)
    * `:check_indexes` - Validate index existence (default: false)

  ## Returns

      {:ok, %{columns: ..., constraints: ..., associations: ...}}
      {:error, %{columns: ..., constraints: ..., associations: ...}}
  """
  @spec validate(module(), keyword()) :: {:ok, map()} | {:error, map()}
  def validate(schema_module, opts \\ []) do
    repo = Keyword.get(opts, :repo, @default_repo)

    unless function_exported?(schema_module, :__schema__, 1) do
      {:error, %{error: "#{inspect(schema_module)} is not an Ecto schema"}}
    else
      table = schema_module.__schema__(:source)

      # Check if table exists
      unless PgIntrospection.table_exists?(repo, table) do
        {:error, %{error: "table #{table} does not exist"}}
      else
        validation_opts = [
          repo: repo,
          table: table,
          schema_module: schema_module,
          check_extra_columns: Keyword.get(opts, :fail_on_extra_columns, false),
          check_indexes: Keyword.get(opts, :check_indexes, false)
        ]

        # Run all checkers
        column_result = ColumnChecker.validate(validation_opts)
        constraint_result = ConstraintChecker.validate(validation_opts)
        assoc_result = AssociationChecker.validate(validation_opts)

        # Aggregate results
        aggregate_results(column_result, constraint_result, assoc_result)
      end
    end
  end

  defp aggregate_results(column_result, constraint_result, assoc_result) do
    all_errors = []
    all_warnings = []
    validated = 0

    {all_errors, all_warnings, validated} =
      case column_result do
        {:ok, %{validated: v, warnings: w}} ->
          {all_errors, all_warnings ++ Enum.map(w, &{:column, &1}), validated + v}

        {:error, %{errors: e, warnings: w}} ->
          {all_errors ++ Enum.map(e, &{:column, &1}), all_warnings ++ Enum.map(w, &{:column, &1}),
           validated}
      end

    {all_errors, all_warnings, validated} =
      case constraint_result do
        {:ok, %{validated: v, warnings: w}} ->
          {all_errors, all_warnings ++ Enum.map(w, &{:constraint, &1}), validated + v}

        {:error, %{errors: e, warnings: w}} ->
          {all_errors ++ Enum.map(e, &{:constraint, &1}),
           all_warnings ++ Enum.map(w, &{:constraint, &1}), validated}
      end

    {all_errors, all_warnings, validated} =
      case assoc_result do
        {:ok, %{validated: v, warnings: w}} ->
          {all_errors, all_warnings ++ Enum.map(w, &{:association, &1}), validated + v}

        {:error, %{errors: e, warnings: w}} ->
          {all_errors ++ Enum.map(e, &{:association, &1}),
           all_warnings ++ Enum.map(w, &{:association, &1}), validated}
      end

    result = %{
      columns: column_result,
      constraints: constraint_result,
      associations: assoc_result,
      validated: validated,
      errors: all_errors,
      warnings: all_warnings
    }

    if all_errors == [] do
      {:ok, result}
    else
      {:error, result}
    end
  end

  @doc """
  Returns a detailed validation report for a schema.

  Unlike `validate/2`, this always returns a report (never fails),
  including all validation details for debugging.
  """
  @spec report(module(), keyword()) :: map()
  def report(schema_module, opts \\ []) do
    repo = Keyword.get(opts, :repo, @default_repo)
    table = schema_module.__schema__(:source)

    validation_opts = [
      repo: repo,
      table: table,
      schema_module: schema_module
    ]

    %{
      schema: schema_module,
      table: table,
      columns: ColumnChecker.summary(validation_opts),
      constraints: ConstraintChecker.summary(validation_opts),
      associations: AssociationChecker.summary(validation_opts),
      db_columns: PgIntrospection.columns(repo, table),
      db_constraints: PgIntrospection.constraints(repo, table),
      db_foreign_keys: PgIntrospection.foreign_keys(repo, table),
      db_indexes: PgIntrospection.indexes(repo, table)
    }
  end

  @doc """
  Validates schemas on application startup.

  Called from `Events.Application.start/2` when configured.

  ## Configuration

      config :events, :schema_validation,
        enabled: true,
        on_startup: true,
        fail_on_error: false
  """
  @spec validate_on_startup() :: :ok | {:error, term()}
  def validate_on_startup do
    config = Application.get_env(:events, :schema_validation, [])

    if Keyword.get(config, :enabled, false) do
      case validate_all(quiet: true) do
        {:ok, %{summary: summary}} ->
          Logger.info("Schema validation passed: #{summary.valid}/#{summary.total} schemas valid")
          :ok

        {:error, %{schemas: results, summary: summary}} ->
          error_msg = format_startup_errors(results)

          if Keyword.get(config, :fail_on_error, false) do
            Logger.error("Schema validation failed:\n#{error_msg}")
            {:error, "Schema validation failed: #{summary.invalid} schema(s) invalid"}
          else
            Logger.warning("Schema validation issues:\n#{error_msg}")
            :ok
          end
      end
    else
      :ok
    end
  end

  defp format_startup_errors(results) do
    results
    |> Enum.filter(fn {_, result} -> match?({:error, _}, result) end)
    |> Enum.map(fn {schema, {:error, details}} ->
      errors = details[:errors] || []
      "  #{inspect(schema)}: #{length(errors)} error(s)"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Discovers all schema modules that use Events.Core.Schema.

  Looks for modules with `__constraints__/0` function as indicator.
  Uses Application.spec/2 to get all compiled modules for the :events app.
  """
  @spec discover_schemas() :: [module()]
  def discover_schemas do
    # Get all modules from the :events application
    # This returns all compiled modules, unlike :code.all_loaded()
    Application.spec(:events, :modules)
    |> Kernel.||([])
    |> Enum.filter(&events_schema?/1)
    |> Enum.sort()
  end

  defp events_schema?(module) do
    # Ensure module is loaded before checking
    Code.ensure_loaded?(module) &&
      function_exported?(module, :__constraints__, 0) &&
      function_exported?(module, :__schema__, 1)
  rescue
    _ -> false
  end

  @doc """
  Discovers schemas matching a pattern.

  ## Examples

      discover_schemas("Events.Domains.Accounts.*")
      # => [Events.Domains.Accounts.User, Events.Domains.Accounts.Membership, ...]
  """
  @spec discover_schemas(String.t()) :: [module()]
  def discover_schemas(pattern) do
    regex = pattern_to_regex(pattern)

    discover_schemas()
    |> Enum.filter(fn mod ->
      Regex.match?(regex, to_string(mod))
    end)
  end

  defp pattern_to_regex(pattern) do
    pattern
    |> String.replace(".", "\\.")
    |> String.replace("*", ".*")
    |> then(&Regex.compile!("^Elixir\\.#{&1}$"))
  end

  @doc """
  Formats validation results for display.

  Returns a string suitable for terminal output.
  """
  @spec format_results(map()) :: String.t()
  def format_results(%{schemas: results, summary: summary}) do
    schema_output =
      results
      |> Enum.map(&format_schema_result/1)
      |> Enum.join("\n\n")

    """
    #{schema_output}

    Summary: #{summary.valid} valid, #{summary.invalid} with errors
    """
  end

  defp format_schema_result({schema_module, {:ok, details}}) do
    table = schema_module.__schema__(:source)
    warnings = details[:warnings] || []

    warning_lines =
      if warnings != [] do
        Enum.map(warnings, fn {type, {field, msg}} ->
          "  ⚠ [#{type}] #{field}: #{msg}"
        end)
        |> Enum.join("\n")
      else
        ""
      end

    """
    #{inspect(schema_module)} (#{table})
      ✓ #{details.validated} validations passed#{if warning_lines != "", do: "\n" <> warning_lines, else: ""}
    """
    |> String.trim()
  end

  defp format_schema_result({schema_module, {:error, details}}) do
    table = schema_module.__schema__(:source)
    errors = details[:errors] || []
    warnings = details[:warnings] || []

    error_lines =
      Enum.map(errors, fn {type, {field, msg}} ->
        "  ✗ [#{type}] #{field}: #{msg}"
      end)
      |> Enum.join("\n")

    warning_lines =
      if warnings != [] do
        Enum.map(warnings, fn {type, {field, msg}} ->
          "  ⚠ [#{type}] #{field}: #{msg}"
        end)
        |> Enum.join("\n")
      else
        ""
      end

    """
    #{inspect(schema_module)} (#{table})
    #{error_lines}#{if warning_lines != "", do: "\n" <> warning_lines, else: ""}
    """
    |> String.trim()
  end
end
