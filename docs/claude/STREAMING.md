# Streaming and Lazy Evaluation

> **Memory-efficient processing of large datasets with FnTypes.Lazy.**

## Overview

`FnTypes.Lazy` provides:
- **Deferred computation**: Execute only when needed
- **Stream processing**: Memory-efficient iteration
- **Result integration**: Error handling in streams
- **Pagination support**: Consume paginated APIs lazily

---

## Quick Reference

| Function | Purpose |
|----------|---------|
| `defer/1` | Create deferred computation |
| `run/1` | Execute deferred computation |
| `stream/3` | Create Result stream from enumerable |
| `stream_map/2` | Transform stream elements |
| `stream_filter/2` | Filter stream elements |
| `stream_take/2` | Take first N elements |
| `stream_collect/2` | Collect stream to list |
| `stream_reduce/3` | Reduce stream with accumulator |
| `stream_batch/3` | Process in batches |
| `paginate/3` | Lazy pagination |

---

## Deferred Computation

### Basic Usage

```elixir
alias FnTypes.Lazy

# Create deferred computation - nothing executes yet
lazy = Lazy.defer(fn ->
  IO.puts("Computing...")
  {:ok, expensive_calculation()}
end)

# Execute when needed
{:ok, result} = Lazy.run(lazy)
# Prints: Computing...
```

### Chaining Deferred Computations

```elixir
Lazy.defer(fn -> fetch_config() end)
|> Lazy.and_then(fn config ->
  Lazy.defer(fn -> apply_config(config) end)
end)
|> Lazy.and_then_result(fn applied ->
  validate_config(applied)  # Returns {:ok, _} | {:error, _}
end)
|> Lazy.run()
```

### Error Handling

```elixir
Lazy.defer(fn -> {:error, :not_found} end)
|> Lazy.or_else(fn _reason ->
  Lazy.defer(fn -> {:ok, default_value()} end)
end)
|> Lazy.run()
#=> {:ok, default_value}
```

---

## Stream Processing

### Creating Streams

```elixir
# From enumerable with Result-returning function
users = [1, 2, 3, 4, 5]

stream = Lazy.stream(users, fn id ->
  case Repo.get(User, id) do
    nil -> {:error, {:not_found, id}}
    user -> {:ok, user}
  end
end)

# Stream hasn't executed yet - it's lazy
```

### Error Handling Options

```elixir
# Default: halt on first error
users
|> Lazy.stream(&fetch_user/1)
|> Lazy.stream_collect()
#=> {:ok, [users...]} | {:error, first_error}

# Skip errors
users
|> Lazy.stream(&fetch_user/1, on_error: :skip)
|> Lazy.stream_collect()
#=> {:ok, [successful_users...]}

# Collect errors
users
|> Lazy.stream(&fetch_user/1, on_error: :collect)
|> Lazy.stream_collect(settle: true)
#=> %{ok: [users...], errors: [errors...]}

# Max errors before halt
users
|> Lazy.stream(&fetch_user/1, on_error: :skip, max_errors: 10)
|> Lazy.stream_collect()
```

### Transforming Streams

```elixir
# Map over successful values
stream
|> Lazy.stream_map(fn user ->
  {:ok, %{id: user.id, name: user.name}}
end)

# Filter with predicate
stream
|> Lazy.stream_filter(fn user ->
  {:ok, user.active?}
end)

# Take first N
stream
|> Lazy.stream_take(100)

# Chain operations
users
|> Lazy.stream(&fetch_user/1, on_error: :skip)
|> Lazy.stream_filter(fn u -> {:ok, u.active?} end)
|> Lazy.stream_map(fn u -> {:ok, format_user(u)} end)
|> Lazy.stream_take(50)
|> Lazy.stream_collect()
```

### Reducing Streams

```elixir
# Sum values
orders
|> Lazy.stream(&fetch_order/1)
|> Lazy.stream_reduce(0, fn order, acc ->
  {:ok, acc + order.total}
end)
#=> {:ok, total_sum}

# Build map
items
|> Lazy.stream(&process_item/1)
|> Lazy.stream_reduce(%{}, fn item, acc ->
  {:ok, Map.put(acc, item.id, item)}
end)
#=> {:ok, %{id1 => item1, id2 => item2, ...}}
```

