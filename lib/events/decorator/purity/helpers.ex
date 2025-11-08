defmodule Events.Decorator.Purity.Helpers do
  @moduledoc """
  Shared utilities for purity checking decorators.
  """

  @doc """
  Checks function purity using strict compile-time analysis.

  Analyzes the AST for impure operations and emits warnings.
  """
  def check_purity_strict(body, context, opts) do
    allow_io? = opts[:allow_io]

    # Analyze AST for impure operations
    impure_calls = find_impure_calls(body, allow_io?)

    if Enum.any?(impure_calls) do
      warning = """
      Function #{context.module}.#{context.name}/#{context.arity} marked as @pure but contains potentially impure operations:

      #{Enum.map_join(impure_calls, "\n", fn {type, details} ->
        "  - #{type}: #{details}"
      end)}

      Pure functions should not:
      - Perform IO operations
      - Use process dictionary
      - Send/receive messages
      - Access ETS
      - Use System functions
      - Generate random numbers
      """

      IO.warn(warning, Macro.Env.stacktrace(__ENV__))
    end

    body
  end

  @doc """
  Finds impure operations in AST.
  """
  def find_impure_calls(ast, allow_io?) do
    impure = []

    # Check for IO operations
    impure = if !allow_io? && has_io_calls?(ast) do
      [{:io, "IO module calls detected"} | impure]
    else
      impure
    end

    # Check for process operations
    impure = if has_process_calls?(ast) do
      [{:process, "Process module calls detected"} | impure]
    else
      impure
    end

    # Check for ETS operations
    impure = if has_ets_calls?(ast) do
      [{:ets, "ETS operations detected"} | impure]
    else
      impure
    end

    # Check for System calls
    impure = if has_system_calls?(ast) do
      [{:system, "System module calls detected"} | impure]
    else
      impure
    end

    # Check for random number generation
    impure = if has_random_calls?(ast) do
      [{:random, "Random number generation detected"} | impure]
    else
      impure
    end

    # Check for Agent/GenServer calls
    impure = if has_stateful_calls?(ast) do
      [{:stateful, "Stateful process calls detected (Agent, GenServer, etc.)"} | impure]
    else
      impure
    end

    impure
  end

  defp has_io_calls?(ast) do
    has_call?(ast, IO) || has_call?(ast, File)
  end

  defp has_process_calls?(ast) do
    has_call?(ast, Process) || has_call?(ast, :erlang, :send) || has_call?(ast, Kernel, :send)
  end

  defp has_ets_calls?(ast) do
    has_call?(ast, :ets)
  end

  defp has_system_calls?(ast) do
    has_call?(ast, System)
  end

  defp has_random_calls?(ast) do
    has_call?(ast, :rand) || has_call?(ast, Enum, :random)
  end

  defp has_stateful_calls?(ast) do
    has_call?(ast, Agent) || has_call?(ast, GenServer) || has_call?(ast, Task)
  end

  defp has_call?(ast, module) when is_atom(module) do
    {_ast, found?} = Macro.prewalk(ast, false, fn
      {{:., _, [{:__aliases__, _, aliases}, _fun]}, _, _args}, _acc ->
        module_name = Module.concat(aliases)
        {ast, module_name == module}

      node, acc ->
        {node, acc}
    end)

    found?
  end

  defp has_call?(ast, module, function) when is_atom(module) and is_atom(function) do
    {_ast, found?} = Macro.prewalk(ast, false, fn
      {{:., _, [{:__aliases__, _, aliases}, fun]}, _, _args}, _acc ->
        module_name = Module.concat(aliases)
        {ast, module_name == module && fun == function}

      {{:., _, [^module, ^function]}, _, _args}, _acc ->
        {ast, true}

      node, acc ->
        {node, acc}
    end)

    found?
  end

  @doc """
  Builds runtime purity verifier.

  Calls function multiple times and checks for determinism.
  """
  def build_purity_verifier(body, context, opts) do
    samples = opts[:samples]

    quote do
      # Store initial process state
      initial_pdict = Process.get()
      initial_messages = Process.info(self(), :messages)

      # Call function multiple times
      results = for _ <- 1..unquote(samples) do
        unquote(body)
      end

      # Check determinism (all results should be equal)
      first_result = hd(results)
      all_equal? = Enum.all?(results, fn r -> r == first_result end)

      if !all_equal? do
        raise """
        Purity violation in #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}

        Function returned different results with identical inputs:
        #{inspect(results, pretty: true)}

        This violates the determinism requirement for pure functions.
        """
      end

      # Check process state unchanged
      final_pdict = Process.get()
      final_messages = Process.info(self(), :messages)

      if initial_pdict != final_pdict do
        IO.warn("""
        Purity warning: Process dictionary was modified by #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}
        """)
      end

      if initial_messages != final_messages do
        IO.warn("""
        Purity warning: Process mailbox was modified by #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}
        """)
      end

      # Return first result
      first_result
    end
  end

  @doc """
  Builds determinism checker.
  """
  def build_determinism_checker(body, context, samples, on_failure) do
    quote do
      # Call function multiple times
      results = for _ <- 1..unquote(samples) do
        unquote(body)
      end

      # Check all results are equal
      first_result = hd(results)
      all_equal? = Enum.all?(results, fn r -> r == first_result end)

      if !all_equal? do
        message = """
        Determinism check failed for #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}

        Expected all #{unquote(samples)} calls to return the same result, but got:
        #{Enum.map_join(Enum.with_index(results), "\n", fn {r, i} ->
          "  Call #{i + 1}: #{inspect(r)}"
        end)}
        """

        case unquote(on_failure) do
          :raise -> raise message
          :warn -> IO.warn(message)
          :ignore -> :ok
        end
      end

      first_result
    end
  end

  @doc """
  Builds idempotence checker.
  """
  def build_idempotence_checker(body, context, calls, compare, comparator) do
    quote do
      # Call function multiple times
      results = for _ <- 1..unquote(calls) do
        unquote(body)
      end

      # Compare results based on comparison strategy
      first_result = hd(results)

      all_equal? = case unquote(compare) do
        :equality ->
          Enum.all?(results, fn r -> r == first_result end)

        :deep_equality ->
          # Use inspect for deep comparison
          first_inspect = inspect(first_result)
          Enum.all?(results, fn r -> inspect(r) == first_inspect end)

        :custom ->
          comparator = unquote(comparator)
          Enum.all?(results, fn r -> comparator.(first_result, r) end)
      end

      if !all_equal? do
        IO.warn("""
        Idempotence check failed for #{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}

        Expected all #{unquote(calls)} calls to produce the same result, but got different results.

        This may indicate the function has side effects that change between calls.
        """)
      end

      first_result
    end
  end

  @doc """
  Checks if function is safe to memoize.
  """
  def check_memoizability(body, context, opts) do
    # Check for impure operations
    impure_calls = find_impure_calls(body, false)

    if Enum.any?(impure_calls) && opts[:warn_impure] do
      IO.warn("""
      Function #{context.module}.#{context.name}/#{context.arity} marked as @memoizable
      but contains potentially impure operations:

      #{Enum.map_join(impure_calls, "\n", fn {type, details} ->
        "  - #{type}: #{details}"
      end)}

      Memoizing impure functions can lead to incorrect behavior.
      Consider removing @memoizable or making the function pure.
      """)
    end

    body
  end
end
