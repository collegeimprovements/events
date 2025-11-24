# Comprehensive Structured Pagination Examples

# This demonstrates the new structured pagination system with cursors and total_count

## Basic Offset Pagination with Total Count

# Build query
query_builder =
  Events.Repo.Query.new(Product)
  |> Events.Repo.Query.where(status: "active")
  |> Events.Repo.Query.order_by(desc: :price)

# Execute with pagination and total count
result =
  query_builder
  |> Events.Repo.Query.paginate(:offset, limit: 10, offset: 20)
  |> Events.Repo.Query.paginated_all(include_total_count: true)

# Structured result
%{
  # List of products
  data: products,
  pagination: %{
    type: :offset,
    limit: 10,
    offset: 20,
    has_more: true,
    total_count: 150,
    current_page: 3,
    total_pages: 15,
    next_offset: 30,
    prev_offset: 10
  }
}

## Cursor-Based Pagination

# Build query with proper ordering for cursors
query_builder =
  Events.Repo.Query.new(Product)
  |> Events.Repo.Query.where(status: "active")
  |> Events.Repo.Query.order_by(desc: :inserted_at, desc: :id)

# First page
first_page =
  query_builder
  |> Events.Repo.Query.paginate(:cursor, limit: 10, cursor_fields: [:inserted_at, :id])
  |> Events.Repo.Query.paginated_all(include_total_count: true)

# Get cursor from first page for next page
next_cursor = first_page.pagination.end_cursor

# Next page using after cursor
next_page =
  query_builder
  |> Events.Repo.Query.paginate(:cursor,
    limit: 10,
    cursor_fields: [:inserted_at, :id],
    after: next_cursor
  )
  |> Events.Repo.Query.paginated_all()

# Previous page using before cursor
prev_page =
  query_builder
  |> Events.Repo.Query.paginate(:cursor,
    limit: 10,
    cursor_fields: [:inserted_at, :id],
    before: next_cursor
  )
  |> Events.Repo.Query.paginated_all()

## Cursor Pagination Result Structure

%{
  data: products,
  pagination: %{
    type: :cursor,
    limit: 10,
    has_more: true,
    total_count: 150,
    cursor_fields: [:inserted_at, :id],
    # Base64 encoded Elixir term
    start_cursor: "g2wAAAACZAAKaW5zZXJ0ZWRfYXR0ZAAVMjAyNC0wMS0xNVQwMDowMDowMFoABmlkZAAEIw==",
    # Base64 encoded Elixir term
    end_cursor: "g2wAAAACZAAKaW5zZXJ0ZWRfYXR0ZAAVMjAyNC0wMS0xMFQwMDowMDowMFoABmlkZAAEMTA=",
    # Would need more logic
    has_previous_page: false,
    has_next_page: true
  }
}

## CRUD System Integration

# Build query with CRUD operations
crud_result =
  Events.CRUD.build_token(Product)
  |> Events.CRUD.where(:status, :eq, "active")
  |> Events.CRUD.order(:price, :desc)
  |> Events.CRUD.paginate(:offset, limit: 10, offset: 20)
  |> Events.CRUD.execute()

# Convert to structured pagination format
case crud_result do
  %Events.CRUD.Result{success: true, data: products, metadata: crud_pagination} ->
    # Get total count separately
    total_count_query =
      Events.CRUD.build_token(Product)
      |> Events.CRUD.where(:status, :eq, "active")
      |> Events.CRUD.execute()

    total_count = Events.Repo.aggregate(total_count_query, :count, :id)

    # Build structured result
    structured_result = %{
      data: products,
      pagination: Map.put(crud_pagination, :total_count, total_count)
    }
end

## Helper Functions for Pagination

defmodule PaginationHelpers do
  @doc """
  Unified pagination function that handles all types
  """
  def paginate_query(query_builder, pagination_opts, execution_opts \\ []) do
    include_total_count = Keyword.get(execution_opts, :include_total_count, false)

    case pagination_opts[:type] do
      :offset ->
        query_builder
        |> Events.Repo.Query.paginate(:offset, pagination_opts)
        |> Events.Repo.Query.paginated_all(include_total_count: include_total_count)

      :cursor ->
        query_builder
        |> Events.Repo.Query.paginate(:cursor, pagination_opts)
        |> Events.Repo.Query.paginated_all(include_total_count: include_total_count)
    end
  end

  @doc """
  Extract pagination info for API responses
  """
  def format_pagination_response(result) do
    %{
      data: result.data,
      pagination: %{
        page_info: extract_page_info(result.pagination),
        total_count: result.pagination.total_count
      }
    }
  end

  defp extract_page_info(%{type: :offset} = pagination) do
    %{
      type: :offset,
      current_page: pagination.current_page,
      total_pages: pagination.total_pages,
      has_next_page: pagination.has_more,
      has_previous_page: pagination.current_page > 1,
      next_offset: pagination.next_offset,
      prev_offset: pagination.prev_offset
    }
  end

  defp extract_page_info(%{type: :cursor} = pagination) do
    %{
      type: :cursor,
      has_next_page: pagination.has_next_page,
      has_previous_page: pagination.has_previous_page,
      start_cursor: pagination.start_cursor,
      end_cursor: pagination.end_cursor
    }
  end
end

# Usage example
query_builder =
  Events.Repo.Query.new(Product)
  |> Events.Repo.Query.where(status: "active")

result =
  PaginationHelpers.paginate_query(
    query_builder,
    %{type: :offset, limit: 10, offset: 20},
    include_total_count: true
  )
