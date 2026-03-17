defmodule FnDecorator.Compose do
  @moduledoc """
  Utilities for composing and combining decorators.

  Provides patterns for:
  - Defining reusable decorator bundles (presets)
  - Conditional decorator application
  - Environment-specific decorators
  - Decorator chaining with metadata

  ## Defining Presets

  Create reusable decorator combinations:

      defmodule MyApp.DecoratorPresets do
        use FnDecorator.Compose

        # Define a preset for monitored operations
        defpreset :monitored do
          [
            {:telemetry_span, [[:my_app, :operation]]},
            {:log_if_slow, [threshold: 1000]},
            {:capture_errors, [reporter: Sentry]}
          ]
        end

        # Parameterized preset
        defpreset :cached, opts do
          cache = Keyword.fetch!(opts, :cache)
          ttl = Keyword.get(opts, :ttl, 3600)
          [
            {:cacheable, [cache: cache, ttl: ttl]},
            {:telemetry_span, [[:my_app, :cache, :access]]}
          ]
        end
      end

  ## Using Presets

      defmodule MyApp.Users do
        use FnDecorator
        import MyApp.DecoratorPresets

        @decorate compose(monitored())
        def get_user(id) do
          Repo.get(User, id)
        end

        @decorate compose(cached(cache: MyApp.Cache, ttl: 7200))
        def get_settings(user_id) do
          Settings.for_user(user_id)
        end
      end

  ## Conditional Decorators

      @decorate when_env(:prod, {:telemetry_span, [[:app, :op]]})
      def operation do
        # Telemetry only in production
      end

      @decorate unless_env(:test, {:cacheable, [cache: MyCache, key: id]})
      def cached_op(id) do
        # Caching disabled in tests
      end

  ## Chaining with Metadata

      @decorate chain([
        {:telemetry_span, [[:app, :users, :create]]},
        {:audit_log, [action: :create, resource: :user]},
        {:rate_limit, [limit: 100, window: :minute]}
      ], metadata: %{feature: :user_management})
      def create_user(attrs) do
        Repo.insert(User.changeset(%User{}, attrs))
      end
  """

  @doc """
  Imports preset macros when `use`d.
  """
  defmacro __using__(_opts) do
    quote do
      import FnDecorator.Compose, only: [defpreset: 2, defpreset: 3]
    end
  end

  @doc """
  Defines a decorator preset (zero-argument version).

  ## Examples

      defpreset :monitored do
        [
          {:telemetry_span, [[:app, :operation]]},
          {:log_if_slow, [threshold: 1000]}
        ]
      end
  """
  defmacro defpreset(name, do: body) do
    quote do
      def unquote(name)() do
        unquote(body)
      end
    end
  end

  @doc """
  Defines a parameterized decorator preset.

  ## Examples

      defpreset :cached, opts do
        cache = Keyword.fetch!(opts, :cache)
        [
          {:cacheable, [cache: cache, key: opts[:key]]},
          {:telemetry_span, [[:app, :cache]]}
        ]
      end
  """
  defmacro defpreset(name, opts_var, do: body) do
    quote do
      def unquote(name)(unquote(opts_var)) do
        unquote(body)
      end
    end
  end

  @doc """
  Merges multiple decorator lists into one.

  Useful for combining presets or adding decorators to an existing list.

  ## Examples

      merge([monitored(), cached(cache: MyCache)])
      #=> [{:telemetry_span, [...]}, {:log_if_slow, [...]}, {:cacheable, [...]}]

      merge([base_decorators(), {:debug, [label: "extra"]}])
  """
  @spec merge([list() | tuple()]) :: list()
  def merge(decorator_lists) when is_list(decorator_lists) do
    Enum.flat_map(decorator_lists, fn
      decorators when is_list(decorators) -> decorators
      decorator when is_tuple(decorator) -> [decorator]
      decorator when is_atom(decorator) -> [decorator]
    end)
  end

  @doc """
  Conditionally includes decorators based on environment.

  Returns the decorators if the current environment matches,
  otherwise returns an empty list.

  ## Examples

      # Only in production
      when_env(:prod, {:telemetry_span, [[:app, :op]]})

      # In dev or test
      when_env([:dev, :test], {:debug, [label: "debug"]})
  """
  @spec when_env(atom() | [atom()], list() | tuple()) :: list()
  def when_env(env_or_envs, decorators) do
    current_env = Mix.env()
    envs = List.wrap(env_or_envs)

    if current_env in envs do
      List.wrap(decorators)
    else
      []
    end
  end

  @doc """
  Conditionally excludes decorators in specified environments.

  Returns the decorators unless the current environment matches.

  ## Examples

      # Skip caching in tests
      unless_env(:test, {:cacheable, [cache: MyCache, key: id]})

      # Skip telemetry in dev/test
      unless_env([:dev, :test], {:telemetry_span, [[:app, :op]]})
  """
  @spec unless_env(atom() | [atom()], list() | tuple()) :: list()
  def unless_env(env_or_envs, decorators) do
    current_env = Mix.env()
    envs = List.wrap(env_or_envs)

    if current_env in envs do
      []
    else
      List.wrap(decorators)
    end
  end

  @doc """
  Conditionally applies decorators based on a boolean or function.

  ## Examples

      # Boolean condition
      when_true(config[:caching_enabled], {:cacheable, [cache: MyCache]})

      # Function condition (evaluated at compile time)
      when_true(fn -> Application.get_env(:my_app, :feature_flags)[:audit] end,
        {:audit_log, [action: :create]})
  """
  @spec when_true(boolean() | (-> boolean()), list() | tuple()) :: list()
  def when_true(condition, decorators) when is_function(condition, 0) do
    if condition.() do
      List.wrap(decorators)
    else
      []
    end
  end

  def when_true(condition, decorators) when is_boolean(condition) do
    if condition do
      List.wrap(decorators)
    else
      []
    end
  end

  @doc """
  Adds metadata to a list of decorators for tracking purposes.

  The metadata is available in telemetry events and logging.

  ## Examples

      with_metadata([
        {:telemetry_span, [[:app, :users]]},
        {:log_call, [level: :info]}
      ], feature: :user_management, version: "2.0")
  """
  @spec with_metadata(list(), keyword()) :: list()
  def with_metadata(decorators, metadata) when is_list(decorators) and is_list(metadata) do
    Enum.map(decorators, fn
      {name, opts} when is_list(opts) ->
        # Check if opts is a keyword list or a plain list
        if Keyword.keyword?(opts) do
          {name, Keyword.merge(opts, metadata: Map.new(metadata))}
        else
          # Plain list (like event names), wrap with metadata
          {name, [value: opts, metadata: Map.new(metadata)]}
        end

      {name, opts} when is_map(opts) ->
        {name, Map.merge(opts, %{metadata: Map.new(metadata)})}

      name when is_atom(name) ->
        {name, [metadata: Map.new(metadata)]}
    end)
  end

  @doc """
  Builds a decorator specification with common patterns.

  ## Options

  - `:base` - Base decorators to always include
  - `:prod_only` - Decorators only for production
  - `:dev_only` - Decorators only for development
  - `:test_only` - Decorators only for testing
  - `:conditional` - List of `{condition, decorators}` tuples
  - `:metadata` - Metadata to attach to all decorators

  ## Examples

      build(
        base: [
          {:telemetry_span, [[:app, :operation]]}
        ],
        prod_only: [
          {:capture_errors, [reporter: Sentry]}
        ],
        dev_only: [
          {:debug, [label: "operation"]}
        ],
        metadata: [feature: :core]
      )
  """
  @spec build(keyword()) :: list()
  def build(opts) when is_list(opts) do
    base = Keyword.get(opts, :base, [])
    prod_only = Keyword.get(opts, :prod_only, [])
    dev_only = Keyword.get(opts, :dev_only, [])
    test_only = Keyword.get(opts, :test_only, [])
    conditional = Keyword.get(opts, :conditional, [])
    metadata = Keyword.get(opts, :metadata, [])

    decorators =
      merge([
        base,
        when_env(:prod, prod_only),
        when_env(:dev, dev_only),
        when_env(:test, test_only)
        | Enum.map(conditional, fn {condition, decs} -> when_true(condition, decs) end)
      ])

    if metadata == [] do
      decorators
    else
      with_metadata(decorators, metadata)
    end
  end

  @doc """
  Creates a decorator that wraps another with before/after hooks.

  Useful for custom cross-cutting concerns without creating full decorators.

  ## Examples

      wrap(:cacheable,
        before: fn _opts, _context -> Logger.info("Cache lookup starting") end,
        after: fn _result, _opts, _context -> Logger.info("Cache lookup complete") end
      )
  """
  @spec wrap(atom(), keyword()) :: {atom(), keyword()}
  def wrap(decorator_name, hooks) when is_atom(decorator_name) and is_list(hooks) do
    before_hook = Keyword.get(hooks, :before)
    after_hook = Keyword.get(hooks, :after)
    base_opts = Keyword.get(hooks, :opts, [])

    opts =
      base_opts
      |> maybe_add_hook(:before_hook, before_hook)
      |> maybe_add_hook(:after_hook, after_hook)

    {decorator_name, opts}
  end

  defp maybe_add_hook(opts, _key, nil), do: opts
  defp maybe_add_hook(opts, key, hook), do: Keyword.put(opts, key, hook)

  @doc """
  Creates a reusable decorator bundle that can be imported.

  Returns a module that exports the bundle as a function.

  ## Examples

      # Define the bundle
      FnDecorator.Compose.define_bundle(MyApp.Bundles.Monitored, [
        {:telemetry_span, [[:app, :operation]]},
        {:log_if_slow, [threshold: 1000]},
        {:capture_errors, [reporter: Sentry]}
      ])

      # Use it
      @decorate compose(MyApp.Bundles.Monitored.decorators())
      def my_function do
        # ...
      end
  """
  defmacro define_bundle(module_name, decorators) do
    quote do
      defmodule unquote(module_name) do
        @decorators unquote(decorators)

        def decorators, do: @decorators

        def decorators(overrides) when is_list(overrides) do
          Enum.map(@decorators, fn
            {name, opts} ->
              case Keyword.get(overrides, name) do
                nil -> {name, opts}
                override_opts -> {name, Keyword.merge(opts, override_opts)}
              end

            name ->
              case Keyword.get(overrides, name) do
                nil -> name
                override_opts -> {name, override_opts}
              end
          end)
        end
      end
    end
  end

  @doc """
  Validates a decorator specification at compile time.

  Raises if any decorator in the list is not registered.

  ## Examples

      validate!([
        {:cacheable, [cache: MyCache]},
        {:telemetry_span, [[:app, :op]]}
      ])
      #=> :ok (or raises ArgumentError)
  """
  @spec validate!(list()) :: :ok
  def validate!(decorators) when is_list(decorators) do
    Enum.each(decorators, fn
      {name, _opts} when is_atom(name) ->
        unless FnDecorator.Registry.registered?(name) do
          raise ArgumentError,
                "Unknown decorator #{inspect(name)}. " <>
                  "Available decorators: #{inspect(Map.keys(FnDecorator.Registry.all()))}"
        end

      name when is_atom(name) ->
        unless FnDecorator.Registry.registered?(name) do
          raise ArgumentError,
                "Unknown decorator #{inspect(name)}. " <>
                  "Available decorators: #{inspect(Map.keys(FnDecorator.Registry.all()))}"
        end

      other ->
        raise ArgumentError,
              "Invalid decorator specification: #{inspect(other)}. " <>
                "Expected {name, opts} tuple or atom."
    end)

    :ok
  end

  @doc """
  Returns a summary of decorators that would be applied.

  Useful for debugging and documentation.

  ## Examples

      describe([
        {:cacheable, [cache: MyCache, ttl: 3600]},
        {:telemetry_span, [[:app, :users, :get]]}
      ])
      #=> "cacheable(cache: MyCache, ttl: 3600) -> telemetry_span([:app, :users, :get])"
  """
  @spec describe(list()) :: String.t()
  def describe(decorators) when is_list(decorators) do
    decorators
    |> Enum.map(fn
      {name, opts} -> "#{name}(#{inspect_opts(opts)})"
      name -> "#{name}()"
    end)
    |> Enum.join(" -> ")
  end

  defp inspect_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
      |> Enum.join(", ")
    else
      # Plain list, just inspect it
      inspect(opts)
    end
  end

  defp inspect_opts(opts), do: inspect(opts)
end
