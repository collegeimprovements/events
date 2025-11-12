defmodule Events.Normalizers.Result do
  @moduledoc """
  Helpers for working with result tuples {:ok, value} | {:error, reason}.

  Provides a functional API for chaining, transforming, and handling result tuples
  inspired by Rust's Result type and Elixir's with expressions.

  ## Usage

      # Chaining operations
      {:ok, user}
      |> Result.and_then(&send_email/1)
      |> Result.and_then(&log_activity/1)
      |> Result.map(&format_response/1)

      # Error handling
      {:error, :not_found}
      |> Result.or_else(fn _ -> {:ok, default_user()} end)
      |> Result.unwrap_or(%User{})

      # Transformation
      {:ok, user}
      |> Result.map(&Map.get(&1, :email))
      |> Result.map_error(&normalize_error/1)
  """

  @type result(ok, error) :: {:ok, ok} | {:error, error}
  @type result(value) :: result(value, term())
  @type result :: result(term(), term())

  ## Core Operations

  @doc """
  Returns true if the result is {:ok, _}.

  ## Examples

      iex> Result.ok?({:ok, 42})
      true

      iex> Result.ok?({:error, :oops})
      false
  """
  @spec ok?(result()) :: boolean()
  def ok?({:ok, _}), do: true
  def ok?(_), do: false

  @doc """
  Returns true if the result is {:error, _}.

  ## Examples

      iex> Result.error?({:error, :oops})
      true

      iex> Result.error?({:ok, 42})
      false
  """
  @spec error?(result()) :: boolean()
  def error?({:error, _}), do: true
  def error?(_), do: false

  ## Transformation

  @doc """
  Transforms the ok value using the given function.

  If the result is an error, returns it unchanged.

  ## Examples

      iex> {:ok, 5} |> Result.map(&(&1 * 2))
      {:ok, 10}

      iex> {:error, :oops} |> Result.map(&(&1 * 2))
      {:error, :oops}
  """
  @spec map(result(a, e), (a -> b)) :: result(b, e) when a: term(), b: term(), e: term()
  def map({:ok, value}, fun) when is_function(fun, 1), do: {:ok, fun.(value)}
  def map({:error, _} = error, _fun), do: error

  @doc """
  Transforms the error value using the given function.

  If the result is ok, returns it unchanged.

  ## Examples

      iex> {:error, :not_found} |> Result.map_error(&Error.normalize/1)
      {:error, %Error{type: :not_found, ...}}

      iex> {:ok, 42} |> Result.map_error(&Error.normalize/1)
      {:ok, 42}
  """
  @spec map_error(result(a, e1), (e1 -> e2)) :: result(a, e2)
        when a: term(), e1: term(), e2: term()
  def map_error({:ok, _} = ok, _fun), do: ok
  def map_error({:error, reason}, fun) when is_function(fun, 1), do: {:error, fun.(reason)}

  @doc """
  Transforms both ok and error values.

  ## Examples

      iex> {:ok, 5} |> Result.map_both(&(&1 * 2), &Error.normalize/1)
      {:ok, 10}

      iex> {:error, :not_found} |> Result.map_both(&(&1 * 2), &Error.normalize/1)
      {:error, %Error{type: :not_found, ...}}
  """
  @spec map_both(result(a, e1), (a -> b), (e1 -> e2)) :: result(b, e2)
        when a: term(), b: term(), e1: term(), e2: term()
  def map_both({:ok, value}, ok_fun, _error_fun), do: {:ok, ok_fun.(value)}
  def map_both({:error, reason}, _ok_fun, error_fun), do: {:error, error_fun.(reason)}

  ## Chaining

  @doc """
  Chains a result-returning function, also known as flat_map or bind.

  If the result is ok, calls the function with the value. If error, returns it.

  ## Examples

      iex> {:ok, "user@example.com"}
      ...> |> Result.and_then(&find_user_by_email/1)
      ...> |> Result.and_then(&send_welcome_email/1)
      {:ok, %Email{}}

      iex> {:error, :not_found} |> Result.and_then(&do_something/1)
      {:error, :not_found}
  """
  @spec and_then(result(a, e), (a -> result(b, e))) :: result(b, e)
        when a: term(), b: term(), e: term()
  def and_then({:ok, value}, fun) when is_function(fun, 1), do: fun.(value)
  def and_then({:error, _} = error, _fun), do: error

  @doc """
  Calls a result-returning function on error, allowing recovery.

  If the result is ok, returns it unchanged. If error, calls the function.

  ## Examples

      iex> {:error, :not_found}
      ...> |> Result.or_else(fn _ -> {:ok, default_user()} end)
      {:ok, %User{}}

      iex> {:ok, user} |> Result.or_else(fn _ -> {:ok, default_user()} end)
      {:ok, user}
  """
  @spec or_else(result(a, e1), (e1 -> result(a, e2))) :: result(a, e2)
        when a: term(), e1: term(), e2: term()
  def or_else({:ok, _} = ok, _fun), do: ok
  def or_else({:error, reason}, fun) when is_function(fun, 1), do: fun.(reason)

  ## Unwrapping

  @doc """
  Unwraps an ok result, raising if error.

  ## Examples

      iex> Result.unwrap!({:ok, 42})
      42

      iex> Result.unwrap!({:error, :oops})
      ** (RuntimeError) Attempted to unwrap an error: :oops
  """
  @spec unwrap!(result(a, term())) :: a when a: term()
  def unwrap!({:ok, value}), do: value

  def unwrap!({:error, reason}) do
    raise "Attempted to unwrap an error: #{inspect(reason)}"
  end

  @doc """
  Unwraps a result, returning the value or a default.

  ## Examples

      iex> Result.unwrap_or({:ok, 42}, 0)
      42

      iex> Result.unwrap_or({:error, :oops}, 0)
      0
  """
  @spec unwrap_or(result(a, term()), a) :: a when a: term()
  def unwrap_or({:ok, value}, _default), do: value
  def unwrap_or({:error, _}, default), do: default

  @doc """
  Unwraps a result, calling a function on error to provide a default.

  ## Examples

      iex> {:ok, 42} |> Result.unwrap_or_else(fn _ -> 0 end)
      42

      iex> {:error, :oops} |> Result.unwrap_or_else(fn _ -> 0 end)
      0
  """
  @spec unwrap_or_else(result(a, e), (e -> a)) :: a when a: term(), e: term()
  def unwrap_or_else({:ok, value}, _fun), do: value
  def unwrap_or_else({:error, reason}, fun) when is_function(fun, 1), do: fun.(reason)

  ## Inspection

  @doc """
  Calls a function with the ok value for side effects, returns result unchanged.

  Useful for debugging or logging in pipelines.

  ## Examples

      iex> {:ok, user}
      ...> |> Result.tap(&IO.inspect/1)
      ...> |> Result.map(&format/1)
  """
  @spec tap(result(a, e), (a -> term())) :: result(a, e) when a: term(), e: term()
  def tap({:ok, value} = result, fun) when is_function(fun, 1) do
    fun.(value)
    result
  end

  def tap(result, _fun), do: result

  @doc """
  Calls a function with the error reason for side effects, returns result unchanged.

  ## Examples

      iex> {:error, :not_found}
      ...> |> Result.tap_error(&Logger.error("Error: \#{inspect(&1)}"))
      ...> |> Result.or_else(&recover/1)
  """
  @spec tap_error(result(a, e), (e -> term())) :: result(a, e) when a: term(), e: term()
  def tap_error({:error, reason} = result, fun) when is_function(fun, 1) do
    fun.(reason)
    result
  end

  def tap_error(result, _fun), do: result

  ## Collection Operations

  @doc """
  Collects a list of results into a single result.

  Returns {:ok, list_of_values} if all results are ok.
  Returns {:error, first_error} if any result is an error.

  ## Examples

      iex> Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])
      {:ok, [1, 2, 3]}

      iex> Result.collect([{:ok, 1}, {:error, :oops}, {:ok, 3}])
      {:error, :oops}
  """
  @spec collect([result(a, e)]) :: result([a], e) when a: term(), e: term()
  def collect(results) when is_list(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, value}, {:ok, acc} -> {:cont, {:ok, [value | acc]}}
      {:error, _} = error, _acc -> {:halt, error}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  @doc """
  Maps a function over a list, collecting results.

  Short-circuits on the first error.

  ## Examples

      iex> Result.traverse([1, 2, 3], &{:ok, &1 * 2})
      {:ok, [2, 4, 6]}

      iex> Result.traverse([1, 2, 3], fn x -> if x == 2, do: {:error, :bad}, else: {:ok, x} end)
      {:error, :bad}
  """
  @spec traverse([a], (a -> result(b, e))) :: result([b], e) when a: term(), b: term(), e: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> collect()
  end

  ## Combining Results

  @doc """
  Combines two results, returning ok only if both are ok.

  ## Examples

      iex> Result.combine({:ok, 1}, {:ok, 2})
      {:ok, {1, 2}}

      iex> Result.combine({:ok, 1}, {:error, :oops})
      {:error, :oops}

      iex> Result.combine({:error, :oops1}, {:error, :oops2})
      {:error, :oops1}
  """
  @spec combine(result(a, e), result(b, e)) :: result({a, b}, e)
        when a: term(), b: term(), e: term()
  def combine({:ok, a}, {:ok, b}), do: {:ok, {a, b}}
  def combine({:error, _} = error, _), do: error
  def combine(_, {:error, _} = error), do: error

  @doc """
  Combines two results using a function.

  ## Examples

      iex> Result.combine_with({:ok, 1}, {:ok, 2}, fn a, b -> a + b end)
      {:ok, 3}
  """
  @spec combine_with(result(a, e), result(b, e), (a, b -> c)) :: result(c, e)
        when a: term(), b: term(), c: term(), e: term()
  def combine_with({:ok, a}, {:ok, b}, fun) when is_function(fun, 2), do: {:ok, fun.(a, b)}
  def combine_with({:error, _} = error, _, _), do: error
  def combine_with(_, {:error, _} = error, _), do: error

  ## Conversion

  @doc """
  Converts an ok result to {:error, error}, and vice versa.

  ## Examples

      iex> Result.flip({:ok, 42})
      {:error, 42}

      iex> Result.flip({:error, :oops})
      {:ok, :oops}
  """
  @spec flip(result(a, e)) :: result(e, a) when a: term(), e: term()
  def flip({:ok, value}), do: {:error, value}
  def flip({:error, reason}), do: {:ok, reason}

  @doc """
  Wraps a value in {:ok, value}.

  ## Examples

      iex> Result.ok(42)
      {:ok, 42}
  """
  @spec ok(a) :: result(a, term()) when a: term()
  def ok(value), do: {:ok, value}

  @doc """
  Wraps a value in {:error, value}.

  ## Examples

      iex> Result.error(:oops)
      {:error, :oops}
  """
  @spec error(e) :: result(term(), e) when e: term()
  def error(reason), do: {:error, reason}
end
