defmodule Mix.Tasks.Schema.Validate do
  @moduledoc """
  Validates Ecto schemas against PostgreSQL database structure.

  Ensures schemas don't drift from actual database columns, indexes, and constraints.

  ## Usage

      # Validate all schemas
      mix schema.validate

      # Validate specific schema
      mix schema.validate Events.Domains.Accounts.User

      # Validate by pattern
      mix schema.validate "Events.Domains.Accounts.*"

      # With options
      mix schema.validate --fail-on-extra-db-columns
      mix schema.validate --check-indexes
      mix schema.validate --format=json
      mix schema.validate --quiet

  ## Options

    * `--fail-on-extra-db-columns` - Treat extra database columns as errors
    * `--check-indexes` - Validate that declared indexes exist (normally warnings)
    * `--format` - Output format: `text` (default) or `json`
    * `--quiet` - Only output errors, no success messages

  ## Exit Codes

    * 0 - All schemas valid
    * 1 - One or more schemas invalid

  ## Examples

      # CI validation (exit code based on result)
      mix schema.validate

      # Detailed output for debugging
      mix schema.validate Events.Domains.Accounts.User --check-indexes

      # JSON output for parsing
      mix schema.validate --format=json

  """

  use Mix.Task

  @shortdoc "Validates Ecto schemas against database structure"

  @switches [
    fail_on_extra_db_columns: :boolean,
    check_indexes: :boolean,
    format: :string,
    quiet: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    # Start application to get database connection
    Mix.Task.run("app.start")

    {opts, args} = OptionParser.parse!(args, switches: @switches)

    format = Keyword.get(opts, :format, "text")
    quiet = Keyword.get(opts, :quiet, false)

    validation_opts = [
      fail_on_extra_columns: Keyword.get(opts, :fail_on_extra_db_columns, false),
      check_indexes: Keyword.get(opts, :check_indexes, false),
      quiet: quiet
    ]

    result =
      case args do
        [] ->
          # Validate all schemas
          OmSchema.DatabaseValidator.validate_all(validation_opts)

        [pattern] ->
          if String.contains?(pattern, "*") do
            # Pattern match
            schemas = OmSchema.DatabaseValidator.discover_schemas(pattern)
            validate_multiple(schemas, validation_opts)
          else
            # Single schema
            schema_module = Module.concat([pattern])

            OmSchema.DatabaseValidator.validate(schema_module, validation_opts)
            |> wrap_single_result(schema_module)
          end
      end

    output(result, format, quiet)
    exit_code(result)
  end

  defp validate_multiple(schemas, opts) do
    results =
      Enum.map(schemas, fn schema ->
        {schema, OmSchema.DatabaseValidator.validate(schema, opts)}
      end)

    errors = Enum.filter(results, fn {_, r} -> match?({:error, _}, r) end)
    successes = Enum.filter(results, fn {_, r} -> match?({:ok, _}, r) end)

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

  defp wrap_single_result(result, schema_module) do
    case result do
      {:ok, details} ->
        {:ok,
         %{
           schemas: [{schema_module, {:ok, details}}],
           summary: %{total: 1, valid: 1, invalid: 0}
         }}

      {:error, details} ->
        {:error,
         %{
           schemas: [{schema_module, {:error, details}}],
           summary: %{total: 1, valid: 0, invalid: 1}
         }}
    end
  end

  defp output(result, "json", _quiet) do
    data =
      case result do
        {:ok, map} -> Map.put(map, :status, "ok")
        {:error, map} -> Map.put(map, :status, "error")
      end

    # Convert to JSON-safe format
    data = convert_to_json_safe(data)

    IO.puts(JSON.encode!(data))
  end

  defp output(result, "text", quiet) do
    case result do
      {:ok, %{schemas: results, summary: summary}} ->
        unless quiet do
          output_text_results(results, summary)
        end

      {:error, %{schemas: results, summary: summary}} ->
        output_text_results(results, summary)
    end
  end

  defp output_text_results(results, summary) do
    IO.puts("\nValidating #{summary.total} schema(s) against database...\n")

    Enum.each(results, fn {schema_module, result} ->
      output_schema_result(schema_module, result)
    end)

    IO.puts("")

    if summary.invalid == 0 do
      IO.puts(
        IO.ANSI.green() <>
          "Summary: #{summary.valid}/#{summary.total} schemas valid" <> IO.ANSI.reset()
      )
    else
      IO.puts(
        IO.ANSI.red() <>
          "Summary: #{summary.valid} valid, #{summary.invalid} with errors" <> IO.ANSI.reset()
      )
    end
  end

  defp output_schema_result(schema_module, {:ok, details}) do
    table = schema_module.__schema__(:source)
    warnings = details[:warnings] || []

    IO.puts(IO.ANSI.bright() <> "#{inspect(schema_module)}" <> IO.ANSI.reset() <> " (#{table})")

    IO.puts(
      "  " <>
        IO.ANSI.green() <> "✓" <> IO.ANSI.reset() <> " #{details.validated} validations passed"
    )

    Enum.each(warnings, fn {type, {field, msg}} ->
      IO.puts("  " <> IO.ANSI.yellow() <> "⚠" <> IO.ANSI.reset() <> " [#{type}] #{field}: #{msg}")
    end)

    IO.puts("")
  end

  defp output_schema_result(schema_module, {:error, details}) do
    table = schema_module.__schema__(:source)
    errors = details[:errors] || []
    warnings = details[:warnings] || []

    IO.puts(IO.ANSI.bright() <> "#{inspect(schema_module)}" <> IO.ANSI.reset() <> " (#{table})")

    Enum.each(errors, fn {type, {field, msg}} ->
      IO.puts("  " <> IO.ANSI.red() <> "✗" <> IO.ANSI.reset() <> " [#{type}] #{field}: #{msg}")
    end)

    Enum.each(warnings, fn {type, {field, msg}} ->
      IO.puts("  " <> IO.ANSI.yellow() <> "⚠" <> IO.ANSI.reset() <> " [#{type}] #{field}: #{msg}")
    end)

    IO.puts("")
  end

  defp convert_to_json_safe(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, convert_to_json_safe(v)} end)
  end

  defp convert_to_json_safe(data) when is_list(data) do
    Enum.map(data, &convert_to_json_safe/1)
  end

  defp convert_to_json_safe({a, b}) do
    %{key: convert_to_json_safe(a), value: convert_to_json_safe(b)}
  end

  defp convert_to_json_safe(atom) when is_atom(atom), do: to_string(atom)

  defp convert_to_json_safe(other), do: other

  defp exit_code({:ok, _}), do: System.halt(0)
  defp exit_code({:error, _}), do: System.halt(1)
end
