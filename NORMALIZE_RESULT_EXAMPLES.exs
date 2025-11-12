#!/usr/bin/env elixir

# Normalize Result Decorator - Interactive Examples
# Run with: elixir NORMALIZE_RESULT_EXAMPLES.exs

# Simulate the decorator functionality
defmodule DecoratorSimulator do
  def normalize_to_result(
        result,
        error_patterns,
        nil_is_error,
        false_is_error,
        error_mapper,
        success_mapper
      ) do
    case result do
      {:ok, value} ->
        if success_mapper do
          {:ok, success_mapper.(value)}
        else
          {:ok, value}
        end

      {:error, reason} ->
        if error_mapper do
          {:error, error_mapper.(reason)}
        else
          {:error, reason}
        end

      nil ->
        if nil_is_error do
          error_value = if error_mapper, do: error_mapper.(:nil_value), else: :nil_value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(nil), else: nil
          {:ok, success_value}
        end

      false ->
        if false_is_error do
          error_value = if error_mapper, do: error_mapper.(:false_value), else: :false_value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(false), else: false
          {:ok, success_value}
        end

      value when is_atom(value) or is_binary(value) ->
        if value in error_patterns do
          error_value = if error_mapper, do: error_mapper.(value), else: value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(value), else: value
          {:ok, success_value}
        end

      value ->
        success_value = if success_mapper, do: success_mapper.(value), else: value
        {:ok, success_value}
    end
  end
end