---

## Pagination

### Basic Pagination

```elixir
# Consume paginated API lazily
Lazy.paginate(
  fn cursor ->
    # Fetch page - returns {:ok, page} | {:error, reason}
    API.list_users(cursor: cursor, limit: 100)
  end,
  fn page ->
    # Extract next cursor (nil to stop)
    page.next_cursor
  end
)
|> Lazy.stream_map(&process_user/1)
|> Lazy.stream_collect()
```

### With Custom Item Extraction

```elixir
Lazy.paginate(
  &fetch_page/1,
  fn page -> page.meta.next_page end,
  get_items: fn page -> page.data.records end,
  initial_cursor: %{page: 1}
)
```

### Database Pagination

```elixir
# Paginate through database records
Lazy.paginate(
  fn cursor ->
    query =
      from u in User,
        where: u.id > ^(cursor || 0),
        order_by: [asc: :id],
        limit: 1000

    users = Repo.all(query)

    case users do
      [] -> {:ok, %{items: [], next: nil}}
      users -> {:ok, %{items: users, next: List.last(users).id}}
    end
  end,
  fn page -> page.next end,
  get_items: fn page -> page.items end
)
|> Lazy.stream_map(&process_user/1)
|> Lazy.stream_collect()
```

---

## Batch Processing

### Processing in Chunks

```elixir
# Process records in batches of 100
users
|> Lazy.stream(&{:ok, &1})  # Wrap in ok tuples
|> Lazy.stream_batch(100, fn batch ->
  # Bulk insert
  {count, _} = Repo.insert_all(ProcessedUser, batch)
  {:ok, count}
end)
|> Lazy.stream_collect()
#=> {:ok, [100, 100, 100, 47]}  # Counts per batch
```

### Batch API Calls

```elixir
user_ids
|> Lazy.stream(&{:ok, &1})
|> Lazy.stream_batch(50, fn ids ->
  # Batch API call
  case ExternalAPI.batch_fetch_users(ids) do
    {:ok, users} -> {:ok, users}
    {:error, _} = err -> err
  end
end)
|> Lazy.stream_collect()
```

---

## Real-World Examples

### Example 1: Export Large Dataset

```elixir
defmodule MyApp.Exports do
  alias FnTypes.Lazy

  def export_users_to_csv(output_path) do
    File.open!(output_path, [:write, :utf8], fn file ->
      # Write header
      IO.write(file, "id,email,name,created_at\n")

      # Stream users in batches
      result =
        stream_all_users()
        |> Lazy.stream_map(&format_csv_row/1)
        |> Lazy.stream_reduce(:ok, fn row, :ok ->
          IO.write(file, row)
          {:ok, :ok}
        end)

      result
    end)
  end

  defp stream_all_users do
    Lazy.paginate(
      fn cursor ->
        query =
          from u in User,
            where: u.id > ^(cursor || 0),
            order_by: [asc: :id],
            limit: 1000,
            select: %{id: u.id, email: u.email, name: u.name, created_at: u.inserted_at}

        users = Repo.all(query)
        next = if users == [], do: nil, else: List.last(users).id
        {:ok, %{items: users, next: next}}
      end,
      & &1.next,
      get_items: & &1.items
    )
  end

  defp format_csv_row(user) do
    {:ok, "#{user.id},#{user.email},#{user.name},#{user.created_at}\n"}
  end
end
```

### Example 2: Sync External Data

```elixir
defmodule MyApp.Sync do
  alias FnTypes.Lazy

  def sync_from_external_api do
    Lazy.paginate(
      fn cursor ->
        ExternalAPI.list_records(cursor: cursor, per_page: 100)
      end,
      fn response -> response.meta.next_cursor end,
      get_items: fn response -> response.data end
    )
    |> Lazy.stream_batch(50, fn records ->
      # Upsert batch
      Repo.insert_all(
        SyncedRecord,
        Enum.map(records, &transform_record/1),
        on_conflict: :replace_all,
        conflict_target: :external_id
      )
      {:ok, length(records)}
    end)
    |> Lazy.stream_reduce(0, fn count, total ->
      {:ok, total + count}
    end)
  end
end
```

### Example 3: Parallel Stream Processing

