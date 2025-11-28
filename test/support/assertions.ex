defmodule Events.Test.Assertions do
  @moduledoc """
  Custom test assertions for cleaner, more expressive tests.

  ## Usage

      use Events.Test.Assertions

  Or import specific assertions:

      import Events.Test.Assertions, only: [assert_ok: 1, assert_error: 1]

  ## Available Assertions

  ### Result Tuple Assertions
  - `assert_ok/1` - Assert `{:ok, value}` and return value
  - `assert_ok!/1` - Assert `{:ok, value}` or raise
  - `assert_error/1` - Assert `{:error, reason}` and return reason
  - `assert_error/2` - Assert `{:error, expected_reason}`

  ### Changeset Assertions
  - `assert_valid/1` - Assert changeset is valid
  - `assert_invalid/1` - Assert changeset is invalid
  - `assert_error_on/2` - Assert specific field has error
  - `assert_error_on/3` - Assert specific field has specific error message

  ### Collection Assertions
  - `assert_contains/2` - Assert collection contains element
  - `assert_all/2` - Assert all elements match predicate

  ### Timing Assertions
  - `assert_under/2` - Assert operation completes under time limit
  """

  import ExUnit.Assertions

  # ============================================
  # Result Tuple Assertions
  # ============================================

  @doc """
  Asserts the result is `{:ok, value}` and returns the value.

  ## Examples

      {:ok, user} = create_user(attrs)
      user = assert_ok(create_user(attrs))  # cleaner
  """
  defmacro assert_ok(result) do
    quote do
      case unquote(result) do
        {:ok, value} ->
          value

        {:error, reason} ->
          flunk("Expected {:ok, _}, got {:error, #{inspect(reason)}}")

        other ->
          flunk("Expected {:ok, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is `{:ok, value}` matching the pattern.

  ## Examples

      assert_ok %User{email: "[email protected]"} = create_user(attrs)
  """
  defmacro assert_ok(pattern, result) do
    quote do
      case unquote(result) do
        {:ok, unquote(pattern) = value} ->
          value

        {:ok, value} ->
          flunk(
            "Expected {:ok, #{unquote(Macro.to_string(pattern))}}, got {:ok, #{inspect(value)}}"
          )

        {:error, reason} ->
          flunk("Expected {:ok, _}, got {:error, #{inspect(reason)}}")

        other ->
          flunk("Expected {:ok, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is `{:error, reason}` and returns the reason.

  ## Examples

      reason = assert_error(create_user(%{email: "invalid"}))
      assert reason == :invalid_email
  """
  defmacro assert_error(result) do
    quote do
      case unquote(result) do
        {:error, reason} ->
          reason

        {:ok, value} ->
          flunk("Expected {:error, _}, got {:ok, #{inspect(value)}}")

        other ->
          flunk("Expected {:error, _}, got #{inspect(other)}")
      end
    end
  end

  @doc """
  Asserts the result is `{:error, expected_reason}`.

  ## Examples

      assert_error(:not_found, get_user(999))
      assert_error(:invalid_email, create_user(%{email: "bad"}))
  """
  defmacro assert_error(expected_reason, result) do
    quote do
      case unquote(result) do
        {:error, unquote(expected_reason)} ->
          unquote(expected_reason)

        {:error, reason} ->
          flunk(
            "Expected {:error, #{inspect(unquote(expected_reason))}}, " <>
              "got {:error, #{inspect(reason)}}"
          )

        {:ok, value} ->
          flunk("Expected {:error, _}, got {:ok, #{inspect(value)}}")

        other ->
          flunk("Expected {:error, _}, got #{inspect(other)}")
      end
    end
  end

  # ============================================
  # Changeset Assertions
  # ============================================

  @doc """
  Asserts the changeset is valid.

  ## Examples

      changeset = User.changeset(%User{}, valid_attrs)
      assert_valid(changeset)
  """
  def assert_valid(%Ecto.Changeset{valid?: true} = changeset), do: changeset

  def assert_valid(%Ecto.Changeset{valid?: false} = changeset) do
    errors = format_changeset_errors(changeset)
    flunk("Expected changeset to be valid, but got errors:\n#{errors}")
  end

  @doc """
  Asserts the changeset is invalid.

  ## Examples

      changeset = User.changeset(%User{}, invalid_attrs)
      assert_invalid(changeset)
  """
  def assert_invalid(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  def assert_invalid(%Ecto.Changeset{valid?: true} = changeset) do
    flunk(
      "Expected changeset to be invalid, but it was valid.\nChanges: #{inspect(changeset.changes)}"
    )
  end

  @doc """
  Asserts a specific field has an error.

  ## Examples

      assert_error_on(changeset, :email)
  """
  def assert_error_on(%Ecto.Changeset{} = changeset, field) when is_atom(field) do
    errors = Ecto.Changeset.traverse_errors(changeset, & &1)

    if Map.has_key?(errors, field) do
      changeset
    else
      available = Map.keys(errors) |> Enum.join(", ")

      flunk(
        "Expected error on :#{field}, but no error found.\n" <>
          "Fields with errors: #{if available == "", do: "(none)", else: available}"
      )
    end
  end

  @doc """
  Asserts a specific field has a specific error message.

  ## Examples

      assert_error_on(changeset, :email, "can't be blank")
      assert_error_on(changeset, :email, ~r/invalid/)
  """
  def assert_error_on(%Ecto.Changeset{} = changeset, field, expected) when is_atom(field) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    field_errors = Map.get(errors, field, [])

    cond do
      field_errors == [] ->
        flunk("Expected error on :#{field}, but no error found")

      is_binary(expected) and expected in field_errors ->
        changeset

      is_struct(expected, Regex) and Enum.any?(field_errors, &Regex.match?(expected, &1)) ->
        changeset

      true ->
        flunk(
          "Expected error matching #{inspect(expected)} on :#{field}\n" <>
            "Actual errors: #{inspect(field_errors)}"
        )
    end
  end

  # ============================================
  # Collection Assertions
  # ============================================

  @doc """
  Asserts that a collection contains the given element.

  ## Examples

      assert_contains(users, %{email: "[email protected]"})
      assert_contains(tags, "elixir")
  """
  def assert_contains(collection, element) when is_list(collection) do
    if element in collection do
      collection
    else
      flunk(
        "Expected collection to contain #{inspect(element)}\nCollection: #{inspect(collection)}"
      )
    end
  end

  def assert_contains(%MapSet{} = set, element) do
    if MapSet.member?(set, element) do
      set
    else
      flunk("Expected set to contain #{inspect(element)}")
    end
  end

  @doc """
  Asserts all elements in collection satisfy the predicate.

  ## Examples

      assert_all(users, fn u -> u.status == :active end)
      assert_all(prices, &(&1 > 0))
  """
  def assert_all(collection, predicate) when is_function(predicate, 1) do
    failures =
      collection
      |> Enum.with_index()
      |> Enum.reject(fn {elem, _idx} -> predicate.(elem) end)

    if failures == [] do
      collection
    else
      failure_info =
        failures
        |> Enum.map(fn {elem, idx} -> "  [#{idx}]: #{inspect(elem)}" end)
        |> Enum.join("\n")

      flunk("Expected all elements to satisfy predicate, but these failed:\n#{failure_info}")
    end
  end

  # ============================================
  # Timing Assertions
  # ============================================

  @doc """
  Asserts that the given function executes under the time limit.

  ## Examples

      assert_under 100, :millisecond do
        quick_operation()
      end

      assert_under 1, :second do
        slower_operation()
      end
  """
  defmacro assert_under(amount, unit, do: block) do
    quote do
      {time_microseconds, result} = :timer.tc(fn -> unquote(block) end)

      limit_microseconds =
        case unquote(unit) do
          :microsecond -> unquote(amount)
          :millisecond -> unquote(amount) * 1_000
          :second -> unquote(amount) * 1_000_000
        end

      if time_microseconds > limit_microseconds do
        flunk(
          "Expected operation to complete under #{unquote(amount)} #{unquote(unit)}, " <>
            "but took #{time_microseconds} microseconds"
        )
      end

      result
    end
  end

  # ============================================
  # Helpers
  # ============================================

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "  #{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("\n")
  end

  defmacro __using__(_opts) do
    quote do
      import Events.Test.Assertions
    end
  end
end
