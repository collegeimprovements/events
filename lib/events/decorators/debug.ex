defmodule Events.Decorators.Debug do
  @moduledoc """
  Debugging decorators for development and testing.

  Provides interactive debugging, inspection, and tracing tools.

  **Note:** These decorators are intended for development/test only
  and should not be used in production code.

  ## Usage

      defmodule MyModule do
        use Events.Decorator

        @decorate debug()
        def complex_logic(params) do
          # Uses Elixir's dbg/2 for debugging
        end

        @decorate inspect(label: "Input")
        def process(data) do
          # Inspects arguments and results
        end

        @decorate pry()
        def interactive_debug(x) do
          # Sets IEx.pry breakpoint
        end
      end
  """

  @doc """
  Debug with Elixir's dbg/2.

  ## Options

  - `:label` - Custom label for debug output
  - `:inspect_opts` - Options for inspect
  - `:only` - Only debug in specific environments
  """
  defmacro debug(opts \\ []) do
    quote do
      use Decorator.Define, debug: 1
      unquote(opts)
    end
  end

  @doc """
  Inspect function arguments and results.

  ## Options

  - `:label` - Custom label
  - `:args` - Inspect arguments (default: true)
  - `:result` - Inspect result (default: true)
  - `:inspect_opts` - Options for IO.inspect
  """
  defmacro inspect(opts \\ []) do
    quote do
      use Decorator.Define, inspect: 1
      unquote(opts)
    end
  end

  @doc """
  Interactive debugging with IEx.pry.

  ## Options

  - `:condition` - Function to determine when to pry
  - `:label` - Message to display at breakpoint
  """
  defmacro pry(opts \\ []) do
    quote do
      use Decorator.Define, pry: 1
      unquote(opts)
    end
  end

  @doc """
  Trace variable changes.

  ## Options

  - `:vars` - List of variable names to trace
  - `:depth` - Trace depth for nested calls
  """
  defmacro trace_vars(opts \\ []) do
    quote do
      use Decorator.Define, trace_vars: 1
      unquote(opts)
    end
  end

  @doc """
  Trace function calls.

  ## Options

  - `:depth` - Maximum call depth to trace
  - `:modules` - Specific modules to trace
  - `:format` - Output format (:simple, :detailed)
  """
  defmacro trace_calls(opts \\ []) do
    quote do
      use Decorator.Define, trace_calls: 1
      unquote(opts)
    end
  end

  @doc """
  Trace module dependencies.

  ## Options

  - `:include` - Modules to include in trace
  - `:exclude` - Modules to exclude from trace
  """
  defmacro trace_modules(opts \\ []) do
    quote do
      use Decorator.Define, trace_modules: 1
      unquote(opts)
    end
  end

  @doc """
  Trace external dependencies.

  ## Options

  - `:libraries` - Specific libraries to trace
  - `:log_calls` - Log all external calls
  """
  defmacro trace_dependencies(opts \\ []) do
    quote do
      use Decorator.Define, trace_dependencies: 1
      unquote(opts)
    end
  end
end
