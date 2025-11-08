defmodule Events.Decorator.Debugging do
  @moduledoc """
  Debugging decorators for development and troubleshooting.

  Provides powerful debugging tools for inspecting function execution:
  - `@debug` - Use IEx.Helpers.dbg/2 to debug function execution
  - `@inspect` - Inspect arguments, results, or intermediate values
  - `@pry` - Insert breakpoints for interactive debugging
  - `@trace_vars` - Trace variable changes throughout execution

  All decorators use compile-time validation with NimbleOptions and are
  automatically disabled in production environments.

  ## Examples

      defmodule MyApp.Calculator do
        use Events.Decorator

        @decorate inspect(what: :args)
        @decorate debug()
        def calculate(x, y) do
          result = x + y
          result * 2
        end

        @decorate pry(condition: fn result -> result > 100 end)
        def expensive_calc(data) do
          # Will break if result > 100
          do_work(data)
        end
      end

  ## Production Safety

  All debugging decorators automatically check the environment and become
  no-ops in production. You can safely leave them in your code.

  For explicit control, use conditional compilation:

      if Mix.env() in [:dev, :test] do
        @decorate debug()
      end
  """

  import Events.Decorator.Debugging.Helpers

  @type debug_opts :: [label: String.t(), opts: keyword()]
  @type inspect_opts :: [
          what: :args | :result | :both | :all,
          label: String.t(),
          opts: keyword()
        ]
  @type pry_opts :: [
          condition: (any() -> boolean()) | boolean(),
          before: boolean(),
          after: boolean()
        ]

  ## Schemas

  @debug_schema NimbleOptions.new!([
    label: [
      type: :string,
      required: false,
      doc: "Custom label for debug output"
    ],
    opts: [
      type: :keyword_list,
      default: [],
      doc: "Options to pass to dbg/2"
    ]
  ])

  @inspect_schema NimbleOptions.new!([
    what: [
      type: {:in, [:args, :result, :both, :all]},
      default: :both,
      doc: "What to inspect: :args (before), :result (after), :both, or :all (step-by-step)"
    ],
    label: [
      type: :string,
      required: false,
      doc: "Custom label for inspect output"
    ],
    opts: [
      type: :keyword_list,
      default: [],
      doc: "Options for inspect/2 (e.g., limit, pretty, width)"
    ]
  ])

  @pry_schema NimbleOptions.new!([
    condition: [
      type: {:or, [{:fun, 1}, :boolean]},
      default: true,
      doc: "Condition function or boolean - pry only if true"
    ],
    before: [
      type: :boolean,
      default: false,
      doc: "If true, pry before function execution"
    ],
    after: [
      type: :boolean,
      default: true,
      doc: "If true, pry after function execution"
    ]
  ])

  @trace_vars_schema NimbleOptions.new!([
    vars: [
      type: {:list, :atom},
      required: true,
      doc: "List of variable names to trace"
    ]
  ])

  ## Decorator Implementations

  @doc """
  Debug decorator using Elixir 1.14+ dbg/2.

  Wraps function execution with dbg/2, providing detailed execution traces
  including intermediate values, pipe chains, and pattern matches.

  Automatically disabled in production (returns normal function body).

  ## Options

  #{NimbleOptions.docs(@debug_schema)}

  ## Examples

      # Basic debugging
      @decorate debug()
      def calculate(x, y) do
        x
        |> add(y)
        |> multiply(2)
      end

      # With custom label
      @decorate debug(label: "User Creation")
      def create_user(attrs) do
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()
      end
  """
  @spec debug(debug_opts(), Macro.t(), map()) :: Macro.t()
  def debug(opts, body, context) when is_list(opts) do
    opts
    |> NimbleOptions.validate!(@debug_schema)
    |> build_debug_wrapper(body, context)
  end

  @doc """
  Inspect decorator for examining function arguments and results.

  Provides detailed inspection of function inputs, outputs, or both,
  using IO.inspect/2 with customizable options.

  ## Options

  #{NimbleOptions.docs(@inspect_schema)}

  ## Examples

      # Inspect arguments before execution
      @decorate inspect(what: :args)
      def process_user(user, attrs) do
        update_user(user, attrs)
      end

      # Inspect result after execution
      @decorate inspect(what: :result, label: "Query Result")
      def get_users do
        Repo.all(User)
      end

      # Inspect both with custom formatting
      @decorate inspect(what: :both, opts: [pretty: true, width: 100])
      def transform_data(input) do
        complex_transformation(input)
      end
  """
  @spec inspect(inspect_opts(), Macro.t(), map()) :: Macro.t()
  def inspect(opts, body, context) when is_list(opts) do
    opts
    |> NimbleOptions.validate!(@inspect_schema)
    |> build_inspect_wrapper(body, context)
  end

  @doc """
  Pry decorator for interactive debugging with IEx.pry.

  Inserts breakpoints that drop you into IEx for interactive debugging.
  Supports conditional breakpoints based on function results.

  Automatically disabled in production and non-interactive environments.

  ## Options

  #{NimbleOptions.docs(@pry_schema)}

  ## Examples

      # Always break after function execution
      @decorate pry()
      def buggy_function(data) do
        result = do_something(data)
        result
      end

      # Conditional pry - only break on errors
      @decorate pry(condition: fn result -> match?({:error, _}, result) end)
      def process_payment(payment) do
        PaymentGateway.charge(payment)
      end

      # Pry before execution
      @decorate pry(before: true, after: false)
      def initialize_system(config) do
        setup(config)
      end
  """
  @spec pry(pry_opts(), Macro.t(), map()) :: Macro.t()
  def pry(opts, body, context) when is_list(opts) do
    opts
    |> NimbleOptions.validate!(@pry_schema)
    |> build_pry_wrapper(body, context)
  end

  @doc """
  Variable tracing decorator for tracking variable changes.

  Emits a compile-time warning suggesting where to add trace points for
  the specified variables. This is a documentation/reminder decorator.

  ## Options

  #{NimbleOptions.docs(@trace_vars_schema)}

  ## Examples

      @decorate trace_vars(vars: [:total, :count, :average])
      def compute_statistics(numbers) do
        total = Enum.sum(numbers)
        count = length(numbers)
        average = total / count
        {total, count, average}
      end

  ## Note

  This decorator suggests adding IO.inspect/2 calls for the specified variables.
  For automatic tracing, use `@decorate inspect(what: :all)` instead.
  """
  @spec trace_vars(keyword(), Macro.t(), map()) :: Macro.t()
  def trace_vars(opts, body, context) when is_list(opts) do
    opts
    |> NimbleOptions.validate!(@trace_vars_schema)
    |> emit_trace_vars_warning(context)

    body
  end

  ## Private Helpers

  defp build_debug_wrapper(validated_opts, body, context) do
    if enabled?() do
      label = validated_opts[:label] || build_function_label(context)
      dbg_opts = validated_opts[:opts]

      quote do
        require IEx

        IO.puts("\n[DEBUG] #{unquote(label)}")

        result =
          unquote(body)
          |> IEx.Helpers.dbg(unquote(dbg_opts))

        IO.puts("[DEBUG] Completed\n")
        result
      end
    else
      body
    end
  end

  defp build_inspect_wrapper(validated_opts, body, context) do
    what = validated_opts[:what]
    label = validated_opts[:label] || build_function_label(context)
    inspect_opts = validated_opts[:opts]

    case what do
      :args -> inspect_args(body, context, label, inspect_opts)
      :result -> inspect_result(body, label, inspect_opts)
      :both -> inspect_both(body, context, label, inspect_opts)
      :all -> build_debug_wrapper([label: label, opts: inspect_opts], body, context)
    end
  end

  defp build_pry_wrapper(validated_opts, body, context) do
    if enabled?() do
      condition = validated_opts[:condition]
      before? = validated_opts[:before]
      after? = validated_opts[:after]

      build_pry(body, context, condition, before?, after?)
    else
      body
    end
  end

  defp emit_trace_vars_warning(validated_opts, context) do
    vars = validated_opts[:vars]

    suggestion =
      vars
      |> Enum.map_join("\n", fn var ->
        "  IO.inspect(#{var}, label: \"#{var}\")"
      end)

    IO.warn("""
    @trace_vars decorator applied to #{context.module}.#{context.name}/#{context.arity}

    Tracing variables: #{inspect(vars)}

    Add IO.inspect/2 calls in your function body to trace these variables:

    #{suggestion}

    Or use @decorate inspect(what: :all) for automatic tracing.
    """)
  end

  defp build_function_label(context) do
    "#{context.module}.#{context.name}/#{context.arity}"
  end

  defp enabled? do
    Mix.env() in [:dev, :test]
  end
end