defmodule NormalizeExamples do
  @moduledoc """
  Interactive examples demonstrating the normalize_result decorator.
  """

  import DecoratorSimulator

  # Helper to print results
  defp print_example(description, function) do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("Example: #{description}")
    IO.puts(String.duplicate("=", 70))

    result = function.()
    IO.puts("Result: #{inspect(result, pretty: true)}")
  end

  def run_examples do
    IO.puts("\n")
    IO.puts(String.duplicate("*", 70))
    IO.puts("NORMALIZE_RESULT DECORATOR - EXAMPLES")
    IO.puts(String.duplicate("*", 70))

    # Example 1: Basic normalization
    print_example("Basic normalization - wrapping raw values", fn ->
      # Returns a struct
      user = %{id: 1, name: "John"}
      normalize_to_result(user, [:error], false, false, nil, nil)
    end)

    # Example 2: nil as error
    print_example("nil_is_error: true", fn ->
      normalize_to_result(nil, [:error], true, false, nil, nil)
    end)

    # Example 3: nil as success
    print_example("nil_is_error: false (default)", fn ->
      normalize_to_result(nil, [:error], false, false, nil, nil)
    end)

    # Example 4: false as error
    print_example("false_is_error: true", fn ->
      normalize_to_result(false, [:error], false, true, nil, nil)
    end)

    # Example 5: Error patterns
    print_example("Error pattern matching - :not_found", fn ->
      normalize_to_result(:not_found, [:not_found, :invalid, :error], false, false, nil, nil)
    end)

    # Example 6: Success pattern (not in error list)
    print_example("Non-error atom - :success", fn ->
      normalize_to_result(:success, [:error, :invalid], false, false, nil, nil)
    end)

    # Example 7: Already result tuple (ok)
    print_example("Already result tuple - {:ok, value}", fn ->
      normalize_to_result({:ok, %{id: 1}}, [:error], false, false, nil, nil)
    end)

    # Example 8: Already result tuple (error)
    print_example("Already result tuple - {:error, reason}", fn ->
      normalize_to_result({:error, :timeout}, [:error], false, false, nil, nil)
    end)

    # Example 9: Error mapper
    print_example("With error_mapper - transforming errors", fn ->
      error_mapper = fn
        :nil_value -> "No user found"
        error -> "Error: #{inspect(error)}"
      end

      normalize_to_result(nil, [:error], true, false, error_mapper, nil)
    end)

    # Example 10: Success mapper
    print_example("With success_mapper - transforming success", fn ->
      success_mapper = fn name -> String.upcase(name) end
      normalize_to_result("john", [:error], false, false, nil, success_mapper)
    end)

    # Example 11: Both mappers with result tuple
    print_example("Both mappers with {:ok, value}", fn ->
      success_mapper = fn user -> Map.put(user, :formatted, true) end

      normalize_to_result(
        {:ok, %{id: 1, name: "John"}},
        [:error],
        false,
        false,
        nil,
        success_mapper
      )
    end)

    # Example 12: String in error patterns
    print_example("String error pattern", fn ->
      normalize_to_result("ERROR", ["ERROR", "FAILED"], false, false, nil, nil)
    end)

    # Example 13: List value (success)
    print_example("List value wrapped in {:ok, list}", fn ->
      normalize_to_result([1, 2, 3], [:error], false, false, nil, nil)
    end)

    # Example 14: Map value (success)
    print_example("Map value wrapped in {:ok, map}", fn ->
      normalize_to_result(%{status: "active", count: 42}, [:error], false, false, nil, nil)
    end)

    # Example 15: Integer value
    print_example("Integer value wrapped in {:ok, int}", fn ->
      normalize_to_result(42, [:error], false, false, nil, nil)
    end)

    # Example 16: Complex error mapper
    print_example("Complex error_mapper with pattern matching", fn ->
      error_mapper = fn
        :nil_value -> %{code: 404, message: "Not found"}
        :timeout -> %{code: 408, message: "Request timeout"}
        error -> %{code: 500, message: inspect(error)}
      end

      normalize_to_result(:timeout, [:timeout, :error], false, false, error_mapper, nil)
    end)

    # Example 17: Complex success mapper
    print_example("Complex success_mapper - extracting fields", fn ->
      user = %{id: 1, name: "John", email: "john@example.com", password: "secret", internal_id: 999}
      success_mapper = fn user -> Map.take(user, [:id, :name, :email]) end

      normalize_to_result(user, [:error], false, false, nil, success_mapper)
    end)

    # Example 18: Real-world scenario - database lookup
    print_example("Real-world: Database lookup (found)", fn ->
      # Simulating Repo.get result
      user = %{id: 123, name: "Alice", email: "alice@example.com"}
      normalize_to_result(user, [:error], true, false, nil, nil)
    end)

    # Example 19: Real-world scenario - database lookup (not found)
    print_example("Real-world: Database lookup (not found)", fn ->
      # Simulating Repo.get returning nil
      error_mapper = fn :nil_value -> "User not found" end
      normalize_to_result(nil, [:error], true, false, error_mapper, nil)
    end)

    # Example 20: Real-world scenario - validation
    print_example("Real-world: Validation result", fn ->
      # Boolean validation result
      is_valid = false
      error_mapper = fn :false_value -> "Email validation failed" end
      normalize_to_result(is_valid, [:error], false, true, error_mapper, nil)
    end)

    IO.puts("\n" <> String.duplicate("*", 70))
    IO.puts("Examples completed!")
    IO.puts(String.duplicate("*", 70) <> "\n")
  end
end

# Run the examples
NormalizeExamples.run_examples()

IO.puts("\n📝 Summary:\n")
IO.puts("The normalize_result decorator ensures ALL functions return:")
IO.puts("  {:ok, result} | {:error, reason}")
IO.puts("\nIt handles:")
IO.puts("  ✅ Raw values → {:ok, value}")
IO.puts("  ✅ nil → {:ok, nil} or {:error, :nil_value}")
IO.puts("  ✅ false → {:ok, false} or {:error, :false_value}")
IO.puts("  ✅ Error atoms → {:error, atom}")
IO.puts("  ✅ Exceptions → {:error, exception}")
IO.puts("  ✅ Already result tuples → Pass through (with optional mapping)")
IO.puts("\nPerfect for wrapping external libraries and ensuring consistency!")
IO.puts("")
