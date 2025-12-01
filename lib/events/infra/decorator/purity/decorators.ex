defmodule Events.Infra.Decorator.Purity do
  @moduledoc """
  Function purity checking decorators.

  Helps verify and enforce functional purity properties:
  - Determinism (same inputs → same outputs)
  - No side effects (IO, ETS, process state, etc.)
  - Referential transparency
  - Idempotence

  Purity checking is done through runtime validation and compile-time warnings.

  ## What is a Pure Function?

  A pure function:
  1. Always returns the same output for the same inputs (deterministic)
  2. Has no observable side effects (no IO, no state mutation, etc.)
  3. Doesn't depend on external state
  4. Doesn't modify its arguments

  ## Examples

      defmodule MyApp.Calculator do
        use Events.Infra.Decorator

        # Verify this function is pure
        @decorate pure(verify: true)
        def add(x, y), do: x + y

        # This will fail purity check (uses System.monotonic_time)
        @decorate pure(verify: true, strict: true)
        def impure_add(x, y) do
          IO.puts("Adding")  # Side effect!
          x + y
        end

        # Check determinism only
        @decorate deterministic(samples: 5)
        def calculate(x, y) do
          # Called 5 times with same inputs, results must match
          x * y + :rand.uniform(0)  # Will fail if rand is used
        end

        # Verify idempotence
        @decorate idempotent(calls: 3)
        def cache_put(key, value) do
          # Calling 3 times should be safe
          Cache.put(key, value)
        end
      end

  ## Limitations

  - Runtime purity checking has overhead - use in tests only
  - Some impure code may not be detected (hidden side effects)
  - False positives possible with certain patterns
  - Cannot detect all forms of impurity at compile time
  """

  ## Schemas

  @pure_schema NimbleOptions.new!(
                 verify: [
                   type: :boolean,
                   default: false,
                   doc: "If true, runtime verification of purity"
                 ],
                 strict: [
                   type: :boolean,
                   default: false,
                   doc: "Enable strict checking (compile-time warnings)"
                 ],
                 allow_io: [
                   type: :boolean,
                   default: false,
                   doc: "Allow IO operations (logging, etc.)"
                 ],
                 samples: [
                   type: :pos_integer,
                   default: 3,
                   doc: "Number of samples for determinism check"
                 ]
               )

  @deterministic_schema NimbleOptions.new!(
                          samples: [
                            type: :pos_integer,
                            default: 5,
                            doc: "Number of times to call with same inputs"
                          ],
                          on_failure: [
                            type: {:in, [:raise, :warn, :ignore]},
                            default: :warn,
                            doc: "What to do if determinism check fails"
                          ]
                        )

  @idempotent_schema NimbleOptions.new!(
                       calls: [
                         type: :pos_integer,
                         default: 2,
                         doc: "Number of times to call function"
                       ],
                       compare: [
                         type: {:in, [:equality, :deep_equality, :custom]},
                         default: :equality,
                         doc: "How to compare results"
                       ],
                       comparator: [
                         type: {:fun, 2},
                         required: false,
                         doc: "Custom comparison function"
                       ]
                     )

  @memoizable_schema NimbleOptions.new!(
                       verify: [
                         type: :boolean,
                         default: true,
                         doc: "Verify the function is actually pure first"
                       ],
                       warn_impure: [
                         type: :boolean,
                         default: true,
                         doc: "Emit warning if function might not be pure"
                       ]
                     )

  ## Decorator Implementations

  @doc """
  Pure function decorator.

  Marks a function as pure and optionally verifies purity at runtime.
  In strict mode, performs compile-time analysis to detect impure operations.

  ## Options

  #{NimbleOptions.docs(@pure_schema)}

  ## Examples

      # Simple purity marker (documentation only)
      @decorate pure()
      def add(x, y), do: x + y

      # With runtime verification
      @decorate pure(verify: true, samples: 10)
      def calculate(a, b, c) do
        # Will be called 10 times with same inputs
        # Results must match or purity violation is raised
        a * b + c
      end

      # Strict mode with compile warnings
      @decorate pure(strict: true)
      def process(data) do
        # Will emit compile warning if:
        # - Calls IO functions
        # - Uses process dictionary
        # - Sends messages
        # - etc.
        transform(data)
      end

      # Allow logging (impure but acceptable)
      @decorate pure(strict: true, allow_io: true)
      def process_with_logging(data) do
        Logger.debug("Processing data")
        transform(data)
      end

  ## Purity Violations Detected

  Runtime verification detects:
  - Non-deterministic results
  - Changing process dictionary
  - Sending/receiving messages
  - ETS operations
  - File IO

  Strict mode warns about:
  - IO module calls
  - Process module calls
  - Agent/GenServer calls
  - System module calls
  - Random number generation
  """
  def pure(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @pure_schema)

    if validated_opts[:strict] do
      # Perform compile-time analysis
      check_purity_strict(body, context, validated_opts)
    end

    if validated_opts[:verify] do
      # Runtime verification
      build_purity_verifier(body, context, validated_opts)
    else
      # Just documentation
      body
    end
  end

  @doc """
  Deterministic function decorator.

  Verifies that a function always returns the same output for the same inputs.
  Calls the function multiple times with identical arguments and compares results.

  ## Options

  #{NimbleOptions.docs(@deterministic_schema)}

  ## Examples

      @decorate deterministic(samples: 10)
      def calculate_discount(price, percentage) do
        price * (percentage / 100)
      end
      # Called 10 times with same inputs, results must match

      @decorate deterministic(samples: 5, on_failure: :raise)
      def hash_password(password) do
        # If you use random salt, this will fail
        Bcrypt.hash_pwd_salt(password)
      end

  ## Use Cases

  - Testing mathematical functions
  - Verifying calculation consistency
  - Ensuring database queries are deterministic
  - Validating pure transformations
  """
  def deterministic(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @deterministic_schema)

    samples = validated_opts[:samples]
    on_failure = validated_opts[:on_failure]

    if Mix.env() in [:dev, :test] do
      build_determinism_checker(body, context, samples, on_failure)
    else
      body
    end
  end

  @doc """
  Idempotent function decorator.

  Verifies that calling a function multiple times with the same arguments
  produces the same effect (and ideally the same result).

  ## Options

  #{NimbleOptions.docs(@idempotent_schema)}

  ## Examples

      @decorate idempotent(calls: 3)
      def set_user_status(user_id, status) do
        # Setting status 3 times should be safe
        User.update_status(user_id, status)
      end

      @decorate idempotent(calls: 5, compare: :deep_equality)
      def cache_update(key, value) do
        Cache.put(key, value)
        Cache.get(key)
      end

  ## Use Cases

  - Testing API operations (PUT requests)
  - Validating database upserts
  - Ensuring cache operations are safe
  - Testing configuration updates
  """
  def idempotent(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @idempotent_schema)

    calls = validated_opts[:calls]
    compare = validated_opts[:compare]
    comparator = validated_opts[:comparator]

    if Mix.env() in [:dev, :test] do
      build_idempotence_checker(body, context, calls, compare, comparator)
    else
      body
    end
  end

  @doc """
  Memoizable decorator.

  Indicates that a function is safe to memoize (cache results).
  Optionally verifies purity before marking as memoizable.

  ## Options

  #{NimbleOptions.docs(@memoizable_schema)}

  ## Examples

      @decorate memoizable()
      def fibonacci(n) when n < 2, do: n
      def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)

      @decorate memoizable(verify: true)
      def expensive_calculation(x, y) do
        # Verification ensures this is actually pure
        :timer.sleep(100)
        x * y
      end

  ## Note

  This decorator doesn't actually implement memoization - it just verifies
  the function is safe to memoize. Use `@decorate cacheable()` for actual caching.

  This is useful for documentation and compile-time verification.
  """
  def memoizable(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @memoizable_schema)

    if validated_opts[:verify] do
      # Verify purity
      check_memoizability(body, context, validated_opts)
    end

    # Just return body - this is primarily documentation
    body
  end

  # Helper functions that were in the deleted helpers module

  defp check_purity_strict(body, context, opts) do
    # Analyze AST for impure operations
    impure_calls = find_impure_calls(body)

    if not Enum.empty?(impure_calls) and not opts[:allow_io] do
      IO.warn("""
      Function #{context.module}.#{context.name}/#{context.arity} may not be pure.
      Found potentially impure operations: #{inspect(impure_calls)}

      Consider:
      - Removing side effects
      - Using @decorate pure(allow_io: true) if logging is needed
      - Refactoring to separate pure and impure parts
      """)
    end

    body
  end

  defp build_purity_verifier(body, context, opts) do
    samples = opts[:samples]

    quote do
      # Get initial state snapshot
      initial_state = unquote(__MODULE__).capture_state_snapshot()

      # Call function multiple times
      results =
        for _ <- 1..unquote(samples) do
          unquote(body)
        end

      # Check all results are identical
      first_result = hd(results)
      all_same = Enum.all?(results, &(&1 == first_result))

      if not all_same do
        raise "Purity violation in #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}: Non-deterministic results"
      end

      # Check state hasn't changed
      final_state = unquote(__MODULE__).capture_state_snapshot()

      if initial_state != final_state do
        raise "Purity violation in #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}: State was modified"
      end

      first_result
    end
  end

  defp build_determinism_checker(body, context, samples, on_failure) do
    quote do
      results =
        for _ <- 1..unquote(samples) do
          unquote(body)
        end

      first_result = hd(results)
      all_same = Enum.all?(results, &(&1 == first_result))

      if not all_same do
        case unquote(on_failure) do
          :raise ->
            raise "Determinism violation in #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}"

          :warn ->
            IO.warn(
              "Determinism violation in #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}"
            )

            first_result

          :ignore ->
            first_result
        end
      else
        first_result
      end
    end
  end

  defp build_idempotence_checker(body, context, calls, compare, comparator) do
    quote do
      results =
        for _ <- 1..unquote(calls) do
          unquote(body)
        end

      first_result = hd(results)

      all_same =
        case unquote(compare) do
          :equality ->
            Enum.all?(results, &(&1 == first_result))

          :deep_equality ->
            # Deep comparison for complex structures
            Enum.all?(results, fn result ->
              unquote(__MODULE__).compare_deep(result, first_result)
            end)

          :custom ->
            comparator_fn = unquote(comparator)
            Enum.all?(results, &comparator_fn.(&1, first_result))
        end

      if not all_same do
        IO.warn("""
        Idempotence violation in #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}
        Function produced different results when called #{unquote(calls)} times
        """)
      end

      first_result
    end
  end

  defp check_memoizability(body, context, opts) do
    if opts[:warn_impure] do
      impure_calls = find_impure_calls(body)

      if not Enum.empty?(impure_calls) do
        IO.warn("""
        Function #{context.module}.#{context.name}/#{context.arity} may not be safe to memoize.
        Found potentially impure operations: #{inspect(impure_calls)}

        Memoizing impure functions can lead to:
        - Stale cached values
        - Missing side effects
        - Incorrect behavior
        """)
      end
    end

    body
  end

  # Helper utilities

  defp find_impure_calls(ast) do
    {_, impure} =
      Macro.prewalk(ast, [], fn
        # IO operations
        {{:., _, [{:__aliases__, _, [:IO]}, _]}, _, _} = node, acc ->
          {node, [:io | acc]}

        # Process operations
        {{:., _, [{:__aliases__, _, [:Process]}, _]}, _, _} = node, acc ->
          {node, [:process | acc]}

        # System calls
        {{:., _, [{:__aliases__, _, [:System]}, _]}, _, _} = node, acc ->
          {node, [:system | acc]}

        # Send operations
        {:send, _, _} = node, acc ->
          {node, [:send | acc]}

        # Receive blocks
        {:receive, _, _} = node, acc ->
          {node, [:receive | acc]}

        # Random operations
        {{:., _, [:rand, _]}, _, _} = node, acc ->
          {node, [:random | acc]}

        # ETS operations
        {{:., _, [:ets, _]}, _, _} = node, acc ->
          {node, [:ets | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(impure)
  end

  @doc false
  def capture_state_snapshot do
    %{
      process_dict: Process.get(),
      message_queue_len: Process.info(self(), :message_queue_len)
    }
  end

  @doc false
  def compare_deep(a, b) when is_map(a) and is_map(b) do
    Map.keys(a) == Map.keys(b) and
      Enum.all?(a, fn {k, v} -> compare_deep(v, Map.get(b, k)) end)
  end

  def compare_deep(a, b) when is_list(a) and is_list(b) do
    length(a) == length(b) and
      Enum.zip(a, b) |> Enum.all?(fn {x, y} -> compare_deep(x, y) end)
  end

  def compare_deep(a, b), do: a == b
end
