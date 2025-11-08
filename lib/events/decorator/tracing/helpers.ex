defmodule Events.Decorator.Tracing.Helpers do
  @moduledoc """
  Shared utilities for tracing decorators.

  Provides helpers for capturing and formatting function call traces.
  """

  @doc """
  Builds a function call tracer.

  Uses process dictionary to track call stack and format output.
  """
  def build_call_tracer(body, context, opts) do
    _depth = opts[:depth]
    filter = opts[:filter]
    exclude = opts[:exclude]
    format = opts[:format]

    function_label = "#{context.module}.#{context.name}/#{context.arity}"

    quote do
      # Initialize tracer state
      Process.put(:__trace_calls__, [])
      Process.put(:__trace_depth__, 0)

      IO.puts("\n[TRACE CALLS] Starting: #{unquote(function_label)}")
      start_time = System.monotonic_time()

      try do
        # Enable process tracing
        :erlang.trace(self(), true, [:call, :timestamp])

        # Set trace patterns for modules we care about
        unquote(setup_trace_patterns(filter, exclude))

        result = unquote(body)

        # Disable tracing
        :erlang.trace(self(), false, [:call])

        result
      after
        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        # Print trace results
        traces = Process.get(:__trace_calls__, [])
        unquote(print_traces(format, function_label))

        IO.puts("[TRACE CALLS] Completed in #{duration_ms}ms\n")

        # Cleanup
        Process.delete(:__trace_calls__)
        Process.delete(:__trace_depth__)
      end
    end
  end

  @doc """
  Builds a module usage tracer.

  Simpler approach - wraps body and analyzes which modules were loaded/called.
  """
  def build_module_tracer(body, context, opts) do
    filter = opts[:filter]
    unique? = opts[:unique]
    exclude_stdlib? = opts[:exclude_stdlib]

    function_label = "#{context.module}.#{context.name}/#{context.arity}"

    quote do
      # Capture currently loaded modules
      modules_before = :code.all_loaded() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      result = unquote(body)

      # See what new modules were loaded
      modules_after = :code.all_loaded() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      new_modules = MapSet.difference(modules_after, modules_before)

      # Filter modules
      filtered_modules =
        new_modules
        |> Enum.to_list()
        |> unquote(apply_module_filters(filter, exclude_stdlib?))
        |> then(fn mods -> if unquote(unique?), do: Enum.uniq(mods), else: mods end)
        |> Enum.sort()

      if Enum.any?(filtered_modules) do
        IO.puts("\n[MODULES] #{unquote(function_label)} called:")

        Enum.each(filtered_modules, fn mod ->
          IO.puts("  - #{inspect(mod)}")
        end)

        IO.puts("")
      end

      result
    end
  end

  @doc """
  Builds a dependency tracer.

  Analyzes which external libraries are called during execution.
  """
  def build_dependency_tracer(body, context, opts) do
    type = opts[:type]
    format = opts[:format]

    function_label = "#{context.module}.#{context.name}/#{context.arity}"

    quote do
      # Get application dependencies
      app = unquote(context.module) |> Application.get_application()
      deps = if app, do: Application.spec(app, :applications) || [], else: []

      # Track module usage
      modules_before = :code.all_loaded() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      result = unquote(body)

      modules_after = :code.all_loaded() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      new_modules = MapSet.difference(modules_after, modules_before)

      # Categorize by dependency
      dependencies =
        new_modules
        |> Enum.to_list()
        |> Enum.map(fn mod ->
          case Application.get_application(mod) do
            nil -> nil
            app -> {app, mod}
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      # Filter by type
      filtered_deps =
        case unquote(type) do
          :all -> dependencies
          :external -> Map.drop(dependencies, [:kernel, :stdlib, :elixir])
          :internal -> Map.take(dependencies, deps)
        end

      if map_size(filtered_deps) > 0 do
        IO.puts("\n[DEPENDENCIES] #{unquote(function_label)}")

        Enum.each(filtered_deps, fn {app, modules} ->
          IO.puts("  #{app} (#{length(modules)} modules)")

          if unquote(format) == :detailed do
            Enum.each(modules, fn mod ->
              IO.puts("    - #{inspect(mod)}")
            end)
          end
        end)

        IO.puts("")
      end

      result
    end
  end

  ## Private Helpers

  defp setup_trace_patterns(_filter, _exclude) do
    quote do
      # This is a placeholder - actual implementation would use :dbg
      # or compile-time AST analysis
      :ok
    end
  end

  defp print_traces(format, _label) do
    quote do
      traces = Process.get(:__trace_calls__, [])

      case unquote(format) do
        :simple ->
          Enum.each(Enum.reverse(traces), fn {module, function, arity} ->
            IO.puts("  #{inspect(module)}.#{function}/#{arity}")
          end)

        :tree ->
          unquote(print_tree_traces(quote(do: traces)))

        :detailed ->
          unquote(print_detailed_traces(quote(do: traces)))
      end
    end
  end

  defp print_tree_traces(traces_var) do
    quote do
      traces = unquote(traces_var)

      Enum.each(Enum.reverse(traces), fn
        {module, function, arity, depth} ->
          indent = String.duplicate("  ", depth)
          IO.puts("#{indent}↳ #{inspect(module)}.#{function}/#{arity}")

        {module, function, arity} ->
          IO.puts("  ↳ #{inspect(module)}.#{function}/#{arity}")
      end)
    end
  end

  defp print_detailed_traces(traces_var) do
    quote do
      traces = unquote(traces_var)

      Enum.each(Enum.reverse(traces), fn
        {module, function, arity, depth, duration} ->
          indent = String.duplicate("  ", depth)
          IO.puts("#{indent}↳ #{inspect(module)}.#{function}/#{arity} (#{duration}ms)")

        {module, function, arity, depth} ->
          indent = String.duplicate("  ", depth)
          IO.puts("#{indent}↳ #{inspect(module)}.#{function}/#{arity}")

        {module, function, arity} ->
          IO.puts("  ↳ #{inspect(module)}.#{function}/#{arity}")
      end)
    end
  end

  defp apply_module_filters(filter, exclude_stdlib?) do
    quote do
      fn modules ->
        modules
        |> then(fn mods ->
          if unquote(exclude_stdlib?) do
            Enum.reject(mods, fn mod ->
              mod_str = to_string(mod)

              String.starts_with?(mod_str, "Elixir.Kernel") ||
                String.starts_with?(mod_str, "Elixir.Enum") ||
                String.starts_with?(mod_str, "Elixir.String") ||
                String.starts_with?(mod_str, "Elixir.List") ||
                String.starts_with?(mod_str, "Elixir.Map")
            end)
          else
            mods
          end
        end)
        |> then(fn mods ->
          case unquote(filter) do
            nil ->
              mods

            %Regex{} = regex ->
              Enum.filter(mods, fn mod ->
                Regex.match?(regex, to_string(mod))
              end)

            module when is_atom(module) ->
              prefix = to_string(module)

              Enum.filter(mods, fn mod ->
                String.starts_with?(to_string(mod), prefix)
              end)
          end
        end)
      end
    end
  end

  @doc """
  Formats call stack for display.
  """
  def format_call_stack(stack, format \\ :tree) do
    case format do
      :tree ->
        Enum.map_join(stack, "\n", fn {depth, mfa} ->
          indent = String.duplicate("  ", depth)
          "#{indent}↳ #{format_mfa(mfa)}"
        end)

      :simple ->
        Enum.map_join(stack, "\n", fn {_depth, mfa} ->
          "  #{format_mfa(mfa)}"
        end)

      :detailed ->
        Enum.map_join(stack, "\n", fn {depth, mfa, timing} ->
          indent = String.duplicate("  ", depth)
          "#{indent}↳ #{format_mfa(mfa)} (#{timing}ms)"
        end)
    end
  end

  defp format_mfa({module, function, arity}) do
    "#{inspect(module)}.#{function}/#{arity}"
  end
end
