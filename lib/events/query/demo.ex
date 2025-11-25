defmodule Events.Query.Demo do
  @moduledoc false
  # Demo module - not part of public API.
  #
  # Working demonstrations of the query system.
  # Run in IEx to see how the query system works.
  #
  # Quick Start:
  #   iex> Events.Query.Demo.token_composition()
  #   iex> Events.Query.Demo.token_inspection()
  #   iex> Events.Query.Demo.result_structure()

  alias Events.Query
  alias Events.Query.{Token, Result}
  import Events.Query.DSL

  @doc """
  Demonstrates token composition without execution.

  Shows how tokens accumulate operations and can be inspected.
  """
  def token_composition do
    IO.puts("\n=== Token Composition Demo ===\n")

    # Start with a base token (using atom for demo - would be a real schema)
    token = Query.new(:users)

    IO.puts("1. New token:")
    IO.inspect(token, label: "Token")

    # Add some operations
    token =
      token
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:age, :gte, 18)
      |> Query.order(:name, :asc)
      |> Query.limit(10)

    IO.puts("\n2. Token with operations:")
    IO.inspect(token.operations, label: "Operations", pretty: true)
    IO.puts("\nOperation count: #{length(token.operations)}")

    token
  end

  @doc """
  Demonstrates token inspection and manipulation.
  """
  def token_inspection do
    IO.puts("\n=== Token Inspection Demo ===\n")

    token =
      Query.new(:posts)
      |> Query.filter(:published, :eq, true)
      |> Query.filter(:views, :gt, 100)
      |> Query.order(:created_at, :desc)
      |> Query.limit(20)
      |> Query.offset(40)

    # Get specific operations
    filter_ops = Token.get_operations(token, :filter)
    IO.puts("Filter operations:")
    Enum.each(filter_ops, fn op -> IO.inspect(op) end)

    # Get pagination info
    limit_ops = Token.get_operations(token, :limit)
    offset_ops = Token.get_operations(token, :offset)

    IO.puts("\nPagination: limit=#{inspect(limit_ops)}, offset=#{inspect(offset_ops)}")

    # Remove operations
    token_without_limit = Token.remove_operations(token, :limit)
    IO.puts("\nOperations after removing limit: #{length(token_without_limit.operations)}")

    token
  end

  @doc """
  Demonstrates result structure creation.
  """
  def result_structure do
    IO.puts("\n=== Result Structure Demo ===\n")

    # Mock data
    data = [
      %{id: 1, name: "Item 1"},
      %{id: 2, name: "Item 2"},
      %{id: 3, name: "Item 3"}
    ]

    # Create result with offset pagination
    result =
      Result.paginated(data,
        pagination_type: :offset,
        limit: 3,
        offset: 0,
        total_count: 10,
        query_time_μs: 1500,
        total_time_μs: 2000,
        operation_count: 4
      )

    IO.puts("Offset Pagination Result:")
    IO.inspect(result.data, label: "Data")
    IO.inspect(result.pagination, label: "Pagination", pretty: true)
    IO.inspect(result.metadata, label: "Metadata", pretty: true)

    # Create result with cursor pagination
    cursor_result =
      Result.paginated(data,
        pagination_type: :cursor,
        limit: 3,
        cursor_fields: [:id],
        query_time_μs: 1200
      )

    IO.puts("\nCursor Pagination Result:")
    IO.inspect(cursor_result.pagination, label: "Pagination", pretty: true)

    result
  end

  @doc """
  Demonstrates DSL macro usage (without execution).
  """
  def dsl_example do
    IO.puts("\n=== DSL Macro Example ===\n")

    # This creates a token but doesn't execute
    token =
      query :users do
        filter(:status, :eq, "active")
        filter(:age, :gte, 21)
        order(:created_at, :desc)
        paginate(:offset, limit: 20, offset: 0)
      end

    IO.puts("DSL-generated token:")
    IO.inspect(token.source, label: "Source")
    IO.inspect(token.operations, label: "Operations", pretty: true)

    token
  end

  @doc """
  Demonstrates filter validation.
  """
  def filter_validation do
    IO.puts("\n=== Filter Validation Demo ===\n")

    token = Query.new(:products)

    # Valid filters
    IO.puts("Adding valid filters:")

    token =
      token
      |> Query.filter(:price, :gte, 10.00)
      |> Query.filter(:category, :in, ["electronics", "gadgets"])
      |> Query.filter(:name, :ilike, "%laptop%")

    IO.puts("✓ All filters valid")
    IO.inspect(length(token.operations), label: "Filter count")

    # Try invalid filter
    IO.puts("\nTrying invalid filter operator:")

    try do
      Query.filter(token, :status, :invalid_op, "value")
      IO.puts("✗ Should have raised error")
    rescue
      e in ArgumentError ->
        IO.puts("✓ Caught expected error: #{e.message}")
    end

    token
  end

  @doc """
  Demonstrates pagination options.
  """
  def pagination_options do
    IO.puts("\n=== Pagination Options Demo ===\n")

    # Offset pagination
    offset_token =
      Query.new(:posts)
      |> Query.paginate(:offset, limit: 20, offset: 40)

    IO.puts("Offset pagination token:")
    paginate_op = Enum.find(offset_token.operations, fn {type, _} -> type == :paginate end)
    IO.inspect(paginate_op, label: "Operation")

    # Cursor pagination
    cursor_token =
      Query.new(:posts)
      |> Query.paginate(:cursor,
        limit: 10,
        cursor_fields: [:created_at, :id],
        after: "some_cursor_value"
      )

    IO.puts("\nCursor pagination token:")
    paginate_op = Enum.find(cursor_token.operations, fn {type, _} -> type == :paginate end)
    IO.inspect(paginate_op, label: "Operation")

    {offset_token, cursor_token}
  end

  @doc """
  Demonstrates building queries (without executing).
  """
  def query_building do
    IO.puts("\n=== Query Building Demo ===\n")

    token =
      Query.new(:orders)
      |> Query.filter(:status, :in, ["pending", "processing"])
      |> Query.filter(:total, :gte, 100.00)
      |> Query.order(:created_at, :desc)
      |> Query.limit(50)

    IO.puts("Token ready for building:")

    IO.inspect(
      %{
        source: token.source,
        operation_count: length(token.operations),
        has_filters: length(Token.get_operations(token, :filter)),
        has_ordering: length(Token.get_operations(token, :order)) > 0,
        has_limit: length(Token.get_operations(token, :limit)) > 0
      },
      label: "Token summary"
    )

    token
  end

  @doc """
  Shows all available filter operators.
  """
  def filter_operators do
    IO.puts("\n=== Available Filter Operators ===\n")

    operators = [
      {:eq, "Equal to", "status: :eq, \"active\""},
      {:neq, "Not equal to", "status: :neq, \"inactive\""},
      {:gt, "Greater than", "age: :gt, 18"},
      {:gte, "Greater than or equal", "price: :gte, 10.00"},
      {:lt, "Less than", "stock: :lt, 5"},
      {:lte, "Less than or equal", "rating: :lte, 3.0"},
      {:in, "In list", "category: :in, [\"a\", \"b\"]"},
      {:not_in, "Not in list", "status: :not_in, [\"deleted\"]"},
      {:like, "Pattern match", "name: :like, \"%widget%\""},
      {:ilike, "Case-insensitive pattern", "email: :ilike, \"%@gmail.com\""},
      {:is_nil, "Is NULL", "deleted_at: :is_nil, nil"},
      {:not_nil, "Is not NULL", "verified_at: :not_nil, nil"},
      {:between, "Between range", "price: :between, {10, 100}"},
      {:contains, "Array contains", "tags: :contains, [\"featured\"]"},
      {:jsonb_contains, "JSONB contains", "metadata: :jsonb_contains, %{active: true}"},
      {:jsonb_has_key, "JSONB has key", "data: :jsonb_has_key, \"field_name\""}
    ]

    Enum.each(operators, fn {op, desc, example} ->
      IO.puts("#{String.pad_trailing(to_string(op), 18)} - #{desc}")
      IO.puts("  Example: filter(#{example})")
      IO.puts("")
    end)

    :ok
  end

  @doc """
  Run all demos.
  """
  def run_all do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("EVENTS.QUERY SYSTEM DEMO")
    IO.puts(String.duplicate("=", 60))

    token_composition()
    token_inspection()
    result_structure()
    dsl_example()
    filter_validation()
    pagination_options()
    query_building()
    filter_operators()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("✓ All demos completed!")
    IO.puts(String.duplicate("=", 60) <> "\n")

    :ok
  end
end
