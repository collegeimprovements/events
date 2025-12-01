defmodule Events.Support.Credo.Checks.UseDecorator do
  @moduledoc """
  Checks that context and service modules use the decorator system.

  This ensures consistent cross-cutting concerns like telemetry, caching, and validation.

  ## Why This Matters

  The decorator system provides:
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
        use Events.Infra.Decorator

        @decorate returns_result(ok: User.t(), error: :atom)
        @decorate telemetry_span([:my_app, :accounts, :get_user])
        def get_user(id) do
          # ...
        end
      end
  """

  use Credo.Check,
    base_priority: :normal,
    category: :design,
    explanations: [
      check: """
      Context and service modules should use `Events.Infra.Decorator` for
      type contracts, telemetry, and other cross-cutting concerns.
      """
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if should_check?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
      |> check_decorator_usage(issue_meta, source_file)
    else
      []
    end
  end

  defp should_check?(filename) do
    cond do
      String.contains?(filename, "/lib/events/accounts/") and
          not String.contains?(filename, "/accounts/user") ->
        true

      String.contains?(filename, "/lib/events/services/") ->
        true

      String.ends_with?(filename, "_context.ex") ->
        true

      String.ends_with?(filename, "_service.ex") ->
        true

      true ->
        false
    end
  end

  # Check for use Events.Infra.Decorator
  defp traverse({:use, _, [{:__aliases__, _, [:Events, :Decorator]} | _]} = ast, acc, _issue_meta) do
    {ast, Map.put(acc, :has_decorator, true)}
  end

  # Check for defmodule to get the line number
  defp traverse({:defmodule, meta, _} = ast, acc, _issue_meta) do
    {ast, Map.put(acc, :module_line, meta[:line])}
  end

  defp traverse(ast, acc, _issue_meta), do: {ast, acc}

  defp check_decorator_usage(%{has_decorator: true}, _issue_meta, _source_file), do: []

  defp check_decorator_usage(acc, issue_meta, _source_file) do
    line = Map.get(acc, :module_line, 1)

    [
      format_issue(
        issue_meta,
        message: "Consider using `use Events.Infra.Decorator` for type contracts and telemetry.",
        trigger: "defmodule",
        line_no: line,
        priority: :low
      )
    ]
  end
end
