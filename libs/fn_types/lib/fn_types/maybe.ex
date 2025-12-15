defmodule FnTypes.Maybe do
  @moduledoc """
  Option/Maybe type for nil-safe operations.

  Provides monadic operations for values that may or may not exist,
  where absence is not an error (unlike `Result`). Inspired by
  Haskell's Maybe, Rust's Option, and Swift's Optional.

  ## Implemented Behaviours

  - `FnTypes.Behaviours.Chainable` (Monad) - pure, bind, map
  - `FnTypes.Behaviours.Combinable` (Applicative) - pure, ap, map
  - `FnTypes.Behaviours.Mappable` (Functor) - map
  - `FnTypes.Behaviours.Reducible` (Foldable) - fold_left, fold_right
  - `FnTypes.Behaviours.Traversable` - traverse, sequence

  ## When to Use Maybe vs Result

  - **Use `Maybe`** when absence is a valid, expected state (e.g., optional fields)
  - **Use `Result`** when absence indicates a failure (e.g., database lookup by ID)

  ## Representation

  - `{:some, value}` - A present value
  - `:none` - Absent value

  ## Usage

      import FnTypes.Maybe

      # Wrap a potentially nil value
      user.middle_name
      |> Maybe.from_nilable()
      |> Maybe.map(&String.upcase/1)
      |> Maybe.unwrap_or("N/A")

      # Chain operations that might return nil
      Maybe.from_nilable(params["user"])
      |> Maybe.and_then(fn u -> Maybe.from_nilable(u["email"]) end)
      |> Maybe.filter(&valid_email?/1)
      |> Maybe.map(&String.downcase/1)

      # First present value
      Maybe.first_some([
        fn -> config[:primary_url] end,
        fn -> System.get_env("API_URL") end,
        fn -> "http://localhost:4000" end
      ])

  ## Interoperability with Result

      # Convert Maybe to Result
      Maybe.from_nilable(value)
      |> Maybe.to_result(:not_found)
      #=> {:ok, value} | {:error, :not_found}

      # Convert Result to Maybe
      {:ok, value} |> Maybe.from_result()
      #=> {:some, value}
  """

  @behaviour FnTypes.Behaviours.Chainable
  @behaviour FnTypes.Behaviours.Combinable
  @behaviour FnTypes.Behaviours.Mappable
  @behaviour FnTypes.Behaviours.Reducible
  @behaviour FnTypes.Behaviours.Traversable

  import Kernel, except: [apply: 2, apply: 3]

  # ============================================
  # Types
  # ============================================

  @type some(value) :: {:some, value}
  @type nothing :: :none
  @type t(value) :: some(value) | nothing()
  @type t() :: t(term())

  # ============================================
  # Type Checking
  # ============================================

  @doc """
  Checks if a value is some.

  ## Examples

      iex> Maybe.some?({:some, 42})
      true

      iex> Maybe.some?(:none)
      false
  """
  @spec some?(t()) :: boolean()
  def some?({:some, _}), do: true
  def some?(:none), do: false
  def some?(_), do: false

  @doc """
  Checks if a value is none.

  ## Examples

      iex> Maybe.none?(:none)
      true

      iex> Maybe.none?({:some, 42})
      false
  """
  @spec none?(t()) :: boolean()
  def none?(:none), do: true
  def none?({:some, _}), do: false
  def none?(_), do: false

  # ============================================
  # Creation
  # ============================================

  @doc """
  Wraps a value in some.

  ## Examples

      iex> Maybe.some(42)
      {:some, 42}

      iex> Maybe.some(nil)
      {:some, nil}
  """
  @spec some(value) :: some(value) when value: term()
  def some(value), do: {:some, value}

  @doc """
  Returns none.

  ## Examples

      iex> Maybe.none()
      :none
  """
  @spec none() :: none()
  def none, do: :none

  @doc """
  Creates a Maybe from a potentially nil value.

  ## Examples

      iex> Maybe.from_nilable(42)
      {:some, 42}

      iex> Maybe.from_nilable(nil)
      :none

      iex> Maybe.from_nilable(false)
      {:some, false}
  """
  @spec from_nilable(value | nil) :: t(value) when value: term()
  def from_nilable(nil), do: :none
  def from_nilable(value), do: {:some, value}

  @doc """
  Creates a Maybe from a Result tuple.

  ## Examples

      iex> Maybe.from_result({:ok, 42})
      {:some, 42}

      iex> Maybe.from_result({:error, :not_found})
      :none
  """
  @spec from_result({:ok, value} | {:error, term()}) :: t(value) when value: term()
  def from_result({:ok, value}), do: {:some, value}
  def from_result({:error, _}), do: :none

  @doc """
  Creates a Maybe from a boolean condition.

  ## Examples

      iex> Maybe.from_bool(true, "yes")
      {:some, "yes"}

      iex> Maybe.from_bool(false, "yes")
      :none
  """
  @spec from_bool(boolean(), value) :: t(value) when value: term()
  def from_bool(true, value), do: {:some, value}
  def from_bool(false, _value), do: :none

  @doc """
  Creates a Maybe, treating empty strings as none.

  ## Examples

      iex> Maybe.from_string("hello")
      {:some, "hello"}

      iex> Maybe.from_string("")
      :none

      iex> Maybe.from_string("   ")
      :none

      iex> Maybe.from_string(nil)
      :none
  """
  @spec from_string(String.t() | nil) :: t(String.t())
  def from_string(nil), do: :none

  def from_string(str) when is_binary(str) do
    case String.trim(str) do
      "" -> :none
      trimmed -> {:some, trimmed}
    end
  end

  @doc """
  Creates a Maybe, treating empty collections as none.

  ## Examples

      iex> Maybe.from_list([1, 2, 3])
      {:some, [1, 2, 3]}

      iex> Maybe.from_list([])
      :none

      iex> Maybe.from_map(%{a: 1})
      {:some, %{a: 1}}

      iex> Maybe.from_map(%{})
      :none
  """
  @spec from_list(list()) :: t(list())
  def from_list([]), do: :none
  def from_list(list) when is_list(list), do: {:some, list}

  @spec from_map(map()) :: t(map())
  def from_map(map) when map_size(map) == 0, do: :none
  def from_map(map) when is_map(map), do: {:some, map}

  # ============================================
  # Transformation
  # ============================================

  @doc """
  Maps a function over the some value.

  ## Examples

      iex> {:some, 5} |> Maybe.map(&(&1 * 2))
      {:some, 10}

      iex> :none |> Maybe.map(&(&1 * 2))
      :none
  """
  @spec map(t(a), (a -> b)) :: t(b) when a: term(), b: term()
  @impl FnTypes.Behaviours.Mappable
  def map({:some, value}, fun) when is_function(fun, 1), do: {:some, fun.(value)}
  def map(:none, _fun), do: :none

  @doc """
  Replaces the value if some, keeping the structure.

  ## Examples

      iex> {:some, 5} |> Maybe.replace(42)
      {:some, 42}

      iex> :none |> Maybe.replace(42)
      :none
  """
  @spec replace(t(any()), value) :: t(value) when value: term()
  def replace({:some, _}, value), do: {:some, value}
  def replace(:none, _value), do: :none

  # ============================================
  # Chaining
  # ============================================

  @doc """
  Chains a maybe-returning function.

  Also known as `flat_map` or `bind`.

  ## Examples

      iex> {:some, 5} |> Maybe.and_then(fn x -> {:some, x * 2} end)
      {:some, 10}

      iex> {:some, 5} |> Maybe.and_then(fn _ -> :none end)
      :none

      iex> :none |> Maybe.and_then(fn x -> {:some, x * 2} end)
      :none
  """
  @spec and_then(t(a), (a -> t(b))) :: t(b) when a: term(), b: term()
  def and_then({:some, value}, fun) when is_function(fun, 1), do: fun.(value)
  def and_then(:none, _fun), do: :none

  @doc """
  Provides an alternative if none.

  ## Examples

      iex> :none |> Maybe.or_else(fn -> {:some, 42} end)
      {:some, 42}

      iex> {:some, 5} |> Maybe.or_else(fn -> {:some, 42} end)
      {:some, 5}
  """
  @spec or_else(t(a), (-> t(a))) :: t(a) when a: term()
  def or_else(:none, fun) when is_function(fun, 0), do: fun.()
  def or_else({:some, _} = some, _fun), do: some

  @doc """
  Returns the first maybe if some, otherwise the second.

  ## Examples

      iex> Maybe.or_value({:some, 1}, {:some, 2})
      {:some, 1}

      iex> Maybe.or_value(:none, {:some, 2})
      {:some, 2}

      iex> Maybe.or_value(:none, :none)
      :none
  """
  @spec or_value(t(a), t(a)) :: t(a) when a: term()
  def or_value({:some, _} = some, _other), do: some
  def or_value(:none, other), do: other

  # ============================================
  # Filtering
  # ============================================

  @doc """
  Filters the value with a predicate.

  Returns none if the predicate returns false.

  ## Examples

      iex> {:some, 5} |> Maybe.filter(&(&1 > 3))
      {:some, 5}

      iex> {:some, 2} |> Maybe.filter(&(&1 > 3))
      :none

      iex> :none |> Maybe.filter(&(&1 > 3))
      :none
  """
  @spec filter(t(a), (a -> boolean())) :: t(a) when a: term()
  def filter({:some, value}, pred) when is_function(pred, 1) do
    case pred.(value) do
      true -> {:some, value}
      false -> :none
    end
  end

  def filter(:none, _pred), do: :none

  @doc """
  Rejects the value if predicate returns true.

  Inverse of `filter/2`.

  ## Examples

      iex> {:some, 5} |> Maybe.reject(&(&1 > 3))
      :none

      iex> {:some, 2} |> Maybe.reject(&(&1 > 3))
      {:some, 2}
  """
  @spec reject(t(a), (a -> boolean())) :: t(a) when a: term()
  def reject({:some, value}, pred) when is_function(pred, 1) do
    case pred.(value) do
      true -> :none
      false -> {:some, value}
    end
  end

  def reject(:none, _pred), do: :none

  # ============================================
  # Extraction
  # ============================================

  @doc """
  Extracts the value from some, raises on none.

  ## Examples

      iex> Maybe.unwrap!({:some, 42})
      42

      iex> Maybe.unwrap!(:none)
      ** (ArgumentError) Expected {:some, value}, got: :none
  """
  @spec unwrap!(t(value)) :: value | no_return() when value: term()
  def unwrap!({:some, value}), do: value
  def unwrap!(:none), do: raise(ArgumentError, "Expected {:some, value}, got: :none")

  @doc """
  Extracts the value from some, returns default on none.

  ## Examples

      iex> Maybe.unwrap_or({:some, 42}, 0)
      42

      iex> Maybe.unwrap_or(:none, 0)
      0
  """
  @spec unwrap_or(t(a), a) :: a when a: term()
  @impl FnTypes.Behaviours.Chainable
  def unwrap_or({:some, value}, _default), do: value
  def unwrap_or(:none, default), do: default

  @doc """
  Extracts the value from some, calls function on none.

  ## Examples

      iex> Maybe.unwrap_or_else({:some, 42}, fn -> 0 end)
      42

      iex> Maybe.unwrap_or_else(:none, fn -> 0 end)
      0
  """
  @spec unwrap_or_else(t(a), (-> a)) :: a when a: term()
  def unwrap_or_else({:some, value}, _fun), do: value
  def unwrap_or_else(:none, fun) when is_function(fun, 0), do: fun.()

  @doc """
  Converts to nilable value.

  ## Examples

      iex> Maybe.to_nilable({:some, 42})
      42

      iex> Maybe.to_nilable(:none)
      nil
  """
  @spec to_nilable(t(value)) :: value | nil when value: term()
  def to_nilable({:some, value}), do: value
  def to_nilable(:none), do: nil

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts to a Result tuple.

  ## Examples

      iex> Maybe.to_result({:some, 42}, :not_found)
      {:ok, 42}

      iex> Maybe.to_result(:none, :not_found)
      {:error, :not_found}
  """
  @spec to_result(t(value), error) :: {:ok, value} | {:error, error}
        when value: term(), error: term()
  def to_result({:some, value}, _error), do: {:ok, value}
  def to_result(:none, error), do: {:error, error}

  @doc """
  Converts to a boolean.

  ## Examples

      iex> Maybe.to_bool({:some, 42})
      true

      iex> Maybe.to_bool(:none)
      false
  """
  @spec to_bool(t()) :: boolean()
  def to_bool({:some, _}), do: true
  def to_bool(:none), do: false

  @doc """
  Converts to a list.

  ## Examples

      iex> Maybe.to_list({:some, 42})
      [42]

      iex> Maybe.to_list(:none)
      []
  """
  @spec to_list(t(value)) :: [value] when value: term()
  @impl FnTypes.Behaviours.Reducible
  def to_list({:some, value}), do: [value]
  def to_list(:none), do: []

  # ============================================
  # Collection Operations
  # ============================================

  @doc """
  Collects a list of maybes into a maybe of list.

  Returns some only if all values are some.

  ## Examples

      iex> Maybe.collect([{:some, 1}, {:some, 2}, {:some, 3}])
      {:some, [1, 2, 3]}

      iex> Maybe.collect([{:some, 1}, :none, {:some, 3}])
      :none

      iex> Maybe.collect([])
      {:some, []}
  """
  @spec collect([t(a)]) :: t([a]) when a: term()
  def collect(maybes) when is_list(maybes) do
    Enum.reduce_while(maybes, {:some, []}, fn
      {:some, value}, {:some, acc} -> {:cont, {:some, [value | acc]}}
      :none, _ -> {:halt, :none}
    end)
    |> case do
      {:some, list} -> {:some, Enum.reverse(list)}
      :none -> :none
    end
  end

  @doc """
  Sequences a list of maybes into a maybe of list.

  Alias for `collect/1`. Provided for Traversable behaviour compliance.

  ## Examples

      iex> Maybe.sequence([{:some, 1}, {:some, 2}, {:some, 3}])
      {:some, [1, 2, 3]}

      iex> Maybe.sequence([{:some, 1}, :none, {:some, 3}])
      :none
  """
  @impl FnTypes.Behaviours.Traversable
  @spec sequence([t(a)]) :: t([a]) when a: term()
  def sequence(maybes), do: collect(maybes)

  @doc """
  Filters a list keeping only some values, unwrapped.

  Named to match `Result.cat_ok/1` and `Result.cat_errors/1` pattern.

  ## Examples

      iex> Maybe.cat_somes([{:some, 1}, :none, {:some, 3}])
      [1, 3]

      iex> Maybe.cat_somes([:none, :none])
      []
  """
  @spec cat_somes([t(a)]) :: [a] when a: term()
  def cat_somes(maybes) when is_list(maybes) do
    maybes
    |> Enum.filter(&some?/1)
    |> Enum.map(&unwrap!/1)
  end

  @doc false
  @deprecated "Use cat_somes/1 instead"
  def cat_maybes(maybes), do: cat_somes(maybes)

  @doc """
  Applies a maybe-returning function to each element.

  ## Examples

      iex> Maybe.traverse([1, 2, 3], fn x -> {:some, x * 2} end)
      {:some, [2, 4, 6]}

      iex> Maybe.traverse([1, 2, 3], fn
      ...>   2 -> :none
      ...>   x -> {:some, x * 2}
      ...> end)
      :none
  """
  @impl FnTypes.Behaviours.Traversable
  @spec traverse([a], (a -> t(b))) :: t([b]) when a: term(), b: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> collect()
  end

  @doc """
  Maps and filters in one pass, keeping only some results.

  ## Examples

      iex> Maybe.filter_map([1, 2, 3, 4], fn
      ...>   x when rem(x, 2) == 0 -> {:some, x * 10}
      ...>   _ -> :none
      ...> end)
      [20, 40]
  """
  @spec filter_map([a], (a -> t(b))) :: [b] when a: term(), b: term()
  def filter_map(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> cat_somes()
  end

  # ============================================
  # Flattening
  # ============================================

  @doc """
  Flattens a nested maybe.

  ## Examples

      iex> Maybe.flatten({:some, {:some, 42}})
      {:some, 42}

      iex> Maybe.flatten({:some, :none})
      :none

      iex> Maybe.flatten(:none)
      :none

      iex> Maybe.flatten({:some, 42})
      {:some, 42}
  """
  @spec flatten(t(t(a))) :: t(a) when a: term()
  def flatten({:some, {:some, _} = inner}), do: inner
  def flatten({:some, :none}), do: :none
  def flatten({:some, value}), do: {:some, value}
  def flatten(:none), do: :none

  # ============================================
  # Applicative
  # ============================================

  @doc """
  Applies a wrapped function to a wrapped value.

  Applicative functor pattern - useful for applying functions
  that are themselves wrapped in Maybe.

  ## Examples

      iex> Maybe.apply({:some, &String.upcase/1}, {:some, "hello"})
      {:some, "HELLO"}

      iex> Maybe.apply(:none, {:some, "hello"})
      :none

      iex> Maybe.apply({:some, &String.upcase/1}, :none)
      :none

      iex> Maybe.apply({:some, fn a, b -> a + b end}, {:some, 1}, {:some, 2})
      {:some, 3}
  """
  @spec apply(t((a -> b)), t(a)) :: t(b) when a: term(), b: term()
  def apply({:some, fun}, {:some, value}) when is_function(fun, 1), do: {:some, fun.(value)}
  def apply(:none, _), do: :none
  def apply(_, :none), do: :none

  @spec apply(t((a, b -> c)), t(a), t(b)) :: t(c) when a: term(), b: term(), c: term()
  def apply({:some, fun}, {:some, a}, {:some, b}) when is_function(fun, 2), do: {:some, fun.(a, b)}
  def apply(:none, _, _), do: :none
  def apply(_, :none, _), do: :none
  def apply(_, _, :none), do: :none

  # ============================================
  # Zipping
  # ============================================

  @doc """
  Zips two maybes into a maybe of tuple.

  Alias for `combine/2` with clearer semantics for parallel combination.

  ## Examples

      iex> Maybe.zip({:some, 1}, {:some, 2})
      {:some, {1, 2}}

      iex> Maybe.zip(:none, {:some, 2})
      :none

      iex> Maybe.zip({:some, 1}, :none)
      :none
  """
  @spec zip(t(a), t(b)) :: t({a, b}) when a: term(), b: term()
  def zip(maybe_a, maybe_b), do: combine(maybe_a, maybe_b)

  @doc """
  Zips two maybes with a combining function.

  Alias for `combine_with/3` with clearer semantics.

  ## Examples

      iex> Maybe.zip_with({:some, 2}, {:some, 3}, &(&1 + &2))
      {:some, 5}

      iex> Maybe.zip_with(:none, {:some, 3}, &(&1 + &2))
      :none

      iex> Maybe.zip_with({:some, "Hello, "}, {:some, "World!"}, &<>/2)
      {:some, "Hello, World!"}
  """
  @spec zip_with(t(a), t(b), (a, b -> c)) :: t(c) when a: term(), b: term(), c: term()
  def zip_with(maybe_a, maybe_b, fun), do: combine_with(maybe_a, maybe_b, fun)

  @doc """
  Zips a list of maybes into a maybe of list.

  Returns some only if all values are some. Alias for `collect/1`.

  ## Examples

      iex> Maybe.zip_all([{:some, 1}, {:some, 2}, {:some, 3}])
      {:some, [1, 2, 3]}

      iex> Maybe.zip_all([{:some, 1}, :none, {:some, 3}])
      :none
  """
  @spec zip_all([t(a)]) :: t([a]) when a: term()
  def zip_all(maybes), do: collect(maybes)

  # ============================================
  # Combining
  # ============================================

  @doc """
  Combines two maybes into a maybe of tuple.

  ## Examples

      iex> Maybe.combine({:some, 1}, {:some, 2})
      {:some, {1, 2}}

      iex> Maybe.combine(:none, {:some, 2})
      :none

      iex> Maybe.combine({:some, 1}, :none)
      :none
  """
  @spec combine(t(a), t(b)) :: t({a, b}) when a: term(), b: term()
  def combine({:some, a}, {:some, b}), do: {:some, {a, b}}
  def combine(:none, _), do: :none
  def combine(_, :none), do: :none

  @doc """
  Combines two maybes with a function.

  ## Examples

      iex> Maybe.combine_with({:some, 2}, {:some, 3}, &(&1 + &2))
      {:some, 5}

      iex> Maybe.combine_with(:none, {:some, 3}, &(&1 + &2))
      :none
  """
  @spec combine_with(t(a), t(b), (a, b -> c)) :: t(c) when a: term(), b: term(), c: term()
  def combine_with({:some, a}, {:some, b}, fun) when is_function(fun, 2) do
    {:some, fun.(a, b)}
  end

  def combine_with(:none, _, _), do: :none
  def combine_with(_, :none, _), do: :none

  @doc """
  Returns the first some from a list of lazy maybes.

  Functions are evaluated lazily, stopping at first some.

  ## Examples

      iex> Maybe.first_some([
      ...>   fn -> :none end,
      ...>   fn -> {:some, 42} end,
      ...>   fn -> raise "never called" end
      ...> ])
      {:some, 42}

      iex> Maybe.first_some([
      ...>   fn -> :none end,
      ...>   fn -> :none end
      ...> ])
      :none
  """
  @spec first_some([(-> t(a))]) :: t(a) when a: term()
  def first_some(funs) when is_list(funs) do
    Enum.reduce_while(funs, :none, fn fun, _acc ->
      case fun.() do
        {:some, _} = some -> {:halt, some}
        :none -> {:cont, :none}
      end
    end)
  end

  # ============================================
  # Utility
  # ============================================

  @doc """
  Taps into some value for side effects.

  ## Examples

      iex> {:some, 42} |> Maybe.tap_some(&IO.inspect/1)
      # Prints: 42
      {:some, 42}

      iex> :none |> Maybe.tap_some(&IO.inspect/1)
      # Nothing printed
      :none
  """
  @spec tap_some(t(a), (a -> any())) :: t(a) when a: term()
  def tap_some({:some, value} = maybe, fun) when is_function(fun, 1) do
    fun.(value)
    maybe
  end

  def tap_some(:none, _fun), do: :none

  @doc """
  Taps into none for side effects.

  ## Examples

      iex> :none |> Maybe.tap_none(fn -> IO.puts("was none") end)
      # Prints: was none
      :none
  """
  @spec tap_none(t(a), (-> any())) :: t(a) when a: term()
  def tap_none(:none, fun) when is_function(fun, 0) do
    fun.()
    :none
  end

  def tap_none({:some, _} = some, _fun), do: some

  @doc """
  Returns some if condition is true, none otherwise.

  Useful for conditional values.

  ## Examples

      iex> Maybe.when_true(true, 42)
      {:some, 42}

      iex> Maybe.when_true(false, 42)
      :none
  """
  @spec when_true(boolean(), value) :: t(value) when value: term()
  def when_true(true, value), do: {:some, value}
  def when_true(false, _value), do: :none

  @doc """
  Returns some with lazy value if condition is true.

  ## Examples

      iex> Maybe.when_true_lazy(true, fn -> 42 end)
      {:some, 42}

      iex> Maybe.when_true_lazy(false, fn -> 42 end)
      :none
  """
  @spec when_true_lazy(boolean(), (-> value)) :: t(value) when value: term()
  def when_true_lazy(true, fun) when is_function(fun, 0), do: {:some, fun.()}
  def when_true_lazy(false, _fun), do: :none

  @doc """
  Returns some if condition is false, none otherwise.

  Inverse of `when_true/2`.

  ## Examples

      iex> Maybe.unless_true(false, 42)
      {:some, 42}

      iex> Maybe.unless_true(true, 42)
      :none
  """
  @spec unless_true(boolean(), value) :: t(value) when value: term()
  def unless_true(false, value), do: {:some, value}
  def unless_true(true, _value), do: :none

  @doc """
  Returns some with lazy value if condition is false.

  Inverse of `when_true_lazy/2`.

  ## Examples

      iex> Maybe.unless_true_lazy(false, fn -> 42 end)
      {:some, 42}

      iex> Maybe.unless_true_lazy(true, fn -> 42 end)
      :none
  """
  @spec unless_true_lazy(boolean(), (-> value)) :: t(value) when value: term()
  def unless_true_lazy(false, fun) when is_function(fun, 0), do: {:some, fun.()}
  def unless_true_lazy(true, _fun), do: :none

  # ============================================
  # Map/Struct Access
  # ============================================

  @doc """
  Gets a value from a map/struct, returning maybe.

  ## Examples

      iex> Maybe.get(%{name: "Alice"}, :name)
      {:some, "Alice"}

      iex> Maybe.get(%{name: "Alice"}, :age)
      :none

      iex> Maybe.get(%{name: nil}, :name)
      :none
  """
  @spec get(map(), atom() | String.t()) :: t(term())
  def get(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, nil} -> :none
      {:ok, value} -> {:some, value}
      :error -> :none
    end
  end

  @doc """
  Gets a nested value from a map/struct following a path.

  ## Examples

      iex> Maybe.fetch_path(%{user: %{profile: %{name: "Alice"}}}, [:user, :profile, :name])
      {:some, "Alice"}

      iex> Maybe.fetch_path(%{user: %{profile: nil}}, [:user, :profile, :name])
      :none

      iex> Maybe.fetch_path(%{user: nil}, [:user, :profile, :name])
      :none
  """
  @spec fetch_path(map(), [atom() | String.t()]) :: t(term())
  def fetch_path(map, []), do: from_nilable(map)

  def fetch_path(map, [key | rest]) when is_map(map) do
    case get(map, key) do
      {:some, value} -> fetch_path(value, rest)
      :none -> :none
    end
  end

  def fetch_path(_, _), do: :none

  # ============================================
  # Function Lifting
  # ============================================

  @doc """
  Lifts a regular function to work on Maybe values.

  Returns a new function that takes a Maybe and applies the
  original function to the wrapped value if present.

  ## Examples

      iex> upcase = Maybe.lift(&String.upcase/1)
      iex> upcase.({:some, "hello"})
      {:some, "HELLO"}

      iex> upcase = Maybe.lift(&String.upcase/1)
      iex> upcase.(:none)
      :none

      iex> add = Maybe.lift(&(&1 + &2))
      iex> add.({:some, 1}, {:some, 2})
      {:some, 3}
  """
  @spec lift((a -> b)) :: (t(a) -> t(b)) when a: term(), b: term()
  def lift(fun) when is_function(fun, 1) do
    fn maybe -> map(maybe, fun) end
  end

  @spec lift((a, b -> c)) :: (t(a), t(b) -> t(c)) when a: term(), b: term(), c: term()
  def lift(fun) when is_function(fun, 2) do
    fn maybe_a, maybe_b -> combine_with(maybe_a, maybe_b, fun) end
  end

  @doc """
  Lifts a function and immediately applies it to Maybe values.

  Convenience for `lift(fun).(maybe)`.

  ## Examples

      iex> Maybe.lift_apply(&String.upcase/1, {:some, "hello"})
      {:some, "HELLO"}

      iex> Maybe.lift_apply(&+/2, {:some, 1}, {:some, 2})
      {:some, 3}
  """
  @spec lift_apply((a -> b), t(a)) :: t(b) when a: term(), b: term()
  def lift_apply(fun, maybe) when is_function(fun, 1), do: map(maybe, fun)

  @spec lift_apply((a, b -> c), t(a), t(b)) :: t(c) when a: term(), b: term(), c: term()
  def lift_apply(fun, maybe_a, maybe_b) when is_function(fun, 2) do
    combine_with(maybe_a, maybe_b, fun)
  end

  # ============================================
  # Enumerable Support
  # ============================================

  @doc """
  Converts a Maybe to an enumerable (list).

  Enables using Maybe values with Enum functions.

  ## Examples

      iex> Maybe.to_enum({:some, 42})
      [42]

      iex> Maybe.to_enum(:none)
      []

      iex> {:some, 5} |> Maybe.to_enum() |> Enum.map(&(&1 * 2))
      [10]
  """
  @spec to_enum(t(a)) :: [a] when a: term()
  def to_enum({:some, value}), do: [value]
  def to_enum(:none), do: []

  @doc """
  Reduces over a Maybe value.

  Provides Enum.reduce-like semantics for Maybe.

  ## Examples

      iex> Maybe.reduce({:some, 5}, 0, &+/2)
      5

      iex> Maybe.reduce(:none, 0, &+/2)
      0
  """
  @spec reduce(t(a), acc, (a, acc -> acc)) :: acc when a: term(), acc: term()
  def reduce({:some, value}, acc, fun) when is_function(fun, 2), do: fun.(value, acc)
  def reduce(:none, acc, _fun), do: acc

  # ============================================
  # Behaviour Implementations
  # ============================================

  @doc """
  Wraps a value in a some (Monad.pure).

  Alias for `some/1`.

  ## Examples

      iex> Maybe.pure(42)
      {:some, 42}
  """
  @impl FnTypes.Behaviours.Combinable
  @spec pure(value) :: some(value) when value: term()
  def pure(value), do: some(value)

  @doc """
  Chains a function that returns a Maybe (Monad.bind).

  Alias for `and_then/2`.

  ## Examples

      iex> Maybe.bind({:some, 5}, fn x -> {:some, x * 2} end)
      {:some, 10}
  """
  @impl FnTypes.Behaviours.Chainable
  @spec bind(t(a), (a -> t(b))) :: t(b) when a: term(), b: term()
  def bind(maybe, fun), do: and_then(maybe, fun)

  @doc """
  Applies a wrapped function to a wrapped value (Applicative.ap).

  Alias for `apply/2`.

  ## Examples

      iex> Maybe.ap({:some, fn x -> x * 2 end}, {:some, 5})
      {:some, 10}
  """
  @impl FnTypes.Behaviours.Combinable
  @spec ap(t((a -> b)), t(a)) :: t(b) when a: term(), b: term()
  def ap(maybe_fun, maybe_val), do: apply(maybe_fun, maybe_val)

  @doc """
  Left fold over the present value (Foldable.fold_left).

  Applies the function to the present value and accumulator.
  Returns the accumulator unchanged for none.

  ## Examples

      iex> Maybe.fold_left({:some, 5}, 10, &+/2)
      15

      iex> Maybe.fold_left(:none, 10, &+/2)
      10
  """
  @impl FnTypes.Behaviours.Reducible
  @spec fold_left(t(a), acc, (a, acc -> acc)) :: acc when a: term(), acc: term()
  def fold_left({:some, value}, acc, fun) when is_function(fun, 2), do: fun.(value, acc)
  def fold_left(:none, acc, _fun), do: acc

  @doc """
  Right fold over the present value (Foldable.fold_right).

  For single-value containers like Maybe, equivalent to fold_left.

  ## Examples

      iex> Maybe.fold_right({:some, 5}, 10, &+/2)
      15
  """
  @impl FnTypes.Behaviours.Reducible
  @spec fold_right(t(a), acc, (a, acc -> acc)) :: acc when a: term(), acc: term()
  def fold_right({:some, value}, acc, fun) when is_function(fun, 2), do: fun.(value, acc)
  def fold_right(:none, acc, _fun), do: acc
end
