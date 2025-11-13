defmodule Events.Result do
  @moduledoc """
  Functional result type for safe error handling.

  Provides monadic operations on `{:ok, value}` and `{:error, reason}` tuples,
  inspired by Rust's Result type.

  ## Usage

      {:ok, user}
      |> Result.and_then(&send_email/1)
      |> Result.and_then(&log_activity/1)
      |> Result.map(&format_response/1)
      |> Result.map_error(&Error.normalize/1)

  ## Pattern Matching

      case Result.unwrap(fetch_user(id)) do
        {:ok, user} -> render_user(user)
        {:error, error} -> render_error(error)
      end

  ## Collection Operations

      results = [fetch_user(1), fetch_user(2), fetch_user(3)]

      # Get all successful results
      {:ok, users} = Result.collect(results)

      # Apply function to each
      {:ok, formatted} = Result.traverse(users, &format_user/1)
  """

  @type ok(value) :: {:ok, value}
  @type error(reason) :: {:error, reason}
  @type t(value, reason) :: ok(value) | error(reason)
  @type t(value) :: t(value, term())
  @type t() :: t(term(), term())

  ## Type Checking

  @doc """
  Checks if a value is an ok tuple.

  ## Examples

      iex> Result.ok?({:ok, 42})
      true

      iex> Result.ok?({:error, :not_found})
      false
  """
  @spec ok?(term()) :: boolean()
  def ok?({:ok, _}), do: true
  def ok?(_), do: false

  @doc """
  Checks if a value is an error tuple.

  ## Examples

      iex> Result.error?({:error, :not_found})
      true

      iex> Result.error?({:ok, 42})
      false
  """
  @spec error?(term()) :: boolean()
  def error?({:error, _}), do: true
  def error?(_), do: false

  ## Creation

  @doc """
  Creates an ok result.

  ## Examples

      iex> Result.ok(42)
      {:ok, 42}
  """
  @spec ok(value) :: ok(value) when value: term()
  def ok(value), do: {:ok, value}

  @doc """
  Creates an error result.

  ## Examples

      iex> Result.error(:not_found)
      {:error, :not_found}
  """
  @spec error(reason) :: error(reason) when reason: term()
  def error(reason), do: {:error, reason}

  ## Transformation

  @doc """
  Maps a function over the ok value.

  ## Examples

      iex> {:ok, 5} |> Result.map(&(&1 * 2))
      {:ok, 10}

      iex> {:error, :not_found} |> Result.map(&(&1 * 2))
      {:error, :not_found}
  """
  @spec map(t(a, e), (a -> b)) :: t(b, e) when a: term(), b: term(), e: term()
  def map({:ok, value}, fun) when is_function(fun, 1), do: {:ok, fun.(value)}
  def map({:error, _} = error, _fun), do: error

  @doc """
  Maps a function over the error value.

  ## Examples

      iex> {:error, "not found"} |> Result.map_error(&String.upcase/1)
      {:error, "NOT FOUND"}

      iex> {:ok, 42} |> Result.map_error(&String.upcase/1)
      {:ok, 42}
  """
  @spec map_error(t(v, a), (a -> b)) :: t(v, b) when v: term(), a: term(), b: term()
  def map_error({:error, reason}, fun) when is_function(fun, 1), do: {:error, fun.(reason)}
  def map_error({:ok, _} = ok, _fun), do: ok

  ## Chaining

  @doc """
  Chains a result-returning function.

  ## Examples

      iex> {:ok, 5} |> Result.and_then(fn x -> {:ok, x * 2} end)
      {:ok, 10}

      iex> {:ok, 5} |> Result.and_then(fn _ -> {:error, :failed} end)
      {:error, :failed}

      iex> {:error, :not_found} |> Result.and_then(fn x -> {:ok, x * 2} end)
      {:error, :not_found}
  """
  @spec and_then(t(a, e), (a -> t(b, e))) :: t(b, e) when a: term(), b: term(), e: term()
  def and_then({:ok, value}, fun) when is_function(fun, 1), do: fun.(value)
  def and_then({:error, _} = error, _fun), do: error

  @doc """
  Chains an error-handling function.

  ## Examples

      iex> {:error, :not_found} |> Result.or_else(fn _ -> {:ok, :default} end)
      {:ok, :default}

      iex> {:ok, 42} |> Result.or_else(fn _ -> {:ok, :default} end)
      {:ok, 42}
  """
  @spec or_else(t(v, a), (a -> t(v, b))) :: t(v, b) when v: term(), a: term(), b: term()
  def or_else({:error, reason}, fun) when is_function(fun, 1), do: fun.(reason)
  def or_else({:ok, _} = ok, _fun), do: ok

  ## Extraction

  @doc """
  Extracts the value from an ok, raises on error.

  ## Examples

      iex> Result.unwrap!({:ok, 42})
      42

      iex> Result.unwrap!({:error, :not_found})
      ** (ArgumentError) Expected {:ok, value}, got: {:error, :not_found}
  """
  @spec unwrap!(t()) :: term() | no_return()
  def unwrap!({:ok, value}), do: value

  def unwrap!(error) do
    raise ArgumentError, "Expected {:ok, value}, got: #{inspect(error)}"
  end

  @doc """
  Extracts the value from an ok, returns default on error.

  ## Examples

      iex> Result.unwrap_or({:ok, 42}, 0)
      42

      iex> Result.unwrap_or({:error, :not_found}, 0)
      0
  """
  @spec unwrap_or(t(v, any()), v) :: v when v: term()
  def unwrap_or({:ok, value}, _default), do: value
  def unwrap_or({:error, _}, default), do: default

  @doc """
  Extracts the value from an ok, calls function on error.

  ## Examples

      iex> Result.unwrap_or_else({:ok, 42}, fn _ -> 0 end)
      42

      iex> Result.unwrap_or_else({:error, :not_found}, fn _ -> 0 end)
      0
  """
  @spec unwrap_or_else(t(v, e), (e -> v)) :: v when v: term(), e: term()
  def unwrap_or_else({:ok, value}, _fun), do: value
  def unwrap_or_else({:error, reason}, fun) when is_function(fun, 1), do: fun.(reason)

  @doc """
  Returns the value for pattern matching.

  ## Examples

      iex> Result.unwrap({:ok, 42})
      {:ok, 42}

      iex> Result.unwrap({:error, :not_found})
      {:error, :not_found}
  """
  @spec unwrap(t()) :: t()
  def unwrap(result), do: result

  ## Collection Operations

  @doc """
  Collects a list of results into a result of list.

  Returns {:ok, list} if all are ok, {:error, first_error} otherwise.

  ## Examples

      iex> Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])
      {:ok, [1, 2, 3]}

      iex> Result.collect([{:ok, 1}, {:error, :bad}, {:ok, 3}])
      {:error, :bad}
  """
  @spec collect([t(v, e)]) :: t([v], e) when v: term(), e: term()
  def collect(results) when is_list(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, value}, {:ok, acc} ->
        {:cont, {:ok, [value | acc]}}

      {:error, _} = error, _ ->
        {:halt, error}

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  @doc """
  Applies a result-returning function to each element.

  ## Examples

      iex> Result.traverse([1, 2, 3], fn x -> {:ok, x * 2} end)
      {:ok, [2, 4, 6]}

      iex> Result.traverse([1, 2, 3], fn
      ...>   2 -> {:error, :bad}
      ...>   x -> {:ok, x * 2}
      ...> end)
      {:error, :bad}
  """
  @spec traverse([a], (a -> t(b, e))) :: t([b], e) when a: term(), b: term(), e: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> collect()
  end

  ## Combination

  @doc """
  Combines two results, keeping the first error if any.

  ## Examples

      iex> Result.combine({:ok, 1}, {:ok, 2})
      {:ok, {1, 2}}

      iex> Result.combine({:error, :first}, {:ok, 2})
      {:error, :first}

      iex> Result.combine({:ok, 1}, {:error, :second})
      {:error, :second}
  """
  @spec combine(t(a, e), t(b, e)) :: t({a, b}, e) when a: term(), b: term(), e: term()
  def combine({:ok, a}, {:ok, b}), do: {:ok, {a, b}}
  def combine({:error, _} = error, _), do: error
  def combine(_, {:error, _} = error), do: error

  @doc """
  Combines two results with a function.

  ## Examples

      iex> Result.combine_with({:ok, 2}, {:ok, 3}, &(&1 + &2))
      {:ok, 5}

      iex> Result.combine_with({:error, :bad}, {:ok, 3}, &(&1 + &2))
      {:error, :bad}
  """
  @spec combine_with(t(a, e), t(b, e), (a, b -> c)) :: t(c, e)
        when a: term(), b: term(), c: term(), e: term()
  def combine_with({:ok, a}, {:ok, b}, fun) when is_function(fun, 2) do
    {:ok, fun.(a, b)}
  end

  def combine_with({:error, _} = error, _, _), do: error
  def combine_with(_, {:error, _} = error, _), do: error

  ## Conversion

  @doc """
  Converts result to a boolean.

  ## Examples

      iex> Result.to_bool({:ok, 42})
      true

      iex> Result.to_bool({:error, :not_found})
      false
  """
  @spec to_bool(t()) :: boolean()
  def to_bool({:ok, _}), do: true
  def to_bool({:error, _}), do: false

  @doc """
  Converts to option type (value or nil).

  ## Examples

      iex> Result.to_option({:ok, 42})
      42

      iex> Result.to_option({:error, :not_found})
      nil
  """
  @spec to_option(t(v, any())) :: v | nil when v: term()
  def to_option({:ok, value}), do: value
  def to_option({:error, _}), do: nil

  ## Utility

  @doc """
  Taps into ok value for side effects.

  ## Examples

      iex> {:ok, 42} |> Result.tap(&IO.inspect/1) |> Result.map(&(&1 * 2))
      # Prints: 42
      {:ok, 84}
  """
  @spec tap(t(v, e), (v -> any())) :: t(v, e) when v: term(), e: term()
  def tap({:ok, value} = result, fun) when is_function(fun, 1) do
    fun.(value)
    result
  end

  def tap({:error, _} = error, _fun), do: error

  @doc """
  Taps into error value for side effects.

  ## Examples

      iex> {:error, :not_found} |> Result.tap_error(&Logger.error/1)
      # Logs the error
      {:error, :not_found}
  """
  @spec tap_error(t(v, e), (e -> any())) :: t(v, e) when v: term(), e: term()
  def tap_error({:error, reason} = error, fun) when is_function(fun, 1) do
    fun.(reason)
    error
  end

  def tap_error({:ok, _} = ok, _fun), do: ok
end
