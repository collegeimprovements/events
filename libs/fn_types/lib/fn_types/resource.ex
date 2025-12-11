defmodule FnTypes.Resource do
  @moduledoc """
  Safe resource management with guaranteed cleanup.

  Resource provides a structured way to manage resources that need cleanup,
  ensuring resources are always released even when errors occur (like try-with-resources
  in Java or Python's context managers).

  ## Quick Start

      alias FnTypes.Resource

      # Basic file resource
      Resource.with_resource(
        fn -> File.open!("data.txt", [:read]) end,
        fn file -> File.close(file) end,
        fn file ->
          IO.read(file, :all)
        end
      )
      #=> {:ok, "file contents..."}

  ## Resource Lifecycle

  1. **Acquire** - Obtain the resource (open file, connect to DB, etc.)
  2. **Use** - Work with the resource
  3. **Release** - Clean up the resource (close file, disconnect, etc.)

  The release function is **always** called, even if:
  - The use function raises an exception
  - The use function returns an error tuple
  - The acquire function fails (release won't be called in this case)

  ## Core Functions

  | Function | Description |
  |----------|-------------|
  | `with_resource/3` | Acquire, use, and release a resource |
  | `with_resources/2` | Manage multiple resources |
  | `bracket/3` | Alias for with_resource |
  | `using/2` | Use a pre-built resource definition |

  ## Defining Reusable Resources

      # Define a resource type
      defmodule MyApp.Resources.DbConnection do
        alias FnTypes.Resource

        def resource(config) do
          Resource.define(
            acquire: fn -> MyApp.DB.connect(config) end,
            release: fn conn -> MyApp.DB.disconnect(conn) end
          )
        end
      end

      # Use it
      Resource.using(MyApp.Resources.DbConnection.resource(config), fn conn ->
        MyApp.DB.query(conn, "SELECT * FROM users")
      end)

  ## Multiple Resources

      # Resources are acquired in order and released in reverse order
      Resource.with_resources([
        {fn -> File.open!("input.txt") end, &File.close/1},
        {fn -> File.open!("output.txt", [:write]) end, &File.close/1}
      ], fn [input, output] ->
        data = IO.read(input, :all)
        IO.write(output, String.upcase(data))
      end)

  ## Error Handling

  The resource pattern ensures cleanup happens regardless of errors:

      Resource.with_resource(
        fn -> open_connection() end,
        fn conn -> close_connection(conn) end,
        fn conn ->
          # Even if this raises, close_connection will be called
          risky_operation(conn)
        end
      )

  ## Integration with Result

      alias FnTypes.{Resource, Result}

      # Chain resource operations
      result = Resource.with_resource(
        fn -> File.open("data.json") end,
        fn {:ok, f} -> File.close(f); _ -> :ok end,
        fn
          {:ok, file} ->
            file
            |> IO.read(:all)
            |> Jason.decode()

          {:error, reason} ->
            {:error, reason}
        end
      )

  ## Common Patterns

  ### Database Transactions

      Resource.with_resource(
        fn -> Repo.checkout(fn -> :ok end) end,
        fn _ -> :ok end,  # checkout handles cleanup
        fn _ ->
          Repo.transaction(fn ->
            # transaction work
          end)
        end
      )

  ### Temporary Files

      Resource.with_resource(
        fn -> Temp.open!("prefix") end,
        fn {path, _io} -> File.rm(path) end,
        fn {_path, io} ->
          IO.write(io, "temp data")
          # ... work with temp file
        end
      )

  ### Lock Management

      Resource.with_resource(
        fn -> acquire_lock(key) end,
        fn lock -> release_lock(lock) end,
        fn lock ->
          critical_section(lock)
        end
      )
  """

  alias FnTypes.Result

  # ============================================================================
  # Types
  # ============================================================================

  @type acquire :: (-> resource)
  @type release :: (resource -> any())
  @type use_fn :: (resource -> result)
  @type resource :: any()
  @type result :: any()

  @type resource_def :: %{
          acquire: acquire(),
          release: release()
        }

  @type resource_tuple :: {acquire(), release()}

  # ============================================================================
  # Core Functions
  # ============================================================================

  @doc """
  Executes a function with a resource, ensuring cleanup.

  The resource is acquired, passed to the use function, and then released.
  The release function is **always** called, even if the use function raises.

  ## Arguments

  - `acquire` - Zero-arity function that acquires the resource
  - `release` - Function that releases/cleans up the resource
  - `use_fn` - Function that uses the resource

  ## Returns

  - `{:ok, result}` - If use_fn succeeds
  - `{:error, reason}` - If acquire or use_fn fails
  - Re-raises if use_fn raises (after releasing)

  ## Examples

      # File resource
      Resource.with_resource(
        fn -> File.open!("data.txt") end,
        fn file -> File.close(file) end,
        fn file -> IO.read(file, :all) end
      )
      #=> {:ok, "contents..."}

      # Connection resource
      Resource.with_resource(
        fn -> DB.connect(config) end,
        fn conn -> DB.disconnect(conn) end,
        fn conn -> DB.query(conn, "SELECT 1") end
      )
  """
  @spec with_resource(acquire(), release(), use_fn()) :: Result.t(any(), any())
  def with_resource(acquire, release, use_fn)
      when is_function(acquire, 0) and is_function(release, 1) and is_function(use_fn, 1) do
    case safe_acquire(acquire) do
      {:ok, resource} ->
        do_with_resource(resource, release, use_fn)

      {:error, _} = error ->
        error
    end
  end

  defp safe_acquire(acquire) do
    {:ok, acquire.()}
  rescue
    e -> {:error, {:acquire_failed, e}}
  end

  defp do_with_resource(resource, release, use_fn) do
    try do
      result = use_fn.(resource)
      wrap_result(result)
    rescue
      e ->
        release.(resource)
        reraise e, __STACKTRACE__
    else
      result ->
        release.(resource)
        result
    end
  end

  @doc """
  Alias for `with_resource/3`.

  Named after Haskell's bracket pattern.

  ## Examples

      Resource.bracket(
        fn -> acquire() end,
        fn r -> release(r) end,
        fn r -> use(r) end
      )
  """
  @spec bracket(acquire(), release(), use_fn()) :: Result.t(any(), any())
  def bracket(acquire, release, use_fn) do
    with_resource(acquire, release, use_fn)
  end

  @doc """
  Manages multiple resources with guaranteed cleanup.

  Resources are acquired in order and released in **reverse order**
  (LIFO - last acquired, first released).

  ## Arguments

  - `resources` - List of `{acquire_fn, release_fn}` tuples
  - `use_fn` - Function that receives list of acquired resources

  ## Examples

      # Multiple files
      Resource.with_resources([
        {fn -> File.open!("in.txt") end, &File.close/1},
        {fn -> File.open!("out.txt", [:write]) end, &File.close/1}
      ], fn [input, output] ->
        data = IO.read(input, :all)
        IO.write(output, data)
      end)

      # Connection pool
      Resource.with_resources([
        {fn -> get_db_conn() end, &release_conn/1},
        {fn -> get_cache_conn() end, &release_conn/1},
        {fn -> get_queue_conn() end, &release_conn/1}
      ], fn [db, cache, queue] ->
        # Use all connections
      end)
  """
  @spec with_resources([resource_tuple()], ([resource()] -> result())) :: Result.t(any(), any())
  def with_resources(resources, use_fn) when is_list(resources) and is_function(use_fn, 1) do
    case acquire_all_safe(resources, []) do
      {:ok, acquired} ->
        # acquired is in LIFO order (last acquired first)
        resources_in_order = Enum.reverse(acquired)

        try do
          result = use_fn.(Enum.map(resources_in_order, fn {r, _} -> r end))
          wrap_result(result)
        rescue
          e ->
            release_all(acquired)
            reraise e, __STACKTRACE__
        else
          result ->
            release_all(acquired)
            result
        end

      {:error, _} = error ->
        error
    end
  end

  # Acquires all resources, returns {:ok, acquired} or {:error, reason}
  # If acquisition fails, releases already acquired resources
  defp acquire_all_safe([], acquired), do: {:ok, acquired}

  defp acquire_all_safe([{acquire, release} | rest], acquired) do
    case safe_acquire(acquire) do
      {:ok, resource} ->
        acquire_all_safe(rest, [{resource, release} | acquired])

      {:error, _} = error ->
        # Release already acquired resources
        release_all(acquired)
        error
    end
  end

  defp release_all(resources) do
    # Release in reverse order (LIFO)
    Enum.each(resources, fn {resource, release} ->
      try do
        release.(resource)
      rescue
        # Ignore release errors
        _ -> :ok
      end
    end)
  end

  # ============================================================================
  # Resource Definitions
  # ============================================================================

  @doc """
  Defines a reusable resource.

  ## Options

  - `:acquire` - Function to acquire the resource
  - `:release` - Function to release the resource

  ## Examples

      # Define a resource type
      file_resource = Resource.define(
        acquire: fn -> File.open!("data.txt") end,
        release: fn f -> File.close(f) end
      )

      # Use it later
      Resource.using(file_resource, fn file ->
        IO.read(file, :all)
      end)
  """
  @spec define(keyword()) :: resource_def()
  def define(opts) when is_list(opts) do
    acquire = Keyword.fetch!(opts, :acquire)
    release = Keyword.fetch!(opts, :release)

    %{acquire: acquire, release: release}
  end

  @doc """
  Uses a pre-defined resource.

  ## Examples

      db_resource = Resource.define(
        acquire: fn -> DB.connect() end,
        release: fn c -> DB.disconnect(c) end
      )

      Resource.using(db_resource, fn conn ->
        DB.query(conn, "SELECT * FROM users")
      end)
  """
  @spec using(resource_def(), use_fn()) :: Result.t(any(), any())
  def using(%{acquire: acquire, release: release}, use_fn) when is_function(use_fn, 1) do
    with_resource(acquire, release, use_fn)
  end

  # ============================================================================
  # Specialized Resources
  # ============================================================================

  @doc """
  Creates a file resource that auto-closes.

  ## Examples

      Resource.with_file("data.txt", [:read], fn file ->
        IO.read(file, :all)
      end)
      #=> {:ok, "contents..."}

      Resource.with_file("output.txt", [:write], fn file ->
        IO.write(file, "Hello!")
      end)
  """
  @spec with_file(Path.t(), [File.mode()], (File.io_device() -> result())) ::
          Result.t(any(), any())
  def with_file(path, modes \\ [], use_fn) when is_function(use_fn, 1) do
    with_resource(
      fn -> File.open!(path, modes) end,
      fn file -> File.close(file) end,
      use_fn
    )
  end

  @doc """
  Creates a temporary file resource that auto-deletes.

  ## Examples

      Resource.with_temp_file(fn path ->
        File.write!(path, "temp data")
        File.read!(path)
      end)
      #=> {:ok, "temp data"}
      # File is deleted after use
  """
  @spec with_temp_file((Path.t() -> result())) :: Result.t(any(), any())
  def with_temp_file(use_fn) when is_function(use_fn, 1) do
    with_resource(
      fn ->
        path = System.tmp_dir!() |> Path.join("resource_#{:erlang.unique_integer([:positive])}")
        File.touch!(path)
        path
      end,
      fn path -> File.rm(path) end,
      use_fn
    )
  end

  @doc """
  Creates a temporary directory resource that auto-deletes.

  ## Examples

      Resource.with_temp_dir(fn dir ->
        File.write!(Path.join(dir, "file.txt"), "data")
        # ... work in temp dir
      end)
      #=> {:ok, result}
      # Directory and contents deleted after use
  """
  @spec with_temp_dir((Path.t() -> result())) :: Result.t(any(), any())
  def with_temp_dir(use_fn) when is_function(use_fn, 1) do
    with_resource(
      fn ->
        path = System.tmp_dir!() |> Path.join("resource_dir_#{:erlang.unique_integer([:positive])}")
        File.mkdir_p!(path)
        path
      end,
      fn path -> File.rm_rf(path) end,
      use_fn
    )
  end

  @doc """
  Creates a process resource (spawns and auto-kills).

  ## Examples

      Resource.with_process(fn ->
        spawn_link(fn -> Process.sleep(:infinity) end)
      end, fn pid ->
        send(pid, :work)
        receive do
          :done -> :ok
        after
          5000 -> :timeout
        end
      end)
  """
  @spec with_process((-> pid()), (pid() -> result())) :: Result.t(any(), any())
  def with_process(spawn_fn, use_fn)
      when is_function(spawn_fn, 0) and is_function(use_fn, 1) do
    with_resource(
      spawn_fn,
      fn pid ->
        if Process.alive?(pid) do
          Process.exit(pid, :shutdown)
        end
      end,
      use_fn
    )
  end

  @doc """
  Creates an ETS table resource that auto-deletes.

  ## Examples

      Resource.with_ets(:my_table, [:set, :public], fn table ->
        :ets.insert(table, {:key, "value"})
        :ets.lookup(table, :key)
      end)
      #=> {:ok, [key: "value"]}
  """
  @spec with_ets(atom(), [:ets.type() | :ets.option()], (:ets.table() -> result())) ::
          Result.t(any(), any())
  def with_ets(name, opts \\ [:set], use_fn) when is_atom(name) and is_function(use_fn, 1) do
    with_resource(
      fn -> :ets.new(name, opts) end,
      fn table -> :ets.delete(table) end,
      use_fn
    )
  end

  @doc """
  Creates an Agent resource that auto-stops.

  ## Examples

      Resource.with_agent(fn -> %{count: 0} end, fn agent ->
        Agent.update(agent, fn state -> %{state | count: state.count + 1} end)
        Agent.get(agent, & &1)
      end)
      #=> {:ok, %{count: 1}}
  """
  @spec with_agent((-> any()), (pid() -> result())) :: Result.t(any(), any())
  def with_agent(initial_fn, use_fn) when is_function(initial_fn, 0) and is_function(use_fn, 1) do
    with_resource(
      fn ->
        {:ok, pid} = Agent.start_link(initial_fn)
        pid
      end,
      fn pid -> Agent.stop(pid) end,
      use_fn
    )
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Wraps the use function result, catching errors.

  Returns `{:ok, result}` for success, `{:error, reason}` for errors.

  ## Examples

      Resource.with_resource_safe(
        fn -> open() end,
        fn r -> close(r) end,
        fn r -> might_fail(r) end
      )
      #=> {:ok, result} or {:error, reason}
  """
  @spec with_resource_safe(acquire(), release(), use_fn()) :: Result.t(any(), any())
  def with_resource_safe(acquire, release, use_fn) do
    resource = acquire.()
    do_with_resource_safe(resource, release, use_fn)
  rescue
    e ->
      {:error, {:acquire_failed, e}}
  end

  defp do_with_resource_safe(resource, release, use_fn) do
    try do
      result = use_fn.(resource)
      wrap_result(result)
    rescue
      e ->
        release.(resource)
        {:error, {:exception, e}}
    catch
      :exit, reason ->
        release.(resource)
        {:error, {:exit, reason}}

      :throw, value ->
        release.(resource)
        {:error, {:throw, value}}
    else
      result ->
        release.(resource)
        result
    end
  end

  @doc """
  Ensures a cleanup function runs regardless of result.

  Like `try/after` but returns a Result.

  ## Examples

      Resource.ensure(
        fn -> risky_operation() end,
        fn -> cleanup() end
      )
  """
  @spec ensure((-> result()), (-> any())) :: Result.t(any(), any())
  def ensure(operation, cleanup) when is_function(operation, 0) and is_function(cleanup, 0) do
    try do
      result = operation.()
      wrap_result(result)
    after
      cleanup.()
    end
  end

  @doc """
  Runs an operation with a timeout, cleaning up if it times out.

  ## Examples

      Resource.with_timeout(
        fn -> slow_operation() end,
        fn -> cancel_operation() end,
        5000
      )
  """
  @spec with_timeout((-> result()), (-> any()), timeout()) :: Result.t(any(), any())
  def with_timeout(operation, cleanup, timeout)
      when is_function(operation, 0) and is_function(cleanup, 0) and is_integer(timeout) do
    task = Task.async(operation)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        wrap_result(result)

      nil ->
        cleanup.()
        {:error, :timeout}

      {:exit, reason} ->
        cleanup.()
        {:error, {:exit, reason}}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp wrap_result({:ok, _} = result), do: result
  defp wrap_result({:error, _} = result), do: result
  defp wrap_result(:ok), do: {:ok, :ok}
  defp wrap_result(result), do: {:ok, result}
end
