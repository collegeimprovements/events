defmodule Events.CRUD.Pattern do
  @moduledoc """
  Advanced pattern matching DSL for complex query construction.

  Provides sophisticated patterns for building queries based on conditions,
  allowing for dynamic query construction with pattern matching.

  ## Examples

      # Pattern-based filtering
      Events.CRUD.Pattern.match(user, [
        active: true,
        role: {:in, ["admin", "moderator"]},
        created_at: {:gt, ~U[2024-01-01 00:00:00Z]}
      ])

      # Conditional operations
      Events.CRUD.Pattern.when(user.role == "admin", fn ->
        preload :admin_permissions
      end)

      # Complex branching logic
      Events.CRUD.Pattern.case(user.type, %{
        "premium" => fn -> preload [:posts, :comments], limit: 100 end,
        "basic" => fn -> preload :posts, limit: 10 end,
        _ => fn -> limit 5 end
      })
  """

  @doc """
  Builds a token based on pattern matching against data.

  ## Examples

      data = %{status: "active", role: "admin", score: 95}

      Events.CRUD.Pattern.match(data, [
        status: :active,
        role: {:in, ["admin", "moderator"]},
        score: {:gte, 90}
      ])
  """
  @spec match(map(), keyword()) :: Events.CRUD.Token.t()
  def match(data, patterns) when is_map(data) and is_list(patterns) do
    token = Events.CRUD.Token.new()

    Enum.reduce(patterns, token, fn {field, condition}, acc ->
      if matches_condition?(data, field, condition) do
        apply_condition(acc, field, condition)
      else
        acc
      end
    end)
  end

  @doc """
  Conditionally applies operations based on a predicate.

  ## Examples

      Events.CRUD.Pattern.when_condition(user.admin?, fn ->
        preload :admin_permissions
        join :audit_logs, :left
      end)
  """
  def when_condition(predicate, fun) when is_boolean(predicate) and is_function(fun, 0) do
    if predicate do
      fun.()
    else
      Events.CRUD.Token.new()
    end
  end

  @doc """
  Pattern matches on a value and applies different operations.

  ## Examples

      Events.CRUD.Pattern.case(user.plan, %{
        "premium" => fn -> limit 100 end,
        "basic" => fn -> limit 10 end,
        _ => fn -> limit 5 end
      })
  """
  @spec case(term(), %{term() => (-> Events.CRUD.Token.t())}) :: Events.CRUD.Token.t()
  def case(value, patterns) when is_map(patterns) do
    case Map.get(patterns, value) || Map.get(patterns, :_) do
      nil -> Events.CRUD.Token.new()
      fun when is_function(fun, 0) -> fun.()
      _ -> Events.CRUD.Token.new()
    end
  end

  @doc """
  Applies operations only if all conditions are met.

  ## Examples

      Events.CRUD.Pattern.all([
        user.active?,
        user.verified?,
        user.created_at > ~U[2024-01-01 00:00:00Z]
      ], fn ->
        preload [:posts, :comments]
        order :engagement_score, :desc
      end)
  """
  @spec all([boolean()], (-> Events.CRUD.Token.t())) :: Events.CRUD.Token.t()
  def all(conditions, fun) when is_list(conditions) and is_function(fun, 0) do
    if Enum.all?(conditions, & &1) do
      fun.()
    else
      Events.CRUD.Token.new()
    end
  end

  @doc """
  Applies operations if any condition is met.

  ## Examples

      Events.CRUD.Pattern.any([
        user.admin?,
        user.moderator?,
        user.created_at < ~U[2024-01-01 00:00:00Z]
      ], fn ->
        preload :special_permissions
      end)
  """
  @spec any([boolean()], (-> Events.CRUD.Token.t())) :: Events.CRUD.Token.t()
  def any(conditions, fun) when is_list(conditions) and is_function(fun, 0) do
    if Enum.any?(conditions, & &1) do
      fun.()
    else
      Events.CRUD.Token.new()
    end
  end

  @doc """
  Chains multiple pattern-based operations.

  ## Examples

      Events.CRUD.Pattern.chain([
        &match(&1, [active: true]),
        &when(&1.admin?, fn -> preload :permissions end),
        &case(&1.role, %{"admin" => fn -> limit 1000 end, _ => fn -> limit 100 end})
      ], user)
  """
  @spec chain([(term() -> Events.CRUD.Token.t())], term()) :: Events.CRUD.Token.t()
  def chain(patterns, data) when is_list(patterns) do
    Enum.reduce(patterns, Events.CRUD.Token.new(), fn pattern_fun, acc ->
      Events.CRUD.Token.merge(acc, pattern_fun.(data))
    end)
  end

  # Private helper functions

  defp matches_condition?(data, field, condition) do
    value = Map.get(data, field)
    matches_value?(value, condition)
  end

  defp matches_value?(value, :any), do: true
  defp matches_value?(value, {:eq, expected}), do: value == expected
  defp matches_value?(value, {:neq, expected}), do: value != expected
  defp matches_value?(value, {:gt, expected}), do: value > expected
  defp matches_value?(value, {:gte, expected}), do: value >= expected
  defp matches_value?(value, {:lt, expected}), do: value < expected
  defp matches_value?(value, {:lte, expected}), do: value <= expected
  defp matches_value?(value, {:in, list}), do: value in list
  defp matches_value?(value, {:not_in, list}), do: value not in list
  defp matches_value?(value, {:like, pattern}), do: String.contains?(to_string(value), pattern)
  defp matches_value?(value, {:between, min..max}), do: value >= min and value <= max
  defp matches_value?(value, expected), do: value == expected

  defp apply_condition(token, field, condition) do
    case condition do
      {:eq, value} -> Events.CRUD.Token.add(token, {:where, {field, :eq, value, []}})
      {:neq, value} -> Events.CRUD.Token.add(token, {:where, {field, :neq, value, []}})
      {:gt, value} -> Events.CRUD.Token.add(token, {:where, {field, :gt, value, []}})
      {:gte, value} -> Events.CRUD.Token.add(token, {:where, {field, :gte, value, []}})
      {:lt, value} -> Events.CRUD.Token.add(token, {:where, {field, :lt, value, []}})
      {:lte, value} -> Events.CRUD.Token.add(token, {:where, {field, :lte, value, []}})
      {:in, value} -> Events.CRUD.Token.add(token, {:where, {field, :in, value, []}})
      {:not_in, value} -> Events.CRUD.Token.add(token, {:where, {field, :not_in, value, []}})
      {:like, value} -> Events.CRUD.Token.add(token, {:where, {field, :like, value, []}})
      {:between, value} -> Events.CRUD.Token.add(token, {:where, {field, :between, value, []}})
      _ -> token
    end
  end
end
