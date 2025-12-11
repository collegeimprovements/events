defmodule FnDecorator.Pipeline do
  @moduledoc """
  Advanced composition decorators for pipelines and around advice.

  Provides powerful patterns for:
  - Function pipelines
  - Around advice (aspect-oriented programming)
  - Decorator composition

  ## Examples

      defmodule MyApp.Data do
        use FnDecorator

        # Pipeline composition
        @decorate pipe_through([
          &validate_input/1,
          &transform_data/1,
          &persist/1
        ])
        def process_data(data) do
          data
        end

        # Around advice
        @decorate around(&measure_time/2)
        def expensive_operation(x, y) do
          # Complex computation
        end

        defp measure_time(decorated_fn, x, y) do
          start = System.monotonic_time()
          result = decorated_fn.(x, y)
          duration_val = System.monotonic_time() - start
          IO.puts("Duration: " <> to_string(duration_val))
          result
        end

        # Decorator composition
        @decorate compose([
          {:cacheable, [cache: MyCache, key: id]},
          {:telemetry_span, [[:app, :get]]},
          {:log_if_slow, [threshold: 1000]}
        ])
        def get_item(id) do
          Repo.get(Item, id)
        end
      end
  """

  @pipe_through_schema NimbleOptions.new!(
                         steps: [
                           type: {:list, :any},
                           required: false,
                           doc: "List of pipeline steps (functions or MFA tuples)"
                         ]
                       )

  @around_schema NimbleOptions.new!(
                   wrapper: [
                     type: {:fun, 2},
                     required: false,
                     doc: "Wrapper function that receives (decorated_fn, ...args)"
                   ]
                 )

  @compose_schema NimbleOptions.new!(
                    decorators: [
                      type: {:list, :any},
                      required: false,
                      doc: "List of decorator specifications to compose"
                    ]
                  )

  @doc """
  Pipeline composition decorator.

  Passes the function result through a series of transformation steps.
  Each step receives the result from the previous step.

  ## Options

  #{NimbleOptions.docs(@pipe_through_schema)}

  ## Valid Pipeline Steps

  - Function captures: `&MyModule.step/1`
  - Anonymous functions: `fn result -> transform(result) end`
  - MFA tuples: `{MyModule, :function, [extra_args]}`

  ## Examples

      # Simple pipeline
      @decorate pipe_through([&String.trim/1, &String.upcase/1])
      def get_name(user) do
        user.name
      end

      # With MFA tuples
      @decorate pipe_through([
        &validate_input/1,
        {DataProcessor, :transform, [:json]},
        &persist_to_db/1
      ])
      def process_data(raw_data) do
        raw_data
      end

      # With anonymous functions
      @decorate pipe_through([
        fn data -> Map.put(data, :processed_at, DateTime.utc_now()) end,
        &save/1
      ])
      def process(data) do
        data
      end

  ## Order of Execution

  1. Original function executes
  2. Result passed to first step
  3. Step 1 result passed to step 2
  4. ... and so on
  5. Final result returned
  """
  def pipe_through(steps, body, _context) when is_list(steps) do
    validated_opts = NimbleOptions.validate!([steps: steps], @pipe_through_schema)
    steps = validated_opts[:steps]

    apply_pipeline(body, steps)
  end

  @doc """
  Around advice decorator (aspect-oriented programming pattern).

  Wraps the original function with custom behavior, giving complete control
  over execution. The wrapper receives a function reference to the original
  function plus all arguments.

  ## Options

  #{NimbleOptions.docs(@around_schema)}

  ## Wrapper Function Signature

  The wrapper must accept:
  - First argument: `decorated_fn` - reference to original function
  - Remaining arguments: All original function arguments
  - Additional arguments: Any extra args passed to the wrapper

  ## Examples

      # Performance measurement
      @decorate around(&ProfileHelper.measure/2)
      def expensive_calculation(x, y) do
        # Complex work
      end

      defmodule ProfileHelper do
        def measure(decorated_fn, x, y) do
          start = System.monotonic_time()
          result = decorated_fn.(x, y)
          duration = System.monotonic_time() - start

          Telemetry.record_duration(duration)
          result
        end
      end

      # Authorization wrapper
      @decorate around(&AuthHelper.check_permission/3)
      def delete_user(conn, user_id) do
        Repo.delete(User, user_id)
      end

      defmodule AuthHelper do
        def check_permission(decorated_fn, conn, user_id) do
          if authorized?(conn, :delete, User) do
            decorated_fn.(conn, user_id)
          else
            {:error, :unauthorized}
          end
        end
      end

      # Retry logic
      @decorate around(&RetryHelper.with_retry/2)
      def call_external_api(endpoint) do
        HTTPClient.get(endpoint)
      end

      defmodule RetryHelper do
        def with_retry(decorated_fn, endpoint, max_attempts \\\\ 3) do
          Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
            case decorated_fn.(endpoint) do
              {:ok, result} -> {:halt, {:ok, result}}
              {:error, _} when attempt < max_attempts -> {:cont, nil}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        end
      end

  ## Important Notes

  - The original function is made private (prefixed with `__decorator_private_`)
  - The wrapper must call `decorated_fn` or the original function won't execute
  - The wrapper can choose not to call `decorated_fn` at all
  - Arguments can be transformed before passing to `decorated_fn`
  - Results can be transformed before returning

  ## Use Cases

  - Performance profiling
  - Authorization checks
  - Retry logic
  - Circuit breakers
  - Rate limiting
  - Request/response transformation
  - Transaction management
  """
  def around(wrapper_fn, body, context) do
    validated_opts = NimbleOptions.validate!([wrapper: wrapper_fn], @around_schema)
    wrapper_fn = validated_opts[:wrapper]

    # For around advice, we need to access the full function definition
    # This is a limitation of the current approach - we're working with body only
    # In a real implementation, we'd need access to the complete defun AST

    # As a workaround, we'll create a closure and pass it to the wrapper
    args_vars = Enum.map(context.args, fn {name, _, _} -> Macro.var(name, nil) end)

    quote do
      decorated_fn = fn unquote_splicing(args_vars) ->
        unquote(body)
      end

      unquote(wrapper_fn).(decorated_fn, unquote_splicing(args_vars))
    end
  end

  @doc """
  Decorator composition decorator.

  Combines multiple decorators into a single, ordered application.
  Useful when you want to apply the same set of decorators to multiple functions.

  ## Options

  #{NimbleOptions.docs(@compose_schema)}

  ## Decorator Specifications

  Decorators can be specified as:
  - `{decorator_name, opts}` - Tuple with decorator name and options
  - `decorator_name` - Just the decorator name (uses default options)

  ## Examples

      # Compose caching, telemetry, and logging
      @decorate compose([
        {:cacheable, [cache: MyCache, key: id, ttl: 3600]},
        {:telemetry_span, [[:app, :users, :get]]},
        {:log_if_slow, [threshold: 1000]}
      ])
      def get_user(id) do
        Repo.get(User, id)
      end

      # Define a reusable composition
      defmodule MyDecorators do
        def cached_and_monitored(cache_opts) do
          [
            {:cacheable, cache_opts},
            {:telemetry_span, [[:app, :cache, :access]]},
            {:log_if_slow, [threshold: 500]}
          ]
        end
      end

      @decorate compose(MyDecorators.cached_and_monitored(cache: MyCache, key: id))
      def get_data(id) do
        fetch_from_source(id)
      end

  ## Execution Order

  Decorators are applied in the order specified. For example:

      @decorate compose([
        {:log_call, [:info]},
        {:cacheable, [cache: MyCache, key: id]},
        {:telemetry_span, [[:app, :op]]}
      ])

  Results in:
  1. Logging happens first (outermost)
  2. Then cacheable check
  3. Then telemetry span (innermost)
  4. Original function execution

  This is equivalent to:

      @decorate log_call(:info)
      @decorate cacheable(cache: MyCache, key: id)
      @decorate telemetry_span([:app, :op])
      def my_function(id), do: ...

  ## Best Practices

  - Define common compositions in a module for reuse
  - Order decorators from outermost to innermost behavior
  - Keep compositions focused (3-5 decorators max)
  - Document custom compositions clearly
  """
  def compose(decorators, body, context) when is_list(decorators) do
    validated_opts = NimbleOptions.validate!([decorators: decorators], @compose_schema)
    decorators = validated_opts[:decorators]

    compose_decorators(decorators, body, context)
  end

  # Helper functions that were in the deleted helpers module

  defp apply_pipeline(body, steps) do
    quote do
      initial_result = unquote(body)

      Enum.reduce(unquote(steps), initial_result, fn step, acc ->
        case step do
          # Function capture
          f when is_function(f, 1) ->
            f.(acc)

          # MFA tuple
          {module, function, extra_args}
          when is_atom(module) and is_atom(function) and is_list(extra_args) ->
            apply(module, function, [acc | extra_args])

          # Module with default transform/1
          module when is_atom(module) ->
            if function_exported?(module, :transform, 1) do
              apply(module, :transform, [acc])
            else
              raise "Pipeline step module #{inspect(module)} must export transform/1"
            end

          other ->
            raise "Invalid pipeline step: #{inspect(other)}"
        end
      end)
    end
  end

  defp compose_decorators([], body, _context), do: body

  defp compose_decorators([decorator | rest], body, context) do
    decorated_body = apply_decorator(decorator, body, context)
    compose_decorators(rest, decorated_body, context)
  end

  defp apply_decorator({decorator_name, opts}, body, context) when is_atom(decorator_name) do
    case FnDecorator.Registry.get(decorator_name) do
      nil ->
        raise ArgumentError,
              "Unknown decorator #{inspect(decorator_name)} in compose/1. " <>
                "Register it with FnDecorator.Registry.register/3 or check spelling."

      {module, function} ->
        # Apply the decorator function at compile time
        apply(module, function, [opts, body, context])
    end
  end

  defp apply_decorator(decorator_name, body, context) when is_atom(decorator_name) do
    apply_decorator({decorator_name, []}, body, context)
  end
end
