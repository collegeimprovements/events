defmodule Events.Core.Schema.RelationshipValidator do
  @moduledoc """
  Validates schema relationships at compile time.

  Add to your application's `start/2` callback or a separate supervision tree
  to validate relationships at startup (development only).

  ## Usage

  In `application.ex`:

      def start(_type, _args) do
        # Validate relationships in dev
        if Application.get_env(:my_app, :env) == :dev do
          Events.Core.Schema.RelationshipValidator.validate_all!()
        end

        # ... rest of start
      end

  Or register as a compiler callback in `mix.exs`:

      def project do
        [
          # ...
          compilers: Mix.compilers() ++ [:schema_relationships]
        ]
      end
  """

  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)

  @doc """
  Validates all schema relationships and logs warnings for missing inverses.

  Returns `:ok` if all valid, or `{:error, issues}` with list of problems.
  """
  def validate_all do
    schemas = discover_schemas()
    issues = find_missing_inverses(schemas)

    if Enum.empty?(issues) do
      :ok
    else
      {:error, issues}
    end
  end

  @doc """
  Same as `validate_all/0` but logs warnings and returns `:ok`.
  """
  def validate_all! do
    case validate_all() do
      :ok ->
        :ok

      {:error, issues} ->
        Enum.each(issues, fn issue ->
          require Logger

          Logger.warning("""
          Missing inverse relationship:
            #{inspect(issue.module)}.#{issue.field} belongs_to #{inspect(issue.related_module)}
            but #{inspect(issue.related_module)} has no has_many/has_one pointing back.

          Suggestion:
          #{issue.suggestion}
          """)
        end)

        :ok
    end
  end

  @doc """
  Checks if a specific module's relationships are valid.
  """
  def validate(module) do
    schemas = discover_schemas()
    associations = get_associations(module)

    issues =
      associations
      |> Enum.filter(fn {_name, assoc} ->
        assoc.cardinality == :one && assoc.relationship == :child
      end)
      |> Enum.flat_map(fn {name, assoc} ->
        validate_belongs_to(module, name, assoc, schemas)
      end)

    if Enum.empty?(issues), do: :ok, else: {:error, issues}
  end

  # Private functions

  defp discover_schemas do
    case :application.get_key(@app_name, :modules) do
      {:ok, modules} ->
        modules
        |> Enum.filter(&ecto_schema?/1)
        |> Enum.map(fn module -> {module, get_associations(module)} end)
        |> Map.new()

      _ ->
        %{}
    end
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

  defp find_missing_inverses(schemas) do
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
          suggestion: suggest_inverse(module, assoc)
        }
      ]
    end
  end

  defp suggest_inverse(module, assoc) do
    module_name = module |> Module.split() |> List.last()
    field_name = module_name |> Macro.underscore()
    plural_name = pluralize(field_name)
    owner_key = assoc.owner_key

    "has_many :#{plural_name}, #{inspect(module)}, foreign_key: :#{owner_key}"
  end

  defp pluralize(str) do
    cond do
      String.ends_with?(str, "y") ->
        String.slice(str, 0..-2//1) <> "ies"

      String.ends_with?(str, ["s", "x", "ch", "sh"]) ->
        str <> "es"

      true ->
        str <> "s"
    end
  end
end
