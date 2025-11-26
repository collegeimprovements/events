defmodule Mix.Tasks.Schema.ValidateRelationships do
  @moduledoc """
  Validates that all schema relationships are bidirectional.

  For every `belongs_to`, there should be a corresponding `has_many` or `has_one`
  on the related schema.

  ## Usage

      mix schema.validate_relationships

  ## Options

      --fix    Generate code suggestions for missing relationships
      --strict Exit with error code if issues found (useful for CI)
  """

  use Mix.Task

  @shortdoc "Validates bidirectional schema relationships"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [fix: :boolean, strict: :boolean])

    Mix.Task.run("compile", ["--no-start"])

    schemas = discover_schemas()
    issues = validate_relationships(schemas)

    if Enum.empty?(issues) do
      Mix.shell().info([:green, "✓ All relationships are bidirectional"])
    else
      print_issues(issues, opts[:fix])

      if opts[:strict] do
        Mix.raise("Relationship validation failed with #{length(issues)} issue(s)")
      end
    end
  end

  defp discover_schemas do
    # Get all modules that have __schema__ function (Ecto schemas)
    {:ok, modules} = :application.get_key(:events, :modules)

    modules
    |> Enum.filter(&ecto_schema?/1)
    |> Enum.map(fn module ->
      {module, get_associations(module)}
    end)
    |> Map.new()
  end

  defp ecto_schema?(module) do
    Code.ensure_loaded?(module) &&
      function_exported?(module, :__schema__, 1)
  end

  defp get_associations(module) do
    module.__schema__(:associations)
    |> Enum.map(fn name ->
      assoc = module.__schema__(:association, name)
      {name, assoc}
    end)
    |> Map.new()
  end

  defp validate_relationships(schemas) do
    schemas
    |> Enum.flat_map(fn {module, associations} ->
      associations
      |> Enum.filter(fn {_name, assoc} ->
        assoc.cardinality == :one && assoc.relationship == :child
      end)
      |> Enum.flat_map(fn {name, assoc} ->
        validate_belongs_to(module, name, assoc, schemas)
      end)
    end)
  end

  defp validate_belongs_to(module, field_name, assoc, schemas) do
    related_module = assoc.related
    related_associations = Map.get(schemas, related_module, %{})

    # Check if the related module has a has_many/has_one pointing back
    has_inverse? =
      Enum.any?(related_associations, fn {_name, rel_assoc} ->
        rel_assoc.related == module &&
          rel_assoc.relationship == :parent &&
          rel_assoc.cardinality in [:one, :many]
      end)

    if has_inverse? do
      []
    else
      [
        %{
          type: :missing_inverse,
          module: module,
          field: field_name,
          related_module: related_module,
          suggestion: suggest_inverse(module, field_name, assoc)
        }
      ]
    end
  end

  defp suggest_inverse(module, _field_name, assoc) do
    module_name = module |> Module.split() |> List.last()
    field_name = module_name |> Macro.underscore() |> String.to_atom()
    plural_name = pluralize(field_name)

    owner_key = assoc.owner_key

    """
    # Add to #{inspect(assoc.related)}:
    has_many :#{plural_name}, #{inspect(module)}, foreign_key: :#{owner_key}
    # or
    has_one :#{field_name}, #{inspect(module)}, foreign_key: :#{owner_key}
    """
  end

  defp pluralize(atom) when is_atom(atom) do
    str = Atom.to_string(atom)

    cond do
      String.ends_with?(str, "y") ->
        String.slice(str, 0..-2//1) <> "ies"

      String.ends_with?(str, ["s", "x", "ch", "sh"]) ->
        str <> "es"

      true ->
        str <> "s"
    end
  end

  defp print_issues(issues, show_fix?) do
    Mix.shell().info([:yellow, "\n⚠ Found #{length(issues)} relationship issue(s):\n"])

    Enum.each(issues, fn issue ->
      Mix.shell().info([
        :red,
        "  • ",
        :reset,
        "#{inspect(issue.module)}.#{issue.field}",
        :yellow,
        " belongs_to ",
        :reset,
        "#{inspect(issue.related_module)}",
        :red,
        " but no inverse relationship found"
      ])

      if show_fix? do
        Mix.shell().info([:cyan, "\n", issue.suggestion])
      end
    end)

    unless show_fix? do
      Mix.shell().info([:dim, "\n  Run with --fix to see suggestions\n"])
    end
  end
end
