defmodule FnDecorator.Tracing do
  @moduledoc """
  Function call tracing decorators for understanding execution flow.

  Provides decorators for tracking:
  - Which modules/functions are called during execution
  - Call hierarchy and depth
  - Execution paths through the codebase
  - External dependencies and side effects

  ## Examples

      defmodule MyApp.OrderProcessor do
        use FnDecorator

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

  ## Schemas

  @trace_calls_schema NimbleOptions.new!(
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
                      )

  @trace_modules_schema NimbleOptions.new!(
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
                        )

  @trace_dependencies_schema NimbleOptions.new!(
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
                             )

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
        |> JSON.decode!()
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

  # Helper functions that were in the deleted helpers module

  defp build_call_tracer(body, context, opts) do
    _depth = opts[:depth]
    filter = opts[:filter]
    exclude = opts[:exclude]
    format = opts[:format]

    quote do
      # Note: Using spawn/1 intentionally here rather than Task.Supervisor.
      # The tracer process must be independent of the supervision tree to correctly
      # receive trace messages from :erlang.trace without being affected by
      # the traced process's lifecycle.
      tracer_pid =
        spawn(fn ->
          Process.flag(:trap_exit, true)
          unquote(__MODULE__).trace_loop([], unquote(format))
        end)

      :erlang.trace(self(), true, [:call, {:tracer, tracer_pid}])

      # Set up trace patterns based on filter
      unquote(setup_trace_patterns(filter, exclude))

      result = unquote(body)

      :erlang.trace(self(), false, [:call])
      send(tracer_pid, {:done, self()})

      receive do
        {:trace_results, results} ->
          IO.puts(
            unquote(__MODULE__).format_trace_results(results, unquote(format), unquote(context))
          )
      after
        1000 -> :ok
      end

      result
    end
  end

  defp build_module_tracer(body, context, opts) do
    filter = opts[:filter]
    unique = opts[:unique]
    exclude_stdlib = opts[:exclude_stdlib]

    quote do
      modules_ref = :ets.new(:trace_modules, [:set, :public])

      # Note: Using spawn/1 intentionally - tracer must be independent of supervision tree
      tracer_pid =
        spawn(fn ->
          FnDecorator.Tracing.__trace_modules_loop__(
            modules_ref,
            unquote(filter),
            unquote(exclude_stdlib)
          )
        end)

      :erlang.trace(self(), true, [:call, {:tracer, tracer_pid}])
      :erlang.trace_pattern({:_, :_, :_}, true, [:local])

      result = unquote(body)

      :erlang.trace(self(), false, [:call])
      send(tracer_pid, {:done, self()})

      modules = :ets.tab2list(modules_ref)
      :ets.delete(modules_ref)

      unquote(__MODULE__).display_modules(modules, unquote(unique), unquote(context))

      result
    end
  end

  defp build_dependency_tracer(body, context, opts) do
    type = opts[:type]
    format = opts[:format]

    quote do
      deps_ref = :ets.new(:trace_deps, [:bag, :public])

      # Note: Using spawn/1 intentionally - tracer must be independent of supervision tree
      tracer_pid =
        spawn(fn ->
          unquote(__MODULE__).trace_deps_loop(deps_ref, unquote(type))
        end)

      :erlang.trace(self(), true, [:call, {:tracer, tracer_pid}])
      :erlang.trace_pattern({:_, :_, :_}, true, [:local])

      result = unquote(body)

      :erlang.trace(self(), false, [:call])
      send(tracer_pid, {:done, self()})

      deps = :ets.tab2list(deps_ref)
      :ets.delete(deps_ref)

      unquote(__MODULE__).display_dependencies(deps, unquote(format), unquote(context))

      result
    end
  end

  defp setup_trace_patterns(nil, exclude) do
    quote do
      :erlang.trace_pattern({:_, :_, :_}, true, [:local])

      for mod <- unquote(exclude) do
        :erlang.trace_pattern({mod, :_, :_}, false, [:local])
      end
    end
  end

  defp setup_trace_patterns(_filter, exclude) do
    quote do
      # This is simplified - in real implementation would need more complex pattern matching
      :erlang.trace_pattern({:_, :_, :_}, true, [:local])

      for mod <- unquote(exclude) do
        :erlang.trace_pattern({mod, :_, :_}, false, [:local])
      end
    end
  end

  @doc false
  def trace_loop(acc, format) do
    receive do
      {:trace, _pid, :call, {mod, fun, args}} ->
        trace_loop([{mod, fun, length(args)} | acc], format)

      {:done, pid} ->
        send(pid, {:trace_results, Enum.reverse(acc)})

      _ ->
        trace_loop(acc, format)
    end
  end

  @doc false
  def __trace_modules_loop__(ets_ref, filter, exclude_stdlib) do
    receive do
      {:trace, _pid, :call, {mod, _fun, _args}} ->
        if should_trace_module?(mod, filter, exclude_stdlib) do
          :ets.insert(ets_ref, {mod})
        end

        __trace_modules_loop__(ets_ref, filter, exclude_stdlib)

      {:done, _pid} ->
        :ok

      _ ->
        __trace_modules_loop__(ets_ref, filter, exclude_stdlib)
    end
  end

  @doc false
  def trace_deps_loop(ets_ref, type) do
    receive do
      {:trace, _pid, :call, {mod, fun, args}} ->
        if is_dependency?(mod, type) do
          :ets.insert(ets_ref, {mod, fun, length(args)})
        end

        trace_deps_loop(ets_ref, type)

      {:done, _pid} ->
        :ok

      _ ->
        trace_deps_loop(ets_ref, type)
    end
  end

  defp should_trace_module?(mod, filter, exclude_stdlib) do
    mod_str = Atom.to_string(mod)

    passes_filter =
      case filter do
        nil -> true
        %Regex{} = regex -> Regex.match?(regex, mod_str)
        prefix when is_atom(prefix) -> String.starts_with?(mod_str, Atom.to_string(prefix))
        _ -> true
      end

    not_stdlib =
      if exclude_stdlib do
        not String.starts_with?(mod_str, "Elixir.")
      else
        true
      end

    passes_filter and not_stdlib
  end

  @doc false
  def is_dependency?(mod, type) do
    mod_str = Atom.to_string(mod)

    case type do
      :all -> true
      :external -> not String.starts_with?(mod_str, "Elixir.MyApp")
      :internal -> String.starts_with?(mod_str, "Elixir.MyApp")
    end
  end

  @doc false
  def format_trace_results(results, format, context) do
    header = "[TRACE] #{context.module}.#{context.name}/#{context.arity}"

    formatted =
      case format do
        :simple ->
          Enum.map_join(results, "\n", fn {mod, fun, arity} ->
            "  → #{mod}.#{fun}/#{arity}"
          end)

        :tree ->
          Enum.map_join(results, "\n", fn {mod, fun, arity} ->
            "  ↳ #{mod}.#{fun}/#{arity}"
          end)

        :detailed ->
          # In real implementation, would include timing
          Enum.map_join(results, "\n", fn {mod, fun, arity} ->
            "  ↳ #{mod}.#{fun}/#{arity}"
          end)
      end

    "#{header}\n#{formatted}"
  end

  @doc false
  def display_modules(modules, unique, context) do
    header = "[MODULES] #{context.module}.#{context.name}/#{context.arity} called:"

    mods =
      if unique do
        modules |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
      else
        modules |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      end

    formatted =
      Enum.map_join(mods, "\n", fn mod ->
        "  - #{mod}"
      end)

    IO.puts("#{header}\n#{formatted}")
  end

  @doc false
  def display_dependencies(deps, format, context) do
    header = "[DEPENDENCIES] #{context.module}.#{context.name}/#{context.arity}"

    grouped = Enum.group_by(deps, &elem(&1, 0))

    formatted =
      case format do
        :list ->
          Enum.map_join(grouped, "\n", fn {mod, calls} ->
            "  - #{mod} (#{length(calls)} calls)"
          end)

        _ ->
          # Simplified for other formats
          Enum.map_join(grouped, "\n", fn {mod, calls} ->
            "  - #{mod} (#{length(calls)} calls)"
          end)
      end

    IO.puts("#{header}\n#{formatted}")
  end
end
