defmodule Events.Decorator.Tracing do
  @moduledoc """
  Function call tracing decorators for understanding execution flow.

  Provides decorators for tracking:
  - Which modules/functions are called during execution
  - Call hierarchy and depth
  - Execution paths through the codebase
  - External dependencies and side effects

  ## Examples

      defmodule MyApp.OrderProcessor do
        use Events.Decorator

        @decorate trace_calls(depth: 3, filter: ~r/MyApp/)
        def process_order(order) do
          # Will trace all MyApp.* function calls up to 3 levels deep
          validate_order(order)
          |> charge_payment()
          |> fulfill_order()
        end

        @decorate trace_modules()
        def complex_workflow(data) do
          # Will show all modules called during execution
          MyApp.Parser.parse(data)
          |> MyApp.Validator.validate()
          |> MyApp.Processor.process()
          |> MyApp.Notifier.notify()
        end
      end

  ## Performance Note

  Tracing adds significant overhead and should only be used in development/debugging.
  """

  import Events.Decorator.Tracing.Helpers

  ## Schemas

  @trace_calls_schema NimbleOptions.new!([
    depth: [
      type: :pos_integer,
      default: 1,
      doc: "Maximum call depth to trace"
    ],
    filter: [
      type: {:or, [:atom, {:custom, __MODULE__, :validate_regex, []}]},
      required: false,
      doc: "Regex or module to filter traced calls"
    ],
    exclude: [
      type: {:list, :atom},
      default: [Kernel, Enum, String, List, Map],
      doc: "Modules to exclude from tracing"
    ],
    format: [
      type: {:in, [:simple, :tree, :detailed]},
      default: :tree,
      doc: "Output format for trace"
    ]
  ])

  @trace_modules_schema NimbleOptions.new!([
    filter: [
      type: {:or, [:atom, {:custom, __MODULE__, :validate_regex, []}]},
      required: false,
      doc: "Regex or module prefix to filter"
    ],
    unique: [
      type: :boolean,
      default: true,
      doc: "Show only unique modules (no duplicates)"
    ],
    exclude_stdlib: [
      type: :boolean,
      default: true,
      doc: "Exclude Elixir standard library modules"
    ]
  ])

  @trace_dependencies_schema NimbleOptions.new!([
    type: [
      type: {:in, [:all, :external, :internal]},
      default: :all,
      doc: "Which dependencies to trace"
    ],
    format: [
      type: {:in, [:list, :tree, :graph]},
      default: :list,
      doc: "Output format"
    ]
  ])

  ## Validator for regex

  @doc false
  def validate_regex(value) do
    cond do
      is_struct(value, Regex) -> {:ok, value}
      is_binary(value) -> {:ok, Regex.compile!(value)}
      true -> {:error, "must be a regex or string"}
    end
  end

  ## Decorator Implementations

  @doc """
  Traces all function calls during execution.

  Uses Erlang's :dbg or process tracing to capture function calls,
  showing the call hierarchy and execution flow.

  ## Options

  #{NimbleOptions.docs(@trace_calls_schema)}

  ## Examples

      # Trace all calls with default depth
      @decorate trace_calls()
      def calculate(x, y) do
        helper_1(x)
        |> helper_2(y)
        |> helper_3()
      end

      # Output:
      # [TRACE] MyApp.Calculator.calculate/2
      #   ↳ MyApp.Calculator.helper_1/1
      #   ↳ MyApp.Calculator.helper_2/2
      #   ↳ MyApp.Calculator.helper_3/1

      # Trace with depth limit and filter
      @decorate trace_calls(depth: 2, filter: ~r/MyApp\./)
      def process_user(user) do
        # Only traces MyApp.* calls, max 2 levels deep
        fetch_permissions(user)
        validate_access(user)
        perform_action(user)
      end

      # Detailed format with timing
      @decorate trace_calls(format: :detailed)
      def expensive_operation(data) do
        step_1(data)
        step_2(data)
        step_3(data)
      end

      # Output:
      # [TRACE] MyApp.Worker.expensive_operation/1
      #   ↳ MyApp.Worker.step_1/1 (2.3ms)
      #   ↳ MyApp.Worker.step_2/1 (15.7ms)
      #   ↳ MyApp.Worker.step_3/1 (8.1ms)
      # Total: 26.1ms

  ## Important

  - Only enabled in :dev and :test environments
  - Adds significant performance overhead
  - Not suitable for production use
  - May miss dynamically dispatched calls (apply/3, etc.)
  """
  def trace_calls(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @trace_calls_schema)

    if Mix.env() in [:dev, :test] do
      build_call_tracer(body, context, validated_opts)
    else
      body
    end
  end

  @doc """
  Traces all modules called during function execution.

  Simpler than trace_calls - just shows which modules are used,
  without detailed call information.

  ## Options

  #{NimbleOptions.docs(@trace_modules_schema)}

  ## Examples

      @decorate trace_modules()
      def process_request(request) do
        Parser.parse(request)
        |> Validator.validate()
        |> Handler.handle()
      end

      # Output:
      # [MODULES] MyApp.RequestProcessor.process_request/1 called:
      #   - MyApp.Parser
      #   - MyApp.Validator
      #   - MyApp.Handler

      # With filtering
      @decorate trace_modules(filter: ~r/^MyApp\.Services/, unique: false)
      def complex_flow(data) do
        # Shows all MyApp.Services.* calls, including duplicates
        process(data)
      end

  ## Use Cases

  - Understanding module dependencies
  - Finding hidden dependencies
  - Refactoring assistance
  - Documentation generation
  """
  def trace_modules(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @trace_modules_schema)

    if Mix.env() in [:dev, :test] do
      build_module_tracer(body, context, validated_opts)
    else
      body
    end
  end

  @doc """
  Traces external dependencies (library calls) during execution.

  Helps understand which external libraries are being used and how often.

  ## Options

  #{NimbleOptions.docs(@trace_dependencies_schema)}

  ## Examples

      @decorate trace_dependencies(type: :external)
      def fetch_and_process_data(url) do
        HTTPoison.get!(url)
        |> Jason.decode!()
        |> process()
      end

      # Output:
      # [DEPENDENCIES] External libraries used:
      #   - HTTPoison (1 call)
      #   - Jason (1 call)

  ## Use Cases

  - Auditing external dependencies
  - Performance analysis
  - Security auditing
  - License compliance checking
  """
  def trace_dependencies(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @trace_dependencies_schema)

    if Mix.env() in [:dev, :test] do
      build_dependency_tracer(body, context, validated_opts)
    else
      body
    end
  end
end
