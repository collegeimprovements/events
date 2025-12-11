defmodule Events.Core.Query.TestHelpers do
  @moduledoc """
  Test utilities for the Events.Core.Query system.

  Provides assertion helpers and utilities for testing query building,
  token inspection, and SQL generation.

  ## Usage in Tests

  Add to your test case:

      use Events.Core.Query.TestHelpers

  Or import specific functions:

      import Events.Core.Query.TestHelpers

  ## Examples

      test "builds correct filter" do
        token = User
          |> Query.new()
          |> Query.filter(:status, :eq, "active")

        assert_has_operation(token, :filter)
        assert_filter_includes(token, :status, :eq, "active")
      end

      test "generates expected SQL" do
        token = User
          |> Query.new()
          |> Query.filter(:age, :gte, 18)

        assert_sql_contains(token, "age >= 18")
        refute_sql_contains(token, "DELETE")
      end
  """

  alias Events.Core.Query.Token
  alias Events.Core.Query.Builder
  alias Events.Core.Query.Debug

  # Configurable default repo - can be overridden via application config
  @default_repo Application.compile_env(:events, [Events.Core.Query, :default_repo], nil)

  @doc """
  Use this module in test cases.

  Imports all assertion helpers and sets up ExUnit assertions.

  ## Example

      defmodule MyQueryTest do
        use ExUnit.Case
        use Events.Core.Query.TestHelpers

        test "my query" do
          token = Query.new(User)
          assert_has_operation(token, :filter)
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import Events.Core.Query.TestHelpers
    end
  end

  ## Token Inspection Helpers

  @doc """
  Get all operations from a token.

  ## Examples

      ops = get_operations(token)
      assert length(ops) == 3
  """
  @spec get_operations(Token.t()) :: [Token.operation()]
  def get_operations(%Token{operations: ops}), do: ops

  @doc """
  Get operations of a specific type from a token.

  ## Examples

      filters = get_operations_by_type(token, :filter)
      assert length(filters) == 2
  """
  @spec get_operations_by_type(Token.t(), atom()) :: [Token.operation()]
  def get_operations_by_type(%Token{operations: ops}, type) do
    Enum.filter(ops, fn {op_type, _} -> op_type == type end)
  end

  @doc """
  Check if a token has any operation of a given type.

  ## Examples

      has_operation?(token, :filter)  # => true
      has_operation?(token, :lock)    # => false
  """
  @spec has_operation?(Token.t(), atom()) :: boolean()
  def has_operation?(%Token{} = token, type) do
    get_operations_by_type(token, type) != []
  end

  @doc """
  Get the source schema from a token.
  """
  @spec get_source(Token.t()) :: module() | Ecto.Query.t()
  def get_source(%Token{source: source}), do: source

  @doc """
  Get token metadata.
  """
  @spec get_metadata(Token.t()) :: map()
  def get_metadata(%Token{metadata: meta}), do: meta

  ## SQL Inspection Helpers

  @doc """
  Get the raw SQL string from a token.

  Returns `{:ok, sql}` or `{:error, reason}`.

  ## Options

  - `:repo` - The Ecto repo to use (default: configured default_repo)

  ## Examples

      {:ok, sql} = to_sql(token)
      assert sql =~ "WHERE"
  """
  @spec to_sql(Token.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_sql(%Token{} = token, opts \\ []) do
    try do
      sql = Debug.to_string(token, :raw_sql, opts)
      {:ok, sql}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Get the raw SQL string from a token, raising on error.

  ## Examples

      sql = to_sql!(token)
      assert sql =~ "SELECT"
  """
  @spec to_sql!(Token.t(), keyword()) :: String.t()
  def to_sql!(%Token{} = token, opts \\ []) do
    case to_sql(token, opts) do
      {:ok, sql} -> sql
      {:error, reason} -> raise "Failed to generate SQL: #{reason}"
    end
  end

  @doc """
  Get the SQL with parameters as a tuple.

  Returns `{:ok, {sql, params}}` or `{:error, reason}`.

  ## Examples

      {:ok, {sql, params}} = to_sql_with_params(token)
      assert sql =~ "$1"
      assert params == ["active"]
  """
  @spec to_sql_with_params(Token.t(), keyword()) :: {:ok, {String.t(), list()}} | {:error, term()}
  def to_sql_with_params(%Token{} = token, opts \\ []) do
    try do
      repo =
        opts[:repo] || Application.get_env(:events, :repo) || @default_repo ||
          raise "No repo configured. Pass :repo option or configure default_repo: config :events, Events.Core.Query, default_repo: MyApp.Repo"

      query = Builder.build(token)
      {:ok, repo.to_sql(:all, query)}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Build the Ecto.Query from a token.

  Returns `{:ok, query}` or `{:error, reason}`.

  ## Examples

      {:ok, query} = build_query(token)
      assert %Ecto.Query{} = query
  """
  @spec build_query(Token.t()) :: {:ok, Ecto.Query.t()} | {:error, term()}
  def build_query(%Token{} = token) do
    try do
      {:ok, Builder.build(token)}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  ## Assertion Helpers

  @doc """
  Assert that a token has an operation of the given type.

  ## Examples

      assert_has_operation(token, :filter)
      assert_has_operation(token, :order)
  """
  defmacro assert_has_operation(token, type) do
    quote do
      token = unquote(token)
      type = unquote(type)

      unless Events.Core.Query.TestHelpers.has_operation?(token, type) do
        ops = Events.Core.Query.TestHelpers.get_operations(token)
        op_types = Enum.map(ops, fn {t, _} -> t end) |> Enum.uniq()

        raise ExUnit.AssertionError,
          message: "Expected token to have operation :#{type}, but only found: #{inspect(op_types)}"
      end
    end
  end

  @doc """
  Assert that a token does not have an operation of the given type.

  ## Examples

      refute_has_operation(token, :lock)
  """
  defmacro refute_has_operation(token, type) do
    quote do
      token = unquote(token)
      type = unquote(type)

      if Events.Core.Query.TestHelpers.has_operation?(token, type) do
        raise ExUnit.AssertionError,
          message: "Expected token NOT to have operation :#{type}, but it does"
      end
    end
  end

  @doc """
  Assert that a token has a specific filter.

  ## Examples

      assert_filter_includes(token, :status, :eq, "active")
      assert_filter_includes(token, :age, :gte, 18)
  """
  defmacro assert_filter_includes(token, field, op, value) do
    quote do
      token = unquote(token)
      field = unquote(field)
      op = unquote(op)
      value = unquote(value)

      filters = Events.Core.Query.TestHelpers.get_operations_by_type(token, :filter)

      found =
        Enum.any?(filters, fn
          {:filter, {^field, ^op, ^value, _opts}} -> true
          _ -> false
        end)

      unless found do
        filter_info =
          Enum.map(filters, fn {:filter, {f, o, v, _}} -> {f, o, v} end)

        raise ExUnit.AssertionError,
          message:
            "Expected filter {#{inspect(field)}, #{inspect(op)}, #{inspect(value)}} not found.\nExisting filters: #{inspect(filter_info)}"
      end
    end
  end

  @doc """
  Assert that the generated SQL contains a substring.

  ## Examples

      assert_sql_contains(token, "WHERE status = 'active'")
      assert_sql_contains(token, "JOIN")
  """
  defmacro assert_sql_contains(token, substring) do
    quote do
      token = unquote(token)
      substring = unquote(substring)

      case Events.Core.Query.TestHelpers.to_sql(token) do
        {:ok, sql} ->
          unless String.contains?(sql, substring) do
            raise ExUnit.AssertionError,
              message: "Expected SQL to contain #{inspect(substring)}\n\nActual SQL:\n#{sql}"
          end

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Failed to generate SQL: #{reason}"
      end
    end
  end

  @doc """
  Assert that the generated SQL does NOT contain a substring.

  ## Examples

      refute_sql_contains(token, "DELETE")
      refute_sql_contains(token, "DROP")
  """
  defmacro refute_sql_contains(token, substring) do
    quote do
      token = unquote(token)
      substring = unquote(substring)

      case Events.Core.Query.TestHelpers.to_sql(token) do
        {:ok, sql} ->
          if String.contains?(sql, substring) do
            raise ExUnit.AssertionError,
              message: "Expected SQL NOT to contain #{inspect(substring)}\n\nActual SQL:\n#{sql}"
          end

        {:error, reason} ->
          raise ExUnit.AssertionError,
            message: "Failed to generate SQL: #{reason}"
      end
    end
  end

  @doc """
  Assert that a token has pagination of a specific type.

  ## Examples

      assert_pagination_type(token, :cursor)
      assert_pagination_type(token, :offset)
  """
  defmacro assert_pagination_type(token, expected_type) do
    quote do
      token = unquote(token)
      expected_type = unquote(expected_type)

      paginations = Events.Core.Query.TestHelpers.get_operations_by_type(token, :paginate)

      case paginations do
        [] ->
          raise ExUnit.AssertionError,
            message: "Expected token to have :#{expected_type} pagination, but no pagination found"

        [{:paginate, {actual_type, _opts}}] ->
          unless actual_type == expected_type do
            raise ExUnit.AssertionError,
              message: "Expected :#{expected_type} pagination, but found :#{actual_type}"
          end

        _ ->
          raise ExUnit.AssertionError,
            message: "Multiple pagination operations found, expected only one"
      end
    end
  end

  @doc """
  Assert that a token has an order by a specific field.

  ## Examples

      assert_order_includes(token, :created_at, :desc)
      assert_order_includes(token, :name, :asc)
  """
  defmacro assert_order_includes(token, field, direction) do
    quote do
      token = unquote(token)
      field = unquote(field)
      direction = unquote(direction)

      orders = Events.Core.Query.TestHelpers.get_operations_by_type(token, :order)

      found =
        Enum.any?(orders, fn
          {:order, {^field, ^direction, _opts}} -> true
          _ -> false
        end)

      unless found do
        order_info =
          Enum.map(orders, fn {:order, {f, d, _}} -> {f, d} end)

        raise ExUnit.AssertionError,
          message:
            "Expected order {#{inspect(field)}, #{inspect(direction)}} not found.\nExisting orders: #{inspect(order_info)}"
      end
    end
  end

  @doc """
  Assert that a token has a join for a specific association.

  ## Examples

      assert_join_includes(token, :posts)
      assert_join_includes(token, :category, :left)
  """
  defmacro assert_join_includes(token, assoc, join_type \\ :inner) do
    quote do
      token = unquote(token)
      assoc = unquote(assoc)
      join_type = unquote(join_type)

      joins = Events.Core.Query.TestHelpers.get_operations_by_type(token, :join)

      found =
        Enum.any?(joins, fn
          {:join, {^assoc, ^join_type, _opts}} -> true
          _ -> false
        end)

      unless found do
        join_info =
          Enum.map(joins, fn {:join, {a, t, _}} -> {a, t} end)

        raise ExUnit.AssertionError,
          message:
            "Expected join {#{inspect(assoc)}, #{inspect(join_type)}} not found.\nExisting joins: #{inspect(join_info)}"
      end
    end
  end

  @doc """
  Assert that the operation count matches expected.

  ## Examples

      assert_operation_count(token, :filter, 3)
      assert_operation_count(token, :join, 2)
  """
  defmacro assert_operation_count(token, type, expected_count) do
    quote do
      token = unquote(token)
      type = unquote(type)
      expected_count = unquote(expected_count)

      ops = Events.Core.Query.TestHelpers.get_operations_by_type(token, type)
      actual_count = length(ops)

      unless actual_count == expected_count do
        raise ExUnit.AssertionError,
          message: "Expected #{expected_count} :#{type} operations, but found #{actual_count}"
      end
    end
  end

  ## Query Comparison Helpers

  @doc """
  Compare two tokens for equivalent operations.

  Returns `true` if both tokens have the same operations in the same order.

  ## Examples

      token1 = User |> Query.new() |> Query.filter(:status, :eq, "active")
      token2 = User |> Query.new() |> Query.filter(:status, :eq, "active")

      assert tokens_equivalent?(token1, token2)
  """
  @spec tokens_equivalent?(Token.t(), Token.t()) :: boolean()
  def tokens_equivalent?(%Token{} = token1, %Token{} = token2) do
    token1.source == token2.source and
      token1.operations == token2.operations
  end

  @doc """
  Assert that two tokens are equivalent.

  ## Examples

      assert_tokens_equivalent(token1, token2)
  """
  defmacro assert_tokens_equivalent(token1, token2) do
    quote do
      t1 = unquote(token1)
      t2 = unquote(token2)

      unless Events.Core.Query.TestHelpers.tokens_equivalent?(t1, t2) do
        raise ExUnit.AssertionError,
          message: """
          Tokens are not equivalent.

          Token 1:
            Source: #{inspect(t1.source)}
            Operations: #{inspect(t1.operations, pretty: true)}

          Token 2:
            Source: #{inspect(t2.source)}
            Operations: #{inspect(t2.operations, pretty: true)}
          """
      end
    end
  end

  ## Debugging Helpers

  @doc """
  Print a token's debug info in tests.

  Useful for debugging test failures.

  ## Options

  - `:format` - Debug format (default: `:raw_sql`)
  - `:label` - Label for output

  ## Examples

      debug_token(token)
      debug_token(token, format: :pipeline, label: "After filters")
  """
  @spec debug_token(Token.t(), keyword()) :: Token.t()
  def debug_token(%Token{} = token, opts \\ []) do
    format = opts[:format] || :raw_sql
    label = opts[:label] || "Test Debug"
    Debug.debug(token, format, label: label)
  end

  @doc """
  Get a summary of a token's operations for debugging.

  Returns a map with operation counts and details.

  ## Examples

      summary = token_summary(token)
      # => %{
      #   source: User,
      #   operation_count: 5,
      #   operations_by_type: %{filter: 2, order: 1, paginate: 1, join: 1},
      #   filters: [{:status, :eq, "active"}, {:age, :gte, 18}],
      #   orders: [{:name, :asc}],
      #   ...
      # }
  """
  @spec token_summary(Token.t()) :: map()
  def token_summary(%Token{source: source, operations: ops, metadata: meta}) do
    by_type =
      Enum.group_by(ops, fn {type, _} -> type end)
      |> Enum.map(fn {type, list} -> {type, length(list)} end)
      |> Enum.into(%{})

    filters =
      get_operations_by_type(%Token{source: source, operations: ops, metadata: meta}, :filter)
      |> Enum.map(fn {:filter, {f, o, v, _}} -> {f, o, v} end)

    orders =
      get_operations_by_type(%Token{source: source, operations: ops, metadata: meta}, :order)
      |> Enum.map(fn {:order, {f, d, _}} -> {f, d} end)

    %{
      source: source,
      operation_count: length(ops),
      operations_by_type: by_type,
      filters: filters,
      orders: orders,
      metadata: meta
    }
  end
end
