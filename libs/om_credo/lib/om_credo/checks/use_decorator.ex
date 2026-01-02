defmodule OmCredo.Checks.UseDecorator do
  @moduledoc """
  Checks that context and service modules use a decorator system.

  This ensures consistent cross-cutting concerns like telemetry, caching, and validation.

  ## Why This Matters

  Decorator systems provide:
  - Type contracts with `@decorate returns_result(...)`
  - Automatic telemetry with `@decorate telemetry_span(...)`
  - Caching with `@decorate cacheable(...)`
  - Validation with `@decorate validate_schema(...)`

  ## Examples

  Incorrect:

      defmodule MyApp.Accounts do
        def get_user(id) do
          # No decorators - missing type contract, telemetry
        end
      end

  Correct:

      defmodule MyApp.Accounts do
        use FnDecorator

        @decorate returns_result(ok: User.t(), error: :atom)
        @decorate telemetry_span([:my_app, :accounts, :get_user])
        def get_user(id) do
          # ...
        end
      end

  ## Configuration

      {OmCredo.Checks.UseDecorator, [
        decorator_module: FnDecorator,
        paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"],
        path_patterns: ["_context.ex", "_service.ex"]
      ]}
  """

  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      decorator_module: FnDecorator,
      paths: [],
      path_patterns: ["_context.ex", "_service.ex"]
    ],
    explanations: [
      check: """
      Context and service modules should use a decorator system for
      type contracts, telemetry, and other cross-cutting concerns.
      """,
      params: [
        decorator_module: "The decorator module to check for (e.g., FnDecorator)",
        paths: "List of paths to check (e.g., [\"/lib/myapp/contexts/\"])",
        path_patterns: "List of filename patterns to check (e.g., [\"_context.ex\"])"
      ]
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    paths = Params.get(params, :paths, __MODULE__)
    patterns = Params.get(params, :path_patterns, __MODULE__)

    if should_check?(source_file.filename, paths, patterns) do
      issue_meta = IssueMeta.for(source_file, params)
      decorator_module = Params.get(params, :decorator_module, __MODULE__)
      decorator_parts = module_to_parts(decorator_module)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta, decorator_parts))
      |> check_decorator_usage(issue_meta, decorator_module)
    else
      []
    end
  end

  defp should_check?(filename, paths, patterns) do
    path_match = Enum.empty?(paths) or Enum.any?(paths, &String.contains?(filename, &1))
    pattern_match = Enum.any?(patterns, &String.contains?(filename, &1))
    path_match and pattern_match
  end

  defp module_to_parts(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  defp module_to_parts(parts) when is_list(parts), do: parts

  # Check for use DecoratorModule
  defp traverse({:use, _, [{:__aliases__, _, alias_parts} | _]} = ast, acc, _issue_meta, decorator_parts) do
    if alias_parts == decorator_parts do
      {ast, Map.put(acc, :has_decorator, true)}
    else
      {ast, acc}
    end
  end

  # Check for defmodule to get the line number
  defp traverse({:defmodule, meta, _} = ast, acc, _issue_meta, _decorator_parts) do
    {ast, Map.put(acc, :module_line, meta[:line])}
  end

  defp traverse(ast, acc, _issue_meta, _decorator_parts), do: {ast, acc}

  defp check_decorator_usage(%{has_decorator: true}, _issue_meta, _decorator_module), do: []

  defp check_decorator_usage(acc, issue_meta, decorator_module) do
    line = Map.get(acc, :module_line, 1)

    decorator_name =
      if is_atom(decorator_module), do: inspect(decorator_module), else: format_module(decorator_module)

    [
      format_issue(
        issue_meta,
        message: "Consider using `use #{decorator_name}` for type contracts and telemetry.",
        trigger: "defmodule",
        line_no: line,
        priority: :low
      )
    ]
  end

  defp format_module(parts) when is_list(parts) do
    parts |> Enum.map(&Atom.to_string/1) |> Enum.join(".")
  end
end