```elixir
defmodule MyApp.ImageProcessor do
  alias FnTypes.{Lazy, AsyncResult}

  def process_images(image_ids) do
    image_ids
    |> Lazy.stream(&fetch_image/1, on_error: :skip)
    |> Lazy.stream_batch(10, fn images ->
      # Process batch in parallel
      tasks = Enum.map(images, fn img ->
        fn -> process_single_image(img) end
      end)

      case AsyncResult.parallel(tasks, max_concurrency: 5) do
        {:ok, results} -> {:ok, results}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Lazy.stream_collect()
  end
end
```

### Example 4: ETL Pipeline

```elixir
defmodule MyApp.ETL do
  alias FnTypes.{Lazy, Pipeline}

  def run_etl(source_query) do
    Pipeline.new(%{query: source_query, stats: %{processed: 0, errors: 0}})
    |> Pipeline.step(:extract, fn ctx ->
      stream =
        ctx.query
        |> Repo.stream()
        |> Lazy.stream(&{:ok, &1})

      {:ok, %{source_stream: stream}}
    end)
    |> Pipeline.step(:transform_and_load, fn ctx ->
      result =
        ctx.source_stream
        |> Lazy.stream_map(&transform_record/1)
        |> Lazy.stream_batch(500, &load_batch/1)
        |> Lazy.stream_collect(settle: true)

      {:ok, %{
        processed: length(result.ok),
        errors: length(result.errors)
      }}
    end)
    |> Pipeline.run()
  end

  defp transform_record(record) do
    # Transform logic
    {:ok, %{
      id: record.id,
      data: process_data(record.data),
      transformed_at: DateTime.utc_now()
    }}
  end

  defp load_batch(records) do
    case Repo.insert_all(TransformedRecord, records) do
      {count, _} -> {:ok, count}
    end
  end
end
```

---

## Performance Tips

### 1. Use Appropriate Batch Sizes

```elixir
# Too small - overhead per batch
|> Lazy.stream_batch(10, ...)  # Many small batches

# Too large - memory pressure
|> Lazy.stream_batch(100_000, ...)  # Few huge batches

# Just right - balance throughput and memory
|> Lazy.stream_batch(1000, ...)
```

### 2. Prefer stream_reduce Over stream_collect

```elixir
# BAD - collects all into memory first
stream
|> Lazy.stream_collect()
|> then(fn {:ok, items} -> Enum.sum(items) end)

# GOOD - processes incrementally
stream
|> Lazy.stream_reduce(0, fn item, acc -> {:ok, acc + item} end)
```

### 3. Skip Errors Early

```elixir
# Process failures early, don't carry them
stream
|> Lazy.stream(on_error: :skip)  # Skip at source
|> Lazy.stream_map(...)
|> Lazy.stream_collect()
```

### 4. Use Database Cursors for Large Tables

```elixir
# BAD - loads all IDs into memory
User
|> Repo.all()
|> Lazy.stream(&process/1)

# GOOD - cursor-based pagination
Lazy.paginate(
  fn cursor ->
    from(u in User, where: u.id > ^(cursor || 0), limit: 1000)
    |> Repo.all()
    |> then(fn users ->
      {:ok, %{items: users, next: List.last(users)[:id]}}
    end)
  end,
  & &1.next,
  get_items: & &1.items
)
```

---

## Comparison with Alternatives

| Approach | Memory | Latency | Use Case |
|----------|--------|---------|----------|
| `Enum.map` | O(n) | Blocking | Small lists |
| `Stream.map` | O(1) | Lazy | Large lists, no errors |
| `Lazy.stream` | O(1) | Lazy | Large lists with Result |
| `Task.async_stream` | O(batch) | Parallel | CPU-bound parallel |
| `AsyncResult.parallel` | O(n) | Parallel | Mixed Results |

### When to Use What

```elixir
# Small list, simple transform
Enum.map(items, &transform/1)

# Large list, no error handling needed
items
|> Stream.map(&transform/1)
|> Enum.to_list()

# Large list with Result error handling
items
|> Lazy.stream(&transform/1)
|> Lazy.stream_collect()

# Parallel processing with Results
AsyncResult.parallel_map(items, &transform/1, max_concurrency: 10)
```
