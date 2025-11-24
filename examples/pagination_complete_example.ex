# Comprehensive Pagination Examples

# This file demonstrates all ways to handle pagination with metadata and total_count

## Approach 1: Events.Repo.Query with Paginated Methods

# Build a complex query with pagination
query_builder = Events.Repo.Query.new(Product)
                |> Events.Repo.Query.where(status: "active")
                |> Events.Repo.Query.join(:category)
                |> Events.Repo.Query.where({:category, :name, "Electronics"})
                |> Events.Repo.Query.order_by([desc: :price])

# Get total count for pagination metadata
total_count = Events.Repo.Query.count(query_builder)

# Execute paginated query
{products, pagination} = query_builder
                          |> Events.Repo.Query.paginate(:offset, limit: 10, offset: 20)
                          |> Events.Repo.Query.paginated_all()

# Add total_count to pagination metadata
complete_pagination = Map.put(pagination, :total_count, total_count)

# Result:
# products = [list of 10 products]
# complete_pagination = %{
#   type: :offset,
#   limit: 10,
#   offset: 20,
#   has_more: true,  # true if length(products) == limit
#   total_count: 150 # total products matching the query
# }

## Approach 2: CRUD System with Structured Results

# Build query with CRUD operations
result = Events.CRUD.new_token(Product)
         |> Events.CRUD.where(:status, :eq, "active")
         |> Events.CRUD.join(:category)
         |> Events.CRUD.where(:category, :name, :eq, "Electronics")
         |> Events.CRUD.order(:price, :desc)
         |> Events.CRUD.paginate(:offset, limit: 10, offset: 20)
         |> Events.CRUD.execute()

# Handle the structured result
case result do
  %Events.CRUD.Result{success: true, data: products, metadata: pagination} ->
    # pagination already includes comprehensive metadata
    # Note: CRUD system may not include total_count by default
    IO.puts("Found #{length(products)} products")
    IO.puts("Pagination: #{inspect(pagination)}")

  %Events.CRUD.Result{success: false, error: error} ->
    IO.puts("Error: #{inspect(error)}")
end

## Approach 3: Build-Only CRUD with Manual Total Count

# Build query without executing
crud_query = Events.CRUD.build_token(Product)
             |> Events.CRUD.where(:status, :eq, "active")
             |> Events.CRUD.join(:category)
             |> Events.CRUD.where(:category, :name, :eq, "Electronics")
             |> Events.CRUD.order(:price, :desc)
             |> Events.CRUD.paginate(:offset, limit: 10, offset: 20)
             |> Events.CRUD.execute()  # Returns Ecto.Query

# Get total count
total_count_query = Events.CRUD.build_token(Product)
                   |> Events.CRUD.where(:status, :eq, "active")
                   |> Events.CRUD.join(:category)
                   |> Events.CRUD.where(:category, :name, :eq, "Electronics")
                   |> Events.CRUD.execute()

total_count = Events.Repo.aggregate(total_count_query, :count, :id)

# Execute paginated query
products = Events.Repo.all(crud_query)

# Build pagination metadata manually
pagination = %{
  type: :offset,
  limit: 10,
  offset: 20,
  has_more: length(products) == 10,
  total_count: total_count,
  current_page: div(20, 10) + 1,  # Calculate current page
  total_pages: ceil(total_count / 10)  # Calculate total pages
}

## Approach 4: DSL with Build-Only and Manual Pagination

import Events.CRUD.DSL

# Build query with DSL
base_query = query Product, build_only: true do
  where :status, :eq, "active"
  join :category
  where :category, :name, :eq, "Electronics"
  order :price, :desc
end

# Get total count
total_count = Events.Repo.aggregate(base_query, :count, :id)

# Apply pagination and execute
paginated_query = base_query
                  |> Events.CRUD.paginate(:offset, limit: 10, offset: 20)
                  |> Events.CRUD.execute()

products = Events.Repo.all(paginated_query)

# Build complete pagination metadata
pagination = %{
  type: :offset,
  limit: 10,
  offset: 20,
  has_more: length(products) == 10,
  total_count: total_count,
  current_page: div(20, 10) + 1,
  total_pages: ceil(total_count / 10),
  next_offset: if(length(products) == 10, do: 20 + 10),
  prev_offset: if(20 > 0, do: max(0, 20 - 10))
}

## Approach 5: Cursor-Based Pagination

# For cursor pagination, you typically need cursor fields
{products, pagination} = Events.Repo.Query.new(Product)
                          |> Events.Repo.Query.where(status: "active")
                          |> Events.Repo.Query.order_by([desc: :inserted_at, desc: :id])
                          |> Events.Repo.Query.paginate(:cursor, limit: 10)
                          |> Events.Repo.Query.paginated_all()

# For cursor pagination, you'd typically encode the last item's cursor
# This is a simplified example - real cursor pagination is more complex
last_product = List.last(products)
cursor = %{inserted_at: last_product.inserted_at, id: last_product.id}

# Next page would use this cursor in the where clause
next_page_query = Events.Repo.Query.new(Product)
                  |> Events.Repo.Query.where(status: "active")
                  |> Events.Repo.Query.where({:inserted_at, :lt, cursor.inserted_at})
                  |> Events.Repo.Query.where({:id, :lt, cursor.id})
                  |> Events.Repo.Query.order_by([desc: :inserted_at, desc: :id])
                  |> Events.Repo.Query.limit(10)

## Helper Functions for Pagination

defmodule PaginationHelpers do
  @doc """
  Builds complete pagination metadata including total_count
  """
  def build_pagination_metadata(query_builder, results, total_count \\ nil) do
    pagination = case Map.get(query_builder.metadata, :pagination) do
      %{type: :offset, limit: limit, offset: offset} ->
        %{
          type: :offset,
          limit: limit,
          offset: offset,
          has_more: length(results) == limit,
          total_count: total_count,
          current_page: if(limit, do: div(offset, limit) + 1),
          total_pages: if(limit && total_count, do: ceil(total_count / limit)),
          next_offset: if(limit && length(results) == limit, do: offset + limit),
          prev_offset: if(offset > 0, do: max(0, offset - limit))
        }

      %{type: :cursor, limit: limit} ->
        %{
          type: :cursor,
          limit: limit,
          has_more: length(results) == limit,
          total_count: total_count,
          cursor: encode_cursor(List.last(results))
        }

      _ ->
        %{type: nil, has_more: false, total_count: total_count}
    end

    # Add total_count if provided
    if total_count do
      Map.put(pagination, :total_count, total_count)
    else
      pagination
    end
  end

  @doc """
  Calculates total count for a query builder
  """
  def get_total_count(query_builder) do
    # Create a count-only query (remove select, order, limit, offset)
    count_query = %{query_builder | query: from(q in query_builder.query, select: count(q.id))}
    Events.Repo.one(count_query)
  end

  @doc """
  Encodes cursor for cursor-based pagination (simplified)
  """
  def encode_cursor(nil), do: nil
  def encode_cursor(record) do
    # In practice, you'd encode this properly (base64, etc.)
    %{id: record.id, inserted_at: record.inserted_at}
  end
end

# Usage with helper:
query_builder = Events.Repo.Query.new(Product)
                |> Events.Repo.Query.where(status: "active")
                |> Events.Repo.Query.paginate(:offset, limit: 10, offset: 20)

total_count = PaginationHelpers.get_total_count(query_builder)
{products, basic_pagination} = Events.Repo.Query.paginated_all(query_builder)
