defmodule FnDecorator.Registry do
  @moduledoc """
  Registry for decorator functions.

  Maps decorator names to their implementing module and function.
  Enables dynamic decorator resolution for composition.

  ## Built-in Decorators

  | Decorator | Module | Description |
  |-----------|--------|-------------|
  | `:cacheable` | `FnDecorator.Caching` | Read-through caching |
  | `:cache_put` | `FnDecorator.Caching` | Write-through caching |
  | `:cache_evict` | `FnDecorator.Caching` | Cache invalidation |
  | `:telemetry_span` | `FnDecorator.Telemetry` | Telemetry spans |
  | `:telemetry_event` | `FnDecorator.Telemetry` | Telemetry events |
  | `:role_required` | `FnDecorator.Security` | Role-based access |
  | `:rate_limit` | `FnDecorator.Security` | Rate limiting |
  | `:audit_log` | `FnDecorator.Security` | Audit logging |
  | `:log_call` | `FnDecorator.Debugging` | Function call logging |
  | `:log_if_slow` | `FnDecorator.Debugging` | Slow function logging |
  | `:trace` | `FnDecorator.Tracing` | Function tracing |
  | `:validate_args` | `FnDecorator.Validation` | Argument validation |
  | `:validate_return` | `FnDecorator.Validation` | Return value validation |

  ## Custom Decorators

  Register custom decorators at application startup:

      FnDecorator.Registry.register(:my_decorator, MyModule, :my_decorator)

  ## Usage

      {module, function} = FnDecorator.Registry.get(:cacheable)
      apply(module, function, [opts, body, context])
  """

  use Agent

  @default_decorators %{
    # Caching decorators
    cacheable: {FnDecorator.Caching, :cacheable},
    cache_put: {FnDecorator.Caching, :cache_put},
    cache_evict: {FnDecorator.Caching, :cache_evict},

    # Telemetry decorators
    telemetry_span: {FnDecorator.Telemetry, :telemetry_span},
    telemetry_event: {FnDecorator.Telemetry, :telemetry_event},

    # Security decorators
    role_required: {FnDecorator.Security, :role_required},
    rate_limit: {FnDecorator.Security, :rate_limit},
    audit_log: {FnDecorator.Security, :audit_log},

    # Debugging decorators
    log_call: {FnDecorator.Debugging, :log_call},
    log_if_slow: {FnDecorator.Debugging, :log_if_slow},
    inspect_args: {FnDecorator.Debugging, :inspect_args},
    inspect_result: {FnDecorator.Debugging, :inspect_result},

    # Tracing decorators
    trace: {FnDecorator.Tracing, :trace},

    # Validation decorators
    validate_args: {FnDecorator.Validation, :validate_args},
    validate_return: {FnDecorator.Validation, :validate_return},

    # Purity decorators
    pure: {FnDecorator.Purity, :pure},
    memoize: {FnDecorator.Purity, :memoize},

    # Pipeline decorators
    pipe_through: {FnDecorator.Pipeline, :pipe_through},
    around: {FnDecorator.Pipeline, :around}
  }

  @doc """
  Starts the decorator registry.

  Called automatically by the Events application supervisor.
  """
  def start_link(_opts) do
    Agent.start_link(fn -> @default_decorators end, name: __MODULE__)
  end

  @doc """
  Gets the module and function for a decorator.

  Returns `nil` if no decorator is registered with that name.

  ## Examples

      iex> FnDecorator.Registry.get(:cacheable)
      {FnDecorator.Caching, :cacheable}

      iex> FnDecorator.Registry.get(:unknown)
      nil
  """
  @spec get(atom()) :: {module(), atom()} | nil
  def get(decorator_name) when is_atom(decorator_name) do
    case Process.whereis(__MODULE__) do
      nil ->
        # Agent not started, use defaults
        Map.get(@default_decorators, decorator_name)

      _pid ->
        Agent.get(__MODULE__, &Map.get(&1, decorator_name))
    end
  end

  @doc """
  Checks if a decorator is registered.

  ## Examples

      iex> FnDecorator.Registry.registered?(:cacheable)
      true

      iex> FnDecorator.Registry.registered?(:unknown)
      false
  """
  @spec registered?(atom()) :: boolean()
  def registered?(decorator_name) when is_atom(decorator_name) do
    get(decorator_name) != nil
  end

  @doc """
  Registers a custom decorator.

  The module must export a function with the signature:
  `function_name(opts, body, context)` that returns a quoted expression.

  ## Examples

      FnDecorator.Registry.register(:my_decorator, MyModule, :my_decorator)

  ## Raises

  - `ArgumentError` if the module doesn't export the function with arity 3
  """
  @spec register(atom(), module(), atom()) :: :ok
  def register(decorator_name, module, function)
      when is_atom(decorator_name) and is_atom(module) and is_atom(function) do
    # Verify the module exports the function
    unless function_exported?(module, function, 3) do
      raise ArgumentError,
            "Decorator module #{inspect(module)} must export #{function}/3"
    end

    case Process.whereis(__MODULE__) do
      nil ->
        raise RuntimeError,
              "Decorator.Registry not started. Add FnDecorator.Registry to your supervision tree."

      _pid ->
        Agent.update(__MODULE__, &Map.put(&1, decorator_name, {module, function}))
    end
  end

  @doc """
  Unregisters a decorator.

  Built-in decorators revert to their default implementation.
  Custom decorators are removed entirely.

  ## Examples

      FnDecorator.Registry.unregister(:my_decorator)
  """
  @spec unregister(atom()) :: :ok
  def unregister(decorator_name) when is_atom(decorator_name) do
    default = Map.get(@default_decorators, decorator_name)

    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      _pid ->
        if default do
          Agent.update(__MODULE__, &Map.put(&1, decorator_name, default))
        else
          Agent.update(__MODULE__, &Map.delete(&1, decorator_name))
        end
    end
  end

  @doc """
  Returns all registered decorators.

  ## Examples

      FnDecorator.Registry.all()
      # => %{cacheable: {FnDecorator.Caching, :cacheable}, ...}
  """
  @spec all() :: %{atom() => {module(), atom()}}
  def all do
    case Process.whereis(__MODULE__) do
      nil -> @default_decorators
      _pid -> Agent.get(__MODULE__, & &1)
    end
  end

  @doc """
  Returns the default decorators (before any custom registrations).
  """
  @spec defaults() :: %{atom() => {module(), atom()}}
  def defaults, do: @default_decorators

  @doc """
  Resets the registry to default decorators.

  Useful for testing.
  """
  @spec reset() :: :ok
  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> Agent.update(__MODULE__, fn _ -> @default_decorators end)
    end
  end

  @doc """
  Lists decorators by category.

  ## Examples

      FnDecorator.Registry.by_category()
      # => %{
      #   caching: [:cacheable, :cache_put, :cache_evict],
      #   security: [:role_required, :rate_limit, :audit_log],
      #   ...
      # }
  """
  @spec by_category() :: %{atom() => [atom()]}
  def by_category do
    %{
      caching: [:cacheable, :cache_put, :cache_evict],
      telemetry: [:telemetry_span, :telemetry_event],
      security: [:role_required, :rate_limit, :audit_log],
      debugging: [:log_call, :log_if_slow, :inspect_args, :inspect_result],
      tracing: [:trace],
      validation: [:validate_args, :validate_return],
      purity: [:pure, :memoize],
      pipeline: [:pipe_through, :around, :compose]
    }
  end
end
