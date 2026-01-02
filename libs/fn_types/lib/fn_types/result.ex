defmodule FnTypes.Result do
  @moduledoc """
  Functional result type for safe error handling.

  Provides monadic operations on `{:ok, value}` and `{:error, reason}` tuples,
  inspired by Rust's Result type.

  ## Implemented Behaviours

  - `FnTypes.Behaviours.Chainable` (Monad) - pure, bind, map
  - `FnTypes.Behaviours.Combinable` (Applicative) - pure, ap, map
  - `FnTypes.Behaviours.Mappable` (Functor) - map
  - `FnTypes.Behaviours.Reducible` (Foldable) - fold_left, fold_right
  - `FnTypes.Behaviours.Traversable` - traverse, sequence
  - `FnTypes.Behaviours.BiMappable` (Bifunctor) - bimap, map_error

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

  @behaviour FnTypes.Behaviours.Chainable
  @behaviour FnTypes.Behaviours.Combinable
  @behaviour FnTypes.Behaviours.Mappable
  @behaviour FnTypes.Behaviours.Reducible
  @behaviour FnTypes.Behaviours.Traversable
  @behaviour FnTypes.Behaviours.BiMappable

  import Kernel, except: [apply: 2, apply: 3]

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
  @impl FnTypes.Behaviours.Mappable
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
  @impl FnTypes.Behaviours.BiMappable
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
  @impl FnTypes.Behaviours.Chainable
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

  ## Flattening

  @doc """
  Flattens a nested result.

  ## Examples

      iex> Result.flatten({:ok, {:ok, 42}})
      {:ok, 42}

      iex> Result.flatten({:ok, {:error, :inner}})
      {:error, :inner}

      iex> Result.flatten({:error, :outer})
      {:error, :outer}

      iex> Result.flatten({:ok, 42})
      {:ok, 42}
  """
  @spec flatten(t(t(a, e), e)) :: t(a, e) when a: term(), e: term()
  def flatten({:ok, {:ok, _} = inner}), do: inner
  def flatten({:ok, {:error, _} = inner}), do: inner
  def flatten({:ok, value}), do: {:ok, value}
  def flatten({:error, _} = error), do: error

  ## Creation from Nilable

  @doc """
  Creates a result from a potentially nil value.

  Returns `{:ok, value}` if not nil, `{:error, reason}` if nil.

  ## Examples

      iex> Result.from_nilable(42, :not_found)
      {:ok, 42}

      iex> Result.from_nilable(nil, :not_found)
      {:error, :not_found}

      iex> Result.from_nilable(false, :not_found)
      {:ok, false}
  """
  @spec from_nilable(value | nil, error) :: t(value, error) when value: term(), error: term()
  def from_nilable(nil, error), do: {:error, error}
  def from_nilable(value, _error), do: {:ok, value}

  @doc """
  Creates a result from a potentially nil value with lazy error.

  ## Examples

      iex> Result.from_nilable_lazy(42, fn -> :not_found end)
      {:ok, 42}

      iex> Result.from_nilable_lazy(nil, fn -> :not_found end)
      {:error, :not_found}
  """
  @spec from_nilable_lazy(value | nil, (-> error)) :: t(value, error)
        when value: term(), error: term()
  def from_nilable_lazy(nil, error_fun) when is_function(error_fun, 0), do: {:error, error_fun.()}
  def from_nilable_lazy(value, _error_fun), do: {:ok, value}

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
  Sequences a list of results into a result of list.

  Alias for `collect/1`. Provided for Traversable behaviour compliance.

  ## Examples

      iex> Result.sequence([{:ok, 1}, {:ok, 2}, {:ok, 3}])
      {:ok, [1, 2, 3]}

      iex> Result.sequence([{:ok, 1}, {:error, :bad}])
      {:error, :bad}
  """
  @impl FnTypes.Behaviours.Traversable
  @spec sequence([t(v, e)]) :: t([v], e) when v: term(), e: term()
  def sequence(results), do: collect(results)

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
  @impl FnTypes.Behaviours.Traversable
  @spec traverse([a], (a -> t(b, e))) :: t([b], e) when a: term(), b: term(), e: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> collect()
  end

  @doc """
  Partitions a list of results into successes and failures.

  Unlike `collect/1` which fails fast, this processes all results
  and separates them.

  ## Examples

      iex> Result.partition([{:ok, 1}, {:error, :a}, {:ok, 2}, {:error, :b}])
      %{ok: [1, 2], errors: [:a, :b]}

      iex> Result.partition([{:ok, 1}, {:ok, 2}])
      %{ok: [1, 2], errors: []}

      iex> Result.partition([{:error, :a}])
      %{ok: [], errors: [:a]}
  """
  @spec partition([t(v, e)]) :: %{ok: [v], errors: [e]} when v: term(), e: term()
  def partition(results) when is_list(results) do
    {oks, errors} =
      Enum.reduce(results, {[], []}, fn
        {:ok, value}, {ok_acc, err_acc} -> {[value | ok_acc], err_acc}
        {:error, reason}, {ok_acc, err_acc} -> {ok_acc, [reason | err_acc]}
      end)

    %{ok: Enum.reverse(oks), errors: Enum.reverse(errors)}
  end

  @doc """
  Filters a list keeping only ok values, unwrapped.

  ## Examples

      iex> Result.cat_ok([{:ok, 1}, {:error, :bad}, {:ok, 2}])
      [1, 2]

      iex> Result.cat_ok([{:error, :a}, {:error, :b}])
      []
  """
  @spec cat_ok([t(v, any())]) :: [v] when v: term()
  def cat_ok(results) when is_list(results) do
    results
    |> Enum.filter(&ok?/1)
    |> Enum.map(&unwrap!/1)
  end

  @doc """
  Filters a list keeping only error reasons.

  ## Examples

      iex> Result.cat_errors([{:ok, 1}, {:error, :bad}, {:ok, 2}, {:error, :worse}])
      [:bad, :worse]
  """
  @spec cat_errors([t(any(), e)]) :: [e] when e: term()
  def cat_errors(results) when is_list(results) do
    for {:error, reason} <- results, do: reason
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

  ## Swapping

  @doc """
  Swaps ok and error.

  Useful for testing or inverting the meaning of a result.

  ## Examples

      iex> Result.swap({:ok, 42})
      {:error, 42}

      iex> Result.swap({:error, :not_found})
      {:ok, :not_found}
  """
  @spec swap(t(v, e)) :: t(e, v) when v: term(), e: term()
  def swap({:ok, value}), do: {:error, value}
  def swap({:error, reason}), do: {:ok, reason}

  ## Applicative

  @doc """
  Applies a wrapped function to a wrapped value.

  Applicative functor pattern.

  ## Examples

      iex> Result.apply({:ok, &String.upcase/1}, {:ok, "hello"})
      {:ok, "HELLO"}

      iex> Result.apply({:error, :no_fn}, {:ok, "hello"})
      {:error, :no_fn}

      iex> Result.apply({:ok, &String.upcase/1}, {:error, :no_val})
      {:error, :no_val}
  """
  @spec apply(t((a -> b), e), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def apply({:ok, fun}, {:ok, value}) when is_function(fun, 1), do: {:ok, fun.(value)}
  def apply({:error, _} = error, _), do: error
  def apply(_, {:error, _} = error), do: error

  @doc """
  Applies a wrapped 2-arity function to two wrapped values.

  ## Examples

      iex> Result.apply({:ok, &+/2}, {:ok, 1}, {:ok, 2})
      {:ok, 3}
  """
  @spec apply(t((a, b -> c), e), t(a, e), t(b, e)) :: t(c, e)
        when a: term(), b: term(), c: term(), e: term()
  def apply({:ok, fun}, {:ok, a}, {:ok, b}) when is_function(fun, 2), do: {:ok, fun.(a, b)}
  def apply({:error, _} = error, _, _), do: error
  def apply(_, {:error, _} = error, _), do: error
  def apply(_, _, {:error, _} = error), do: error

  ## Zipping (aliases for combine)

  @doc """
  Zips two results into a result of tuple.

  Alias for `combine/2`.

  ## Examples

      iex> Result.zip({:ok, 1}, {:ok, 2})
      {:ok, {1, 2}}

      iex> Result.zip({:error, :a}, {:ok, 2})
      {:error, :a}
  """
  @spec zip(t(a, e), t(b, e)) :: t({a, b}, e) when a: term(), b: term(), e: term()
  def zip(result_a, result_b), do: combine(result_a, result_b)

  @doc """
  Zips two results with a combining function.

  Alias for `combine_with/3`.

  ## Examples

      iex> Result.zip_with({:ok, 2}, {:ok, 3}, &+/2)
      {:ok, 5}
  """
  @spec zip_with(t(a, e), t(b, e), (a, b -> c)) :: t(c, e)
        when a: term(), b: term(), c: term(), e: term()
  def zip_with(result_a, result_b, fun), do: combine_with(result_a, result_b, fun)

  ## Exception Handling

  @doc """
  Wraps a potentially raising function in a Result.

  Catches exceptions and returns them as `{:error, exception}`.

  ## Examples

      iex> Result.try_with(fn -> 1 + 1 end)
      {:ok, 2}

      iex> {:error, %RuntimeError{}} = Result.try_with(fn -> raise "boom" end)
      iex> :ok
      :ok

      iex> Result.try_with(fn -> throw(:ball) end)
      {:error, {:throw, :ball}}

      iex> Result.try_with(fn -> exit(:normal) end)
      {:error, {:exit, :normal}}
  """
  @spec try_with((-> a)) :: t(a, Exception.t() | {:throw, term()} | {:exit, term()})
        when a: term()
  def try_with(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    e -> {:error, e}
  catch
    :throw, value -> {:error, {:throw, value}}
    :exit, reason -> {:error, {:exit, reason}}
  end

  @doc """
  Wraps a potentially raising function, passing an argument.

  ## Examples

      iex> Result.try_with(fn x -> x * 2 end, 5)
      {:ok, 10}

      iex> Result.try_with(fn _ -> raise "boom" end, 5)
      {:error, %RuntimeError{message: "boom"}}
  """
  @spec try_with((a -> b), a) :: t(b, Exception.t() | {:throw, term()} | {:exit, term()})
        when a: term(), b: term()
  def try_with(fun, arg) when is_function(fun, 1) do
    {:ok, fun.(arg)}
  rescue
    e -> {:error, e}
  catch
    :throw, value -> {:error, {:throw, value}}
    :exit, reason -> {:error, {:exit, reason}}
  end

  ## Bimap

  @doc """
  Transforms both ok and error values using expressive keyword options.

  Use `on_ok:` to transform success values and `on_error:` to transform errors.
  You can specify both or just one - the other side passes through unchanged.

  ## Examples

      # Transform both sides
      iex> Result.bimap({:ok, 5}, on_ok: &(&1 * 2), on_error: &String.upcase/1)
      {:ok, 10}

      iex> Result.bimap({:error, "bad"}, on_ok: &(&1 * 2), on_error: &String.upcase/1)
      {:error, "BAD"}

      # Transform only errors (ok passes through)
      iex> Result.bimap({:ok, 5}, on_error: &String.upcase/1)
      {:ok, 5}

      iex> Result.bimap({:error, "bad"}, on_error: &String.upcase/1)
      {:error, "BAD"}

      # Transform only ok (errors pass through)
      iex> Result.bimap({:ok, 5}, on_ok: &(&1 * 2))
      {:ok, 10}

  ## Real-world Example

      fetch_user(id)
      |> Result.bimap(
        on_ok: fn user -> %{id: user.id, name: user.name} end,
        on_error: fn error -> %{code: 404, message: inspect(error)} end
      )
  """
  @impl FnTypes.Behaviours.BiMappable
  @spec bimap(t(a, e1), keyword()) :: t(b, e2)
        when a: term(), b: term(), e1: term(), e2: term()
  def bimap(result, opts) when is_list(opts) do
    on_ok = Keyword.get(opts, :on_ok)
    on_error = Keyword.get(opts, :on_error)

    case result do
      {:ok, value} when is_function(on_ok, 1) -> {:ok, on_ok.(value)}
      {:ok, _} = ok -> ok
      {:error, reason} when is_function(on_error, 1) -> {:error, on_error.(reason)}
      {:error, _} = error -> error
    end
  end

  ## Function Lifting

  @doc """
  Lifts a regular function to work on Result values.

  Returns a new function that takes a Result and applies the
  original function to the wrapped value if ok.

  ## Examples

      iex> upcase = Result.lift(&String.upcase/1)
      iex> upcase.({:ok, "hello"})
      {:ok, "HELLO"}

      iex> upcase = Result.lift(&String.upcase/1)
      iex> upcase.({:error, :bad})
      {:error, :bad}

      iex> add = Result.lift(&(&1 + &2))
      iex> add.({:ok, 1}, {:ok, 2})
      {:ok, 3}
  """
  @spec lift((a -> b)) :: (t(a, e) -> t(b, e)) when a: term(), b: term(), e: term()
  def lift(fun) when is_function(fun, 1) do
    fn result -> map(result, fun) end
  end

  @spec lift((a, b -> c)) :: (t(a, e), t(b, e) -> t(c, e))
        when a: term(), b: term(), c: term(), e: term()
  def lift(fun) when is_function(fun, 2) do
    fn result_a, result_b -> combine_with(result_a, result_b, fun) end
  end

  @doc """
  Lifts a function and immediately applies it to Result values.

  ## Examples

      iex> Result.lift_apply(&String.upcase/1, {:ok, "hello"})
      {:ok, "HELLO"}

      iex> Result.lift_apply(&+/2, {:ok, 1}, {:ok, 2})
      {:ok, 3}
  """
  @spec lift_apply((a -> b), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def lift_apply(fun, result) when is_function(fun, 1), do: map(result, fun)

  @spec lift_apply((a, b -> c), t(a, e), t(b, e)) :: t(c, e)
        when a: term(), b: term(), c: term(), e: term()
  def lift_apply(fun, result_a, result_b) when is_function(fun, 2) do
    combine_with(result_a, result_b, fun)
  end

  ## Enumerable Support

  @doc """
  Converts a Result to an enumerable (list).

  Enables using Result values with Enum functions.

  ## Examples

      iex> Result.to_enum({:ok, 42})
      [42]

      iex> Result.to_enum({:error, :bad})
      []

      iex> {:ok, 5} |> Result.to_enum() |> Enum.map(&(&1 * 2))
      [10]
  """
  @spec to_enum(t(a, any())) :: [a] when a: term()
  def to_enum({:ok, value}), do: [value]
  def to_enum({:error, _}), do: []

  @doc """
  Reduces over a Result value.

  ## Examples

      iex> Result.reduce({:ok, 5}, 0, &+/2)
      5

      iex> Result.reduce({:error, :bad}, 0, &+/2)
      0
  """
  @spec reduce(t(a, any()), acc, (a, acc -> acc)) :: acc when a: term(), acc: term()
  def reduce({:ok, value}, acc, fun) when is_function(fun, 2), do: fun.(value, acc)
  def reduce({:error, _}, acc, _fun), do: acc

  ## Error Module Integration

  @doc """
  Normalizes an error using the FnTypes.Normalizable protocol.

  Transforms any error reason into a structured `FnTypes.Error` using
  protocol-based normalization. Supports Ecto changesets, HTTP errors,
  database errors, and any type implementing `FnTypes.Normalizable`.

  ## Examples

      {:error, changeset} |> Result.normalize_error()
      #=> {:error, %FnTypes.Error{type: :validation, ...}}

      {:error, :not_found} |> Result.normalize_error()
      #=> {:error, %FnTypes.Error{type: :not_found, ...}}

      {:error, %Postgrex.Error{}} |> Result.normalize_error(context: %{user_id: 123})
      #=> {:error, %FnTypes.Error{context: %{user_id: 123}, ...}}

      {:ok, value} |> Result.normalize_error()
      #=> {:ok, value}
  """
  @spec normalize_error(t(v, e), keyword()) :: t(v, FnTypes.Error.t())
        when v: term(), e: term()
  def normalize_error(result, opts \\ [])
  def normalize_error({:ok, _} = ok, _opts), do: ok

  def normalize_error({:error, reason}, opts) do
    {:error, FnTypes.Protocols.Normalizable.normalize(reason, opts)}
  end

  @doc """
  Wraps an error with FnTypes.Error context.

  Transforms a simple error into a structured Error with context.
  Useful for adding debugging information to errors.

  ## Examples

      iex> {:error, :not_found}
      ...> |> Result.wrap_error(user_id: 123, action: :fetch)
      {:error, %{reason: :not_found, context: %{user_id: 123, action: :fetch}}}

      iex> {:ok, 42} |> Result.wrap_error(user_id: 123)
      {:ok, 42}
  """
  @spec wrap_error(t(v, e), keyword()) :: t(v, %{reason: e, context: map()})
        when v: term(), e: term()
  def wrap_error({:ok, _} = ok, _context), do: ok

  def wrap_error({:error, reason}, context) when is_list(context) do
    {:error, %{reason: reason, context: Map.new(context)}}
  end

  @doc """
  Converts an error to an FnTypes.Error struct.

  Creates a full Error struct from a result error, with optional
  type and context.

  ## Examples

      Result.to_error({:error, :not_found}, :not_found,
        message: "User not found",
        context: %{user_id: 123}
      )
      #=> {:error, %FnTypes.Error{type: :not_found, code: :not_found, ...}}

      Result.to_error({:ok, value}, :not_found)
      #=> {:ok, value}
  """
  @spec to_error(t(v, e), atom(), keyword()) :: t(v, FnTypes.Error.t())
        when v: term(), e: term()
  def to_error(result, type, opts \\ [])
  def to_error({:ok, _} = ok, _type, _opts), do: ok

  def to_error({:error, reason}, type, opts) when is_atom(type) do
    code = Keyword.get(opts, :code, reason_to_code(reason))
    message = Keyword.get(opts, :message, reason_to_message(reason))
    context = Keyword.get(opts, :context, %{})
    details = Keyword.get(opts, :details, %{original_reason: reason})

    error = FnTypes.Error.new(type, code, message: message, details: details, context: context)
    {:error, error}
  end

  @doc """
  Adds step context to an error for pipeline tracking.

  ## Examples

      Result.with_step({:error, :not_found}, :fetch_user)
      #=> {:error, {:step_failed, :fetch_user, :not_found}}

      Result.with_step({:ok, value}, :fetch_user)
      #=> {:ok, value}
  """
  @spec with_step(t(v, e), atom()) :: t(v, {:step_failed, atom(), e}) when v: term(), e: term()
  def with_step({:ok, _} = ok, _step), do: ok

  def with_step({:error, reason}, step) when is_atom(step) do
    {:error, {:step_failed, step, reason}}
  end

  @doc """
  Extracts the original error from a step-wrapped error.

  ## Examples

      iex> Result.unwrap_step({:error, {:step_failed, :fetch, :not_found}})
      {:error, :not_found}

      iex> Result.unwrap_step({:error, :simple_error})
      {:error, :simple_error}

      iex> Result.unwrap_step({:ok, 42})
      {:ok, 42}
  """
  @spec unwrap_step(t(v, e)) :: t(v, term()) when v: term(), e: term()
  def unwrap_step({:ok, _} = ok), do: ok
  def unwrap_step({:error, {:step_failed, _step, reason}}), do: {:error, reason}
  def unwrap_step({:error, _} = error), do: error

  # Private helpers for error conversion
  defp reason_to_code(reason) when is_atom(reason), do: reason
  defp reason_to_code(%{code: code}) when is_atom(code), do: code
  defp reason_to_code(_), do: :unknown

  defp reason_to_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_message(reason) when is_binary(reason), do: reason
  defp reason_to_message(%{message: msg}) when is_binary(msg), do: msg
  defp reason_to_message(reason), do: inspect(reason)

  # ============================================
  # Behaviour Implementations
  # ============================================

  @doc """
  Wraps a value in an ok result (Monad.pure).

  Alias for `ok/1`.

  ## Examples

      iex> Result.pure(42)
      {:ok, 42}
  """
  @impl FnTypes.Behaviours.Combinable
  @spec pure(value) :: ok(value) when value: term()
  def pure(value), do: ok(value)

  @doc """
  Chains a function that returns a Result (Monad.bind).

  Alias for `and_then/2`.

  ## Examples

      iex> Result.bind({:ok, 5}, fn x -> {:ok, x * 2} end)
      {:ok, 10}
  """
  @impl FnTypes.Behaviours.Chainable
  @spec bind(t(a, e), (a -> t(b, e))) :: t(b, e) when a: term(), b: term(), e: term()
  def bind(result, fun), do: and_then(result, fun)

  @doc """
  Applies a wrapped function to a wrapped value (Applicative.ap).

  Alias for `apply/2`.

  ## Examples

      iex> Result.ap({:ok, fn x -> x * 2 end}, {:ok, 5})
      {:ok, 10}
  """
  @impl FnTypes.Behaviours.Combinable
  @spec ap(t((a -> b), e), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def ap(result_fun, result_val), do: apply(result_fun, result_val)

  @doc """
  Left fold over the success value (Foldable.fold_left).

  Applies the function to the success value and accumulator.
  Returns the accumulator unchanged for error results.

  ## Examples

      iex> Result.fold_left({:ok, 5}, 10, &+/2)
      15

      iex> Result.fold_left({:error, :not_found}, 10, &+/2)
      10
  """
  @impl FnTypes.Behaviours.Reducible
  @spec fold_left(t(a, e), acc, (a, acc -> acc)) :: acc when a: term(), e: term(), acc: term()
  def fold_left({:ok, value}, acc, fun) when is_function(fun, 2), do: fun.(value, acc)
  def fold_left({:error, _}, acc, _fun), do: acc

  @doc """
  Right fold over the success value (Foldable.fold_right).

  For single-value containers like Result, equivalent to fold_left.

  ## Examples

      iex> Result.fold_right({:ok, 5}, 10, &+/2)
      15
  """
  @impl FnTypes.Behaviours.Reducible
  @spec fold_right(t(a, e), acc, (a, acc -> acc)) :: acc when a: term(), e: term(), acc: term()
  def fold_right({:ok, value}, acc, fun) when is_function(fun, 2), do: fun.(value, acc)
  def fold_right({:error, _}, acc, _fun), do: acc
end
