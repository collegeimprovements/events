defmodule Events.Schema.ConditionalRequired do
  @moduledoc """
  Evaluates conditional required field expressions.

  Supports a DSL for declaring when fields are required based on other field values.

  ## DSL Syntax

  ### Equality (keyword list, implicit AND)

      [status: :active]
      [status: :active, type: :premium]    # both must match

  ### Comparison operators {field, operator, value}

      {:amount, :gt, 100}
      {:amount, :gte, 100}
      {:amount, :lt, 100}
      {:amount, :lte, 100}
      {:amount, :eq, 100}
      {:amount, :neq, 100}
      {:status, :in, [:active, :pending]}
      {:status, :not_in, [:draft, :cancelled]}

  ### Unary operators {field, operator}

      {:is_business, :truthy}
      {:is_business, :falsy}
      {:email, :present}
      {:email, :blank}

  ### Boolean combinators [condition, :and/:or, condition, ...]

      [[status: :active], :and, {:amount, :gt, 100}]
      [[type: :a], :or, [type: :b]]

  ### Chaining (same operator only)

      [cond1, :and, cond2, :and, cond3]
      [cond1, :or, cond2, :or, cond3]

  ### Negation

      {:not, [status: :draft]}
      {:not, {:amount, :gt, 100}}

  ### Nested grouping (lists as parentheses)

      [
        [[status: :active], :and, {:amount, :gt, 100}],
        :or,
        [[type: :vip], :and, {:priority, :gte, 5}]
      ]

  ### Function escape hatch

      &my_function/1
      {Module, :function}

  ## Examples

      field :shipping_address, :map,
        required_when: [[type: :physical], :and, {:requires_shipping, :truthy}]

      field :cancellation_reason, :string,
        required_when: [status: :cancelled]

      field :contact_phone, :string,
        required_when: [[notify_sms: true], :or, [notify_email: true]]
  """

  import Ecto.Changeset, only: [get_field: 2, add_error: 3]

  @comparison_ops [:eq, :neq, :gt, :gte, :lt, :lte, :in, :not_in]
  @unary_ops [:truthy, :falsy, :present, :blank]
  @boolean_ops [:and, :or]

  @doc """
  Validates conditional required fields on a changeset.

  Iterates through fields that have `required_when` conditions and adds
  errors for fields that are required but missing.
  """
  @spec validate(Ecto.Changeset.t(), [{atom(), any()}]) :: Ecto.Changeset.t()
  def validate(changeset, conditional_fields) do
    Enum.reduce(conditional_fields, changeset, fn {field, condition}, acc ->
      if required?(acc, condition) && field_blank?(acc, field) do
        add_error(acc, field, "is required")
      else
        acc
      end
    end)
  end

  @doc """
  Checks if a condition evaluates to true for the given changeset.
  """
  @spec required?(Ecto.Changeset.t(), any()) :: boolean()
  def required?(changeset, condition) do
    evaluate(changeset, condition)
  end

  @doc """
  Validates the condition DSL syntax at compile time.

  Returns `:ok` if valid, or `{:error, message}` if invalid.
  """
  @spec validate_syntax(any()) :: :ok | {:error, String.t()}
  def validate_syntax(condition) do
    case do_validate_syntax(condition) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  # ============================================================================
  # Evaluation
  # ============================================================================

  # Function escape hatch
  defp evaluate(changeset, fun) when is_function(fun, 1) do
    fun.(changeset)
  end

  # Negation: {:not, condition}
  defp evaluate(changeset, {:not, condition}) do
    not evaluate(changeset, condition)
  end

  # Unary operators: {:field, :truthy} etc.
  # Must come before MFA to avoid {field, op} being treated as {module, function}
  defp evaluate(changeset, {field, op}) when is_atom(field) and op in @unary_ops do
    value = get_field(changeset, field)
    evaluate_unary(op, value)
  end

  # Comparison operators: {:field, :gt, value}
  defp evaluate(changeset, {field, op, expected}) when is_atom(field) and op in @comparison_ops do
    value = get_field(changeset, field)
    evaluate_comparison(op, value, expected)
  end

  # MFA escape hatch - checked after unary/comparison to avoid false matches
  defp evaluate(changeset, {module, function}) when is_atom(module) and is_atom(function) do
    apply(module, function, [changeset])
  end

  # Boolean combinator list: [cond1, :and, cond2, ...]
  defp evaluate(changeset, [first | rest]) when is_list(rest) and length(rest) >= 2 do
    case parse_boolean_list([first | rest]) do
      {:ok, :and, conditions} ->
        Enum.all?(conditions, &evaluate(changeset, &1))

      {:ok, :or, conditions} ->
        Enum.any?(conditions, &evaluate(changeset, &1))

      {:error, reason} ->
        raise ArgumentError, "Invalid required_when condition: #{reason}"
    end
  end

  # Keyword list (equality, implicit AND): [status: :active, type: :vip]
  defp evaluate(changeset, conditions) when is_list(conditions) do
    if Keyword.keyword?(conditions) do
      Enum.all?(conditions, fn {field, expected} ->
        get_field(changeset, field) == expected
      end)
    else
      raise ArgumentError, "Invalid required_when condition: #{inspect(conditions)}"
    end
  end

  defp evaluate(_changeset, condition) do
    raise ArgumentError, "Invalid required_when condition: #{inspect(condition)}"
  end

  # ============================================================================
  # Operators
  # ============================================================================

  defp evaluate_unary(:truthy, value), do: !!value
  defp evaluate_unary(:falsy, value), do: !value
  defp evaluate_unary(:present, value), do: value != nil
  defp evaluate_unary(:blank, value), do: value == nil or value == ""

  defp evaluate_comparison(:eq, value, expected), do: value == expected
  defp evaluate_comparison(:neq, value, expected), do: value != expected
  defp evaluate_comparison(:gt, value, expected), do: value != nil and value > expected
  defp evaluate_comparison(:gte, value, expected), do: value != nil and value >= expected
  defp evaluate_comparison(:lt, value, expected), do: value != nil and value < expected
  defp evaluate_comparison(:lte, value, expected), do: value != nil and value <= expected
  defp evaluate_comparison(:in, value, expected), do: value in expected
  defp evaluate_comparison(:not_in, value, expected), do: value not in expected

  # ============================================================================
  # Boolean List Parsing
  # ============================================================================

  # Parse a list like [cond1, :and, cond2, :and, cond3] into {:ok, :and, [conditions]}
  defp parse_boolean_list(list) do
    {conditions, operators} = extract_conditions_and_operators(list, [], [])

    cond do
      operators == [] ->
        {:error, "no boolean operators found"}

      not all_same_operator?(operators) ->
        {:error, "mixed :and/:or operators require explicit grouping"}

      true ->
        {:ok, hd(operators), conditions}
    end
  end

  defp extract_conditions_and_operators([], conditions, operators) do
    {Enum.reverse(conditions), Enum.reverse(operators)}
  end

  defp extract_conditions_and_operators([condition, op | rest], conditions, operators)
       when op in @boolean_ops do
    extract_conditions_and_operators(rest, [condition | conditions], [op | operators])
  end

  defp extract_conditions_and_operators([condition], conditions, operators) do
    {Enum.reverse([condition | conditions]), Enum.reverse(operators)}
  end

  defp extract_conditions_and_operators([item | _], _, _) do
    raise ArgumentError, "Invalid item in boolean expression: #{inspect(item)}"
  end

  defp all_same_operator?([]), do: true
  defp all_same_operator?([_]), do: true
  defp all_same_operator?([op | rest]), do: Enum.all?(rest, &(&1 == op))

  # ============================================================================
  # Field Blank Check
  # ============================================================================

  defp field_blank?(changeset, field) do
    value = get_field(changeset, field)
    value == nil or value == "" or value == [] or value == %{}
  end

  # ============================================================================
  # Syntax Validation (Compile-time)
  # ============================================================================

  defp do_validate_syntax(fun) when is_function(fun, 1), do: :ok

  defp do_validate_syntax({module, function}) when is_atom(module) and is_atom(function), do: :ok

  defp do_validate_syntax({:not, condition}), do: do_validate_syntax(condition)

  defp do_validate_syntax({field, op}) when is_atom(field) and op in @unary_ops, do: :ok

  defp do_validate_syntax({field, op, _value}) when is_atom(field) and op in @comparison_ops,
    do: :ok

  defp do_validate_syntax({field, op, _value}) when is_atom(field) do
    {:error, "unknown comparison operator :#{op}, expected one of #{inspect(@comparison_ops)}"}
  end

  defp do_validate_syntax({field, op}) when is_atom(field) do
    {:error, "unknown unary operator :#{op}, expected one of #{inspect(@unary_ops)}"}
  end

  defp do_validate_syntax([_first | rest] = list) when is_list(rest) and length(rest) >= 2 do
    case parse_boolean_list_syntax(list) do
      {:ok, conditions} ->
        Enum.reduce_while(conditions, :ok, fn cond, :ok ->
          case do_validate_syntax(cond) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      {:error, _} = error ->
        error
    end
  end

  defp do_validate_syntax(conditions) when is_list(conditions) do
    if Keyword.keyword?(conditions) do
      :ok
    else
      {:error, "expected keyword list for equality conditions, got: #{inspect(conditions)}"}
    end
  end

  defp do_validate_syntax(other) do
    {:error, "invalid condition format: #{inspect(other)}"}
  end

  defp parse_boolean_list_syntax(list) do
    {conditions, operators} = extract_conditions_and_operators_syntax(list, [], [])

    cond do
      operators == [] ->
        {:error, "no boolean operators found in list"}

      not all_same_operator?(operators) ->
        {:error,
         "mixed :and/:or operators require explicit grouping - wrap sub-expressions in lists"}

      true ->
        {:ok, conditions}
    end
  end

  defp extract_conditions_and_operators_syntax([], conditions, operators) do
    {Enum.reverse(conditions), Enum.reverse(operators)}
  end

  defp extract_conditions_and_operators_syntax([condition, op | rest], conditions, operators)
       when op in @boolean_ops do
    extract_conditions_and_operators_syntax(rest, [condition | conditions], [op | operators])
  end

  defp extract_conditions_and_operators_syntax([condition], conditions, operators) do
    {Enum.reverse([condition | conditions]), Enum.reverse(operators)}
  end

  defp extract_conditions_and_operators_syntax([_condition, invalid_op | _], _, _) do
    {:error, "expected :and or :or, got: #{inspect(invalid_op)}"}
  end
end
