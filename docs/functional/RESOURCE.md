# Events.Types.Resource

Safe resource management with guaranteed cleanup.

## Overview

`Resource` provides a structured way to manage resources that need cleanup, ensuring resources are always released even when errors occur. This is similar to:

- Java's try-with-resources
- Python's context managers (`with` statement)
- Haskell's bracket pattern

```elixir
alias Events.Types.Resource

# File is always closed, even if reading fails
Resource.with_file("data.txt", [:read], fn file ->
  IO.read(file, :eof)
end)
#=> {:ok, "file contents..."}
```

## The Problem

Without proper resource management:

```elixir
# BAD: Resource leak if processing fails
file = File.open!("data.txt")
result = process(file)  # What if this raises?
File.close(file)        # Never reached!
result
```

With Resource:

```elixir
# GOOD: File always closed
Resource.with_resource(
  fn -> File.open!("data.txt") end,
  fn file -> File.close(file) end,
  fn file -> process(file) end
)
```

## Resource Lifecycle

1. **Acquire** - Obtain the resource (open file, connect to DB, etc.)
2. **Use** - Work with the resource
3. **Release** - Clean up the resource (close file, disconnect, etc.)

The release function is **always** called, even if:
- The use function raises an exception
- The use function returns an error tuple
- The acquire function fails (release won't be called in this case)

## Core Functions

### with_resource/3

The fundamental pattern:

```elixir
Resource.with_resource(
  fn -> acquire_resource() end,    # Acquire
  fn resource -> release(resource) end,  # Release (always called)
  fn resource -> use(resource) end       # Use
)
```

```elixir
# Database connection
Resource.with_resource(
  fn -> DB.connect(config) end,
  fn conn -> DB.disconnect(conn) end,
  fn conn -> DB.query(conn, "SELECT * FROM users") end
)

# Lock management
Resource.with_resource(
  fn -> acquire_lock(key) end,
  fn lock -> release_lock(lock) end,
  fn lock -> critical_section(lock) end
)
```

### bracket/3

Alias for `with_resource/3`, named after Haskell's bracket pattern:

```elixir
Resource.bracket(
  fn -> open() end,
  fn r -> close(r) end,
  fn r -> use(r) end
)
```

## Multiple Resources

Manage multiple resources with guaranteed cleanup in LIFO order (last acquired, first released):

```elixir
Resource.with_resources([
  {fn -> File.open!("input.txt") end, &File.close/1},
  {fn -> File.open!("output.txt", [:write]) end, &File.close/1}
], fn [input, output] ->
  data = IO.read(input, :eof)
  IO.write(output, String.upcase(data))
end)
```

If any acquisition fails, previously acquired resources are released:

```elixir
Resource.with_resources([
  {fn -> connect_db() end, &disconnect/1},
  {fn -> raise "Connection failed!" end, &close/1},  # Fails
  {fn -> connect_cache() end, &close/1}               # Never called
], fn [db, _, cache] ->
  # Never reached
end)
# DB is properly disconnected despite failure
```

## Reusable Resource Definitions

Define resources once, use them anywhere:

```elixir
# Define a resource type
db_resource = Resource.define(
  acquire: fn -> DB.connect(config) end,
  release: fn conn -> DB.disconnect(conn) end
)

# Use it multiple times
Resource.using(db_resource, fn conn ->
  DB.query(conn, "SELECT 1")
end)

Resource.using(db_resource, fn conn ->
  DB.insert(conn, data)
end)
```

## Specialized Resources

### File Operations

```elixir
# Read file with auto-close
Resource.with_file("data.txt", [:read], fn file ->
  IO.read(file, :eof)
end)
#=> {:ok, "contents..."}

# Write file
Resource.with_file("output.txt", [:write], fn file ->
  IO.write(file, "Hello!")
end)
```

### Temporary Files

```elixir
# File is deleted after use
Resource.with_temp_file(fn path ->
  File.write!(path, "temp data")
  result = process_file(path)
  result
end)
# File automatically deleted
```

### Temporary Directories

```elixir
# Directory and all contents deleted after use
Resource.with_temp_dir(fn dir ->
  File.write!(Path.join(dir, "file1.txt"), "data1")
  File.write!(Path.join(dir, "file2.txt"), "data2")
  process_directory(dir)
end)
# Entire directory removed
```

### Processes

```elixir
# Process is killed after use
Resource.with_process(
  fn ->
    spawn(fn ->
      receive do
        :work -> do_work()
      end
    end)
  end,
  fn pid ->
    send(pid, :work)
    receive_result()
  end
)
# Process automatically terminated
```

### ETS Tables

```elixir
# Table is deleted after use
Resource.with_ets(:my_table, [:set, :public], fn table ->
  :ets.insert(table, {:key, "value"})
  :ets.lookup(table, :key)
end)
#=> {:ok, [key: "value"]}
# Table automatically deleted
```

### Agents

```elixir
# Agent is stopped after use
Resource.with_agent(fn -> %{count: 0} end, fn agent ->
  Agent.update(agent, &Map.update!(&1, :count, fn c -> c + 1 end))
  Agent.get(agent, & &1)
end)
#=> {:ok, %{count: 1}}
# Agent automatically stopped
```

## Utility Functions

### ensure/2

Like try/after but returns a Result:

```elixir
Resource.ensure(
  fn -> risky_operation() end,
  fn -> cleanup() end
)
```

### with_timeout/3

Run operation with timeout, cleanup on timeout:

```elixir
Resource.with_timeout(
  fn -> slow_operation() end,
  fn -> cancel_operation() end,
  5000  # 5 second timeout
)
#=> {:ok, result} or {:error, :timeout}
```

### with_resource_safe/3

Catch all exceptions and return error tuple instead of raising:

```elixir
Resource.with_resource_safe(
  fn -> open() end,
  fn r -> close(r) end,
  fn r -> might_fail(r) end
)
#=> {:ok, result} or {:error, {:exception, %RuntimeError{...}}}
#=> {:error, {:exit, reason}}
#=> {:error, {:throw, value}}
```

## Return Values

All resource functions return Result tuples:

```elixir
{:ok, result}                    # Success
{:error, {:acquire_failed, e}}   # Acquisition failed
{:error, reason}                 # Use function returned error

# Exceptions in use function are re-raised after cleanup
```

The `wrap_result` helper normalizes returns:

```elixir
{:ok, value}  -> {:ok, value}      # Passed through
{:error, r}   -> {:error, r}       # Passed through
:ok           -> {:ok, :ok}        # Wrapped
other         -> {:ok, other}      # Wrapped
```

## Real-World Examples

### Database Transaction Pattern

```elixir
defmodule TransactionHelper do
  alias Events.Types.Resource

  def with_transaction(repo, fun) do
    Resource.with_resource(
      fn ->
        {:ok, _} = repo.transaction(fn -> :started end)
        :transaction
      end,
      fn :transaction ->
        # Ecto handles commit/rollback automatically
        :ok
      end,
      fn :transaction ->
        fun.()
      end
    )
  end
end
```

### Connection Pool

```elixir
defmodule PooledConnection do
  alias Events.Types.Resource

  def with_connection(pool, fun) do
    Resource.with_resource(
      fn -> :poolboy.checkout(pool) end,
      fn worker -> :poolboy.checkin(pool, worker) end,
      fun
    )
  end

  # Multiple pooled resources
  def with_connections(pools, fun) do
    resources = Enum.map(pools, fn pool ->
      {fn -> :poolboy.checkout(pool) end,
       fn worker -> :poolboy.checkin(pool, worker) end}
    end)

    Resource.with_resources(resources, fun)
  end
end
```

### File Processing Pipeline

```elixir
defmodule FileProcessor do
  alias Events.Types.Resource

  def process_and_archive(input_path, output_path, archive_path) do
    Resource.with_resources([
      {fn -> File.open!(input_path, [:read]) end, &File.close/1},
      {fn -> File.open!(output_path, [:write]) end, &File.close/1},
      {fn -> File.open!(archive_path, [:write, :compressed]) end, &File.close/1}
    ], fn [input, output, archive] ->
      data = IO.read(input, :eof)
      processed = transform(data)

      IO.write(output, processed)
      IO.write(archive, data)

      {:ok, byte_size(processed)}
    end)
  end
end
```

### Distributed Lock

```elixir
defmodule DistributedLock do
  alias Events.Types.Resource

  def with_lock(key, timeout \\ 5000, fun) do
    Resource.with_timeout(
      fn ->
        Resource.with_resource(
          fn -> acquire_distributed_lock(key) end,
          fn lock -> release_distributed_lock(lock) end,
          fun
        )
      end,
      fn -> force_release_lock(key) end,
      timeout
    )
  end

  defp acquire_distributed_lock(key) do
    # Redis/etcd/Consul lock acquisition
    {:ok, lock_id} = LockService.acquire(key)
    {key, lock_id}
  end

  defp release_distributed_lock({key, lock_id}) do
    LockService.release(key, lock_id)
  end

  defp force_release_lock(key) do
    LockService.force_release(key)
  end
end
```

### Test Fixtures

```elixir
defmodule TestHelpers do
  alias Events.Types.Resource

  def with_test_user(attrs \\ %{}, fun) do
    Resource.with_resource(
      fn -> create_test_user(attrs) end,
      fn user -> delete_test_user(user) end,
      fun
    )
  end

  def with_test_data(fixtures, fun) do
    resources = Enum.map(fixtures, fn {type, attrs} ->
      {fn -> create_fixture(type, attrs) end,
       fn fixture -> cleanup_fixture(fixture) end}
    end)

    Resource.with_resources(resources, fun)
  end
end

# In tests
test "user can place order" do
  TestHelpers.with_test_data([
    {:user, %{name: "Alice"}},
    {:product, %{name: "Widget", price: 100}}
  ], fn [user, product] ->
    assert {:ok, order} = Orders.create(user, product)
    assert order.total == 100
  end)
end
```

## Function Reference

| Function | Description |
|----------|-------------|
| `with_resource/3` | Core acquire/use/release pattern |
| `bracket/3` | Alias for with_resource |
| `with_resources/2` | Multiple resources with LIFO release |
| `define/1` | Create reusable resource definition |
| `using/2` | Use a defined resource |
| `with_file/3` | File with auto-close |
| `with_temp_file/1` | Temp file with auto-delete |
| `with_temp_dir/1` | Temp directory with auto-delete |
| `with_process/2` | Process with auto-kill |
| `with_ets/3` | ETS table with auto-delete |
| `with_agent/2` | Agent with auto-stop |
| `with_resource_safe/3` | Catch all errors as tuples |
| `ensure/2` | Run with guaranteed cleanup |
| `with_timeout/3` | Run with timeout and cleanup |
