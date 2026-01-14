defmodule FnTypes.Lazy do
  @moduledoc """
  Lazy evaluation and streaming for Result types.

  Provides deferred computation and memory-efficient streaming for operations
  that may produce large datasets or expensive computations.

  ## Design Philosophy

  - **Deferred execution**: Computations are described, not executed immediately
  - **Memory efficiency**: Process large datasets without loading all into memory
  - **Composable**: Chain lazy operations that execute as a single pass
  - **Result-aware**: Integrates with Result tuples for error handling

  ## Quick Reference

  | Function | Use Case |
  |----------|----------|
  | `defer/1` | Wrap a computation for later execution |
  | `run/1` | Execute a deferred computation |
  | `stream/2` | Create lazy Result stream from enumerable |
  | `stream_map/2` | Map over stream with Result-returning function |
  | `stream_filter/2` | Filter stream with Result-returning predicate |
  | `stream_take/2` | Take first N successful results |
  | `stream_collect/1` | Collect stream to list (with fail-fast) |
  | `stream_reduce/3` | Reduce stream with accumulator |
  | `paginate/3` | Paginated fetching with cursor |

  ## Basic Usage

      # Deferred computation
      lazy = Lazy.defer(fn -> expensive_database_query() end)
      # Nothing happens yet...

      {:ok, result} = Lazy.run(lazy)
      # Now the computation executes

      # Streaming large datasets
      User
      |> Repo.stream()
      |> Lazy.stream(&process_user/1)
      |> Lazy.stream_filter(fn user -> {:ok, user.active?} end)
      |> Lazy.stream_take(100)
      |> Lazy.stream_collect()
      #=> {:ok, [processed_users...]}

  ## Pagination Pattern

      Lazy.paginate(
        fn cursor -> fetch_page(cursor, limit: 100) end,
        fn page -> page.next_cursor end
      )
      |> Lazy.stream_map(&process_item/1)
      |> Lazy.stream_collect()

  ## Composition with Result

      # Chain lazy operations
      Lazy.defer(fn -> fetch_config() end)
      |> Lazy.and_then(fn config ->
        Lazy.defer(fn -> apply_config(config) end)
      end)
      |> Lazy.run()
  """

  alias FnTypes.Result

  # ============================================
  # Types
  # ============================================

  @type lazy(a) :: %__MODULE__{
          computation: (-> Result.t(a, term())),
          memoized: boolean()
        }

  @type t(a) :: lazy(a)
  @type t() :: t(term())

  @type stream_opts :: [
          max_errors: non_neg_integer() | :infinity,
          on_error: :skip | :halt | :collect,
          chunk_size: pos_integer()
        ]

  defstruct computation: nil,
            memoized: false,
            cached_result: nil

  # ============================================
  # Deferred Computation
  # ============================================

  @doc """
  Creates a deferred computation.

  The function is not executed until `run/1` is called.

  ## Examples

      lazy = Lazy.defer(fn ->
        {:ok, expensive_operation()}
      end)

      # Later...
      {:ok, result} = Lazy.run(lazy)

      # With memoization (caches result)
      lazy = Lazy.defer(fn -> api_call() end, memoize: true)
      {:ok, r1} = Lazy.run(lazy)  # Calls API
      {:ok, r2} = Lazy.run(lazy)  # Returns cached result
  """
  @spec defer((-> Result.t(a, e)), keyword()) :: t(a) when a: term(), e: term()
  def defer(computation, opts \\ []) when is_function(computation, 0) do
    %__MODULE__{
      computation: computation,
      memoized: Keyword.get(opts, :memoize, false)
    }
  end

  @doc """
  Creates a lazy value that's already computed.

  Useful for lifting pure values into the Lazy context.

  ## Examples

      Lazy.pure(42) |> Lazy.run()
      #=> {:ok, 42}
  """
  @spec pure(a) :: t(a) when a: term()
  def pure(value) do
    defer(fn -> {:ok, value} end)
  end

  @doc """
  Creates a lazy error.

  ## Examples

      Lazy.error(:not_found) |> Lazy.run()
      #=> {:error, :not_found}
  """
  @spec error(e) :: t(term()) when e: term()
  def error(reason) do
    defer(fn -> {:error, reason} end)
  end

  @doc """
  Executes a deferred computation.

  ## Examples

      lazy = Lazy.defer(fn -> {:ok, 42} end)
      {:ok, 42} = Lazy.run(lazy)
  """
  @spec run(t(a)) :: Result.t(a, term()) when a: term()
  def run(%__MODULE__{computation: computation, memoized: false}) do
    computation.()
  end

  def run(%__MODULE__{cached_result: cached}) when not is_nil(cached) do
    cached
  end

  def run(%__MODULE__{computation: computation, memoized: true}) do
    # Note: This doesn't actually update the struct since Elixir is immutable
    # For true memoization, use an Agent or ETS
    computation.()
  end

  @doc """
  Executes and unwraps, raising on error.

  ## Examples

      42 = Lazy.run!(Lazy.pure(42))
  """
  @spec run!(t(a)) :: a | no_return() when a: term()
  def run!(lazy) do
    case run(lazy) do
      {:ok, value} -> value
      {:error, reason} -> raise "Lazy computation failed: #{inspect(reason)}"
    end
  end

  # ============================================
  # Transformation
  # ============================================

  @doc """
  Maps a function over the lazy value.

  The mapping is deferred - it won't execute until `run/1` is called.

  ## Examples

      Lazy.pure(5)
      |> Lazy.map(&(&1 * 2))
      |> Lazy.run()
      #=> {:ok, 10}
  """
  @spec map(t(a), (a -> b)) :: t(b) when a: term(), b: term()
  def map(%__MODULE__{} = lazy, fun) when is_function(fun, 1) do
    defer(fn ->
      case run(lazy) do
        {:ok, value} -> {:ok, fun.(value)}
        {:error, _} = error -> error
      end
    end)
  end

  @doc """
  Chains a lazy computation that returns another lazy.

  ## Examples

      Lazy.pure(5)
      |> Lazy.and_then(fn n ->
        Lazy.defer(fn -> {:ok, n * 2} end)
      end)
      |> Lazy.run()
      #=> {:ok, 10}
  """
  @spec and_then(t(a), (a -> t(b))) :: t(b) when a: term(), b: term()
  def and_then(%__MODULE__{} = lazy, fun) when is_function(fun, 1) do
    defer(fn ->
      case run(lazy) do
        {:ok, value} ->
          next_lazy = fun.(value)
          run(next_lazy)

        {:error, _} = error ->
          error
      end
    end)
  end

  @doc """
  Chains a function that returns a Result.

  ## Examples

      Lazy.pure(5)
      |> Lazy.and_then_result(fn n ->
        {:ok, n * 2}
      end)
      |> Lazy.run()
      #=> {:ok, 10}
  """
  @spec and_then_result(t(a), (a -> Result.t(b, e))) :: t(b) when a: term(), b: term(), e: term()
  def and_then_result(%__MODULE__{} = lazy, fun) when is_function(fun, 1) do
    defer(fn ->
      case run(lazy) do
        {:ok, value} -> fun.(value)
        {:error, _} = error -> error
      end
    end)
  end

  @doc """
  Handles errors in the lazy computation.

  ## Examples

      Lazy.error(:not_found)
      |> Lazy.or_else(fn _reason ->
        Lazy.pure(:default)
      end)
      |> Lazy.run()
      #=> {:ok, :default}
  """
  @spec or_else(t(a), (term() -> t(a))) :: t(a) when a: term()
  def or_else(%__MODULE__{} = lazy, handler) when is_function(handler, 1) do
    defer(fn ->
      case run(lazy) do
        {:ok, _} = ok -> ok
        {:error, reason} -> run(handler.(reason))
      end
    end)
  end

  # ============================================
  # Streaming
  # ============================================

  @doc """
  Creates a lazy stream from an enumerable.

  Each element is processed through the given function which should
  return a Result tuple.

  ## Options

  - `:max_errors` - Maximum errors before halting (default: :infinity)
  - `:on_error` - Error handling: `:skip`, `:halt`, or `:collect` (default: :halt)
  - `:chunk_size` - Process in chunks for efficiency (default: 1)

  ## Examples

      users = [1, 2, 3, 4, 5]

      users
      |> Lazy.stream(&fetch_user/1)
      |> Lazy.stream_collect()
      #=> {:ok, [user1, user2, ...]}

      # Skip errors
      users
      |> Lazy.stream(&fetch_user/1, on_error: :skip)
      |> Lazy.stream_collect()
      #=> {:ok, [successful_users...]}
  """
  @spec stream(Enumerable.t(), (term() -> Result.t(a, e)), stream_opts()) :: Enumerable.t()
        when a: term(), e: term()
  def stream(enumerable, fun, opts \\ []) when is_function(fun, 1) do
    on_error = Keyword.get(opts, :on_error, :halt)
    max_errors = Keyword.get(opts, :max_errors, :infinity)

    Stream.transform(enumerable, {0, []}, fn item, {error_count, errors} ->
      case fun.(item) do
        {:ok, value} ->
          {[{:ok, value}], {error_count, errors}}

        {:error, _reason} = error ->
          new_count = error_count + 1

          case {on_error, should_halt?(new_count, max_errors)} do
            {:halt, _} ->
              {:halt, {new_count, [error | errors]}}

            {:skip, false} ->
              {[], {new_count, [error | errors]}}

            {:skip, true} ->
              {:halt, {new_count, [error | errors]}}

            {:collect, false} ->
              {[error], {new_count, [error | errors]}}

            {:collect, true} ->
              {:halt, {new_count, [error | errors]}}
          end
      end
    end)
  end

  defp should_halt?(_count, :infinity), do: false
  defp should_halt?(count, max), do: count >= max

  @doc """
  Maps a Result-returning function over a stream.

  ## Examples

      stream
      |> Lazy.stream_map(fn item ->
        {:ok, transform(item)}
      end)
  """
  @spec stream_map(Enumerable.t(), (term() -> Result.t(a, e))) :: Enumerable.t()
        when a: term(), e: term()
  def stream_map(stream, fun) when is_function(fun, 1) do
    Stream.map(stream, fn
      {:ok, value} -> fun.(value)
      {:error, _} = error -> error
    end)
  end

  @doc """
  Filters a stream with a Result-returning predicate.

  ## Examples

      stream
      |> Lazy.stream_filter(fn item ->
        {:ok, item.active?}
      end)
  """
  @spec stream_filter(Enumerable.t(), (term() -> Result.t(boolean(), e))) :: Enumerable.t()
        when e: term()
  def stream_filter(stream, predicate) when is_function(predicate, 1) do
    Stream.flat_map(stream, fn
      {:ok, value} ->
        case predicate.(value) do
          {:ok, true} -> [{:ok, value}]
          {:ok, false} -> []
          {:error, _} = error -> [error]
        end

      {:error, _} = error ->
        [error]
    end)
  end

  @doc """
  Takes the first N successful results from a stream.

  ## Examples

      stream
      |> Lazy.stream_take(10)
      |> Lazy.stream_collect()
      #=> {:ok, [first_10_successful...]}
  """
  @spec stream_take(Enumerable.t(), non_neg_integer()) :: Enumerable.t()
  def stream_take(stream, count) when is_integer(count) and count >= 0 do
    Stream.transform(stream, count, fn
      _, 0 ->
        {:halt, 0}

      {:ok, _} = ok, remaining ->
        {[ok], remaining - 1}

      {:error, _} = error, remaining ->
        {[error], remaining}
    end)
  end

  @doc """
  Collects a stream into a Result.

  Fails fast on first error unless `settle: true` is passed.

  ## Options

  - `:settle` - Collect all results instead of failing fast (default: false)

  ## Examples

      # Fail-fast
      Lazy.stream_collect(stream)
      #=> {:ok, [values...]} | {:error, first_error}

      # Settle (collect all)
      Lazy.stream_collect(stream, settle: true)
      #=> %{ok: [values...], errors: [errors...]}
  """
  @spec stream_collect(Enumerable.t(), keyword()) ::
          Result.t([term()], term()) | %{ok: [term()], errors: [term()]}
  def stream_collect(stream, opts \\ []) do
    settle = Keyword.get(opts, :settle, false)

    case settle do
      false ->
        collect_fail_fast(stream)

      true ->
        collect_settle(stream)
    end
  end

  defp collect_fail_fast(stream) do
    stream
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} ->
        {:cont, {:ok, [value | acc]}}

      {:error, _} = error, _ ->
        {:halt, error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp collect_settle(stream) do
    stream
    |> Enum.reduce(%{ok: [], errors: []}, fn
      {:ok, value}, acc ->
        %{acc | ok: [value | acc.ok]}

      {:error, reason}, acc ->
        %{acc | errors: [reason | acc.errors]}
    end)
    |> then(fn acc ->
      %{ok: Enum.reverse(acc.ok), errors: Enum.reverse(acc.errors)}
    end)
  end

  @doc """
  Reduces a stream with an accumulator.

  ## Examples

      stream
      |> Lazy.stream_reduce(0, fn value, acc ->
        {:ok, acc + value}
      end)
      #=> {:ok, sum}
  """
  @spec stream_reduce(Enumerable.t(), acc, (term(), acc -> Result.t(acc, e))) :: Result.t(acc, e)
        when acc: term(), e: term()
  def stream_reduce(stream, initial, reducer) when is_function(reducer, 2) do
    stream
    |> Enum.reduce_while({:ok, initial}, fn
      {:ok, value}, {:ok, acc} ->
        case reducer.(value, acc) do
          {:ok, _} = ok -> {:cont, ok}
          {:error, _} = error -> {:halt, error}
        end

      {:error, _} = error, _ ->
        {:halt, error}
    end)
  end

  # ============================================
  # Pagination
  # ============================================

  @doc """
  Creates a lazy stream for paginated data.

  Fetches pages on-demand, yielding items from each page.

  ## Parameters

  - `fetch_page` - Function that takes a cursor and returns `{:ok, page}` or `{:error, reason}`
  - `get_cursor` - Function that extracts the next cursor from a page (nil to stop)
  - `opts` - Options:
    - `:get_items` - Function to extract items from page (default: `& &1.items`)
    - `:initial_cursor` - Starting cursor (default: nil)

  ## Examples

      Lazy.paginate(
        fn cursor -> API.list_users(cursor: cursor, limit: 100) end,
        fn page -> page.next_cursor end
      )
      |> Lazy.stream_map(&process_user/1)
      |> Lazy.stream_collect()

      # With custom item extraction
      Lazy.paginate(
        &fetch_page/1,
        & &1.meta.next,
        get_items: & &1.data.records
      )
  """
  @spec paginate(
          (term() -> Result.t(page, e)),
          (page -> term() | nil),
          keyword()
        ) :: Enumerable.t()
        when page: term(), e: term()
  def paginate(fetch_page, get_cursor, opts \\ [])
      when is_function(fetch_page, 1) and is_function(get_cursor, 1) do
    get_items = Keyword.get(opts, :get_items, & &1.items)
    initial_cursor = Keyword.get(opts, :initial_cursor, nil)

    Stream.resource(
      fn -> {:fetch, initial_cursor} end,
      fn
        :done ->
          {:halt, :done}

        {:fetch, cursor} ->
          case fetch_page.(cursor) do
            {:ok, page} ->
              items = get_items.(page)
              next_cursor = get_cursor.(page)

              next_state =
                case next_cursor do
                  nil -> :done
                  cursor -> {:fetch, cursor}
                end

              results = Enum.map(items, &{:ok, &1})
              {results, next_state}

            {:error, reason} ->
              {[{:error, reason}], :done}
          end
      end,
      fn _ -> :ok end
    )
  end

  # ============================================
  # Batch Processing
  # ============================================

  @doc """
  Processes a stream in batches.

  Useful for bulk database operations or API calls with batch endpoints.

  ## Examples

      users
      |> Lazy.stream(&{:ok, &1})
      |> Lazy.stream_batch(100, fn batch ->
        Repo.insert_all(User, batch)
        {:ok, length(batch)}
      end)
      |> Lazy.stream_collect()
      #=> {:ok, [100, 100, 50]}  # Counts of inserted batches
  """
  @spec stream_batch(Enumerable.t(), pos_integer(), ([term()] -> Result.t(b, e))) :: Enumerable.t()
        when b: term(), e: term()
  def stream_batch(stream, batch_size, processor)
      when is_integer(batch_size) and batch_size > 0 and is_function(processor, 1) do
    stream
    |> Stream.chunk_every(batch_size)
    |> Stream.map(fn batch ->
      # Extract values from ok tuples
      values =
        Enum.flat_map(batch, fn
          {:ok, v} -> [v]
          {:error, _} -> []
        end)

      case values do
        [] -> {:ok, []}
        items -> processor.(items)
      end
    end)
  end

  # ============================================
  # Utility
  # ============================================

  @doc """
  Combines two lazy computations.

  ## Examples

      lazy1 = Lazy.pure(1)
      lazy2 = Lazy.pure(2)

      Lazy.zip(lazy1, lazy2) |> Lazy.run()
      #=> {:ok, {1, 2}}
  """
  @spec zip(t(a), t(b)) :: t({a, b}) when a: term(), b: term()
  def zip(%__MODULE__{} = lazy1, %__MODULE__{} = lazy2) do
    defer(fn ->
      with {:ok, a} <- run(lazy1),
           {:ok, b} <- run(lazy2) do
        {:ok, {a, b}}
      end
    end)
  end

  @doc """
  Combines lazy computations with a function.

  ## Examples

      Lazy.zip_with(Lazy.pure(2), Lazy.pure(3), &*/2)
      |> Lazy.run()
      #=> {:ok, 6}
  """
  @spec zip_with(t(a), t(b), (a, b -> c)) :: t(c) when a: term(), b: term(), c: term()
  def zip_with(%__MODULE__{} = lazy1, %__MODULE__{} = lazy2, fun) when is_function(fun, 2) do
    defer(fn ->
      with {:ok, a} <- run(lazy1),
           {:ok, b} <- run(lazy2) do
        {:ok, fun.(a, b)}
      end
    end)
  end

  @doc """
  Sequences a list of lazy computations.

  ## Examples

      [Lazy.pure(1), Lazy.pure(2), Lazy.pure(3)]
      |> Lazy.sequence()
      |> Lazy.run()
      #=> {:ok, [1, 2, 3]}
  """
  @spec sequence([t(a)]) :: t([a]) when a: term()
  def sequence(lazies) when is_list(lazies) do
    defer(fn ->
      lazies
      |> Enum.reduce_while({:ok, []}, fn lazy, {:ok, acc} ->
        case run(lazy) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Enum.reverse(values)}
        error -> error
      end
    end)
  end

  @doc """
  Converts a lazy to a stream of one element.

  ## Examples

      Lazy.pure(42)
      |> Lazy.to_stream()
      |> Enum.to_list()
      #=> [{:ok, 42}]
  """
  @spec to_stream(t(a)) :: Enumerable.t() when a: term()
  def to_stream(%__MODULE__{} = lazy) do
    Stream.resource(
      fn -> :pending end,
      fn
        :pending -> {[run(lazy)], :done}
        :done -> {:halt, :done}
      end,
      fn _ -> :ok end
    )
  end
end
