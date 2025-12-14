defmodule FnTypes.Ior do
  @moduledoc """
  Inclusive Or - represents success with warnings, failure, or success.

  `Ior` (Inclusive Or) fills the gap between `Result` and `Validation`:
  - `Result`: Either success OR failure (exclusive)
  - `Validation`: Accumulates errors, no value if any error
  - `Ior`: Can have BOTH a value AND accumulated warnings/errors

  ## Implemented Behaviours

  - `FnTypes.Behaviours.Monad` - pure, bind, map
  - `FnTypes.Behaviours.Applicative` - pure, ap, map
  - `FnTypes.Behaviours.Functor` - map
  - `FnTypes.Behaviours.Semigroup` - combine (warning accumulation)

  ## Representation

  - `{:right, value}` - Pure success, no warnings
  - `{:left, errors}` - Failure, no value
  - `{:both, errors, value}` - Success with warnings

  ## Use Cases

  - Parsing with warnings (deprecated fields, type coercions)
  - Configuration loading (missing optional values)
  - Data import (partial success with issues)
  - API responses that succeed but have warnings

  ## Example

      alias FnTypes.Ior

      # Parse config that may have deprecation warnings
      def parse_config(params) do
        Ior.right(%{})
        |> Ior.and_then(fn config ->
          case params[:old_api_key] do
            nil -> Ior.right(config)
            key -> Ior.both([:deprecated_old_api_key], Map.put(config, :api_key, key))
          end
        end)
        |> Ior.and_then(fn config ->
          case params[:timeout] do
            nil -> Ior.right(Map.put(config, :timeout, 5000))
            val when is_integer(val) -> Ior.right(Map.put(config, :timeout, val))
            val -> Ior.left([:invalid_timeout])
          end
        end)
      end

      parse_config(%{old_api_key: "abc123", timeout: 3000})
      #=> {:both, [:deprecated_old_api_key], %{api_key: "abc123", timeout: 3000}}

  ## Comparison with Result and Validation

  | Type | Fail-Fast? | Accumulates? | Value on Error? |
  |------|------------|--------------|-----------------|
  | Result | Yes | No | No |
  | Validation | No | Yes | No |
  | Ior | No | Yes | Yes (with warnings) |

  """

  @behaviour FnTypes.Behaviours.Monad
  @behaviour FnTypes.Behaviours.Applicative
  @behaviour FnTypes.Behaviours.Functor
  @behaviour FnTypes.Behaviours.Semigroup

  alias FnTypes.{Result, Maybe}

  # ============================================
  # Types
  # ============================================

  @type value :: term()
  @type error :: term()
  @type errors :: [error()]

  @type right(a) :: {:right, a}
  @type left(e) :: {:left, [e]}
  @type both(e, a) :: {:both, [e], a}

  @type t(a, e) :: right(a) | left(e) | both(e, a)
  @type t(a) :: t(a, term())
  @type t() :: t(term(), term())

  # ============================================
  # Construction
  # ============================================

  @doc """
  Creates a pure success (right) with no warnings.

  ## Examples

      iex> Ior.right(42)
      {:right, 42}
  """
  @spec right(a) :: right(a) when a: term()
  def right(value), do: {:right, value}

  @doc """
  Creates a failure (left) with errors.

  ## Examples

      iex> Ior.left(:not_found)
      {:left, [:not_found]}

      iex> Ior.left([:error1, :error2])
      {:left, [:error1, :error2]}
  """
  @spec left(error() | errors()) :: left(error())
  def left(errors) when is_list(errors), do: {:left, errors}
  def left(error), do: {:left, [error]}

  @doc """
  Creates a success with warnings (both).

  ## Examples

      iex> Ior.both(:deprecated_field, %{value: 42})
      {:both, [:deprecated_field], %{value: 42}}

      iex> Ior.both([:warn1, :warn2], "processed")
      {:both, [:warn1, :warn2], "processed"}
  """
  @spec both(error() | errors(), a) :: both(error(), a) when a: term()
  def both(errors, value) when is_list(errors), do: {:both, errors, value}
  def both(error, value), do: {:both, [error], value}

  # ============================================
  # Type Checking
  # ============================================

  @doc """
  Checks if this is a right (pure success).

  ## Examples

      iex> Ior.right?(Ior.right(42))
      true

      iex> Ior.right?(Ior.both(:warn, 42))
      false

      iex> Ior.right?(Ior.left(:error))
      false
  """
  @spec right?(t()) :: boolean()
  def right?({:right, _}), do: true
  def right?(_), do: false

  @doc """
  Checks if this is a left (failure).

  ## Examples

      iex> Ior.left?(Ior.left(:error))
      true

      iex> Ior.left?(Ior.right(42))
      false

      iex> Ior.left?(Ior.both(:warn, 42))
      false
  """
  @spec left?(t()) :: boolean()
  def left?({:left, _}), do: true
  def left?(_), do: false

  @doc """
  Checks if this is a both (success with warnings).

  ## Examples

      iex> Ior.both?(Ior.both(:warn, 42))
      true

      iex> Ior.both?(Ior.right(42))
      false
  """
  @spec both?(t()) :: boolean()
  def both?({:both, _, _}), do: true
  def both?(_), do: false

  @doc """
  Checks if this has a value (right or both).

  ## Examples

      iex> Ior.has_value?(Ior.right(42))
      true

      iex> Ior.has_value?(Ior.both(:warn, 42))
      true

      iex> Ior.has_value?(Ior.left(:error))
      false
  """
  @spec has_value?(t()) :: boolean()
  def has_value?({:right, _}), do: true
  def has_value?({:both, _, _}), do: true
  def has_value?({:left, _}), do: false

  @doc """
  Checks if this has errors/warnings (left or both).

  ## Examples

      iex> Ior.has_errors?(Ior.left(:error))
      true

      iex> Ior.has_errors?(Ior.both(:warn, 42))
      true

      iex> Ior.has_errors?(Ior.right(42))
      false
  """
  @spec has_errors?(t()) :: boolean()
  def has_errors?({:left, _}), do: true
  def has_errors?({:both, _, _}), do: true
  def has_errors?({:right, _}), do: false

  # ============================================
  # Functor Operations (map)
  # ============================================

  @doc """
  Maps a function over the value (if present).

  ## Examples

      iex> Ior.map(Ior.right(5), &(&1 * 2))
      {:right, 10}

      iex> Ior.map(Ior.both(:warn, 5), &(&1 * 2))
      {:both, [:warn], 10}

      iex> Ior.map(Ior.left(:error), &(&1 * 2))
      {:left, [:error]}
  """
  @spec map(t(a, e), (a -> b)) :: t(b, e) when a: term(), b: term(), e: term()
  @impl FnTypes.Behaviours.Functor
  def map({:right, value}, fun) when is_function(fun, 1), do: {:right, fun.(value)}
  def map({:both, errors, value}, fun) when is_function(fun, 1), do: {:both, errors, fun.(value)}
  def map({:left, _} = left, _fun), do: left

  @doc """
  Maps a function over the errors.

  ## Examples

      iex> Ior.map_left(Ior.left(:error), &Atom.to_string/1)
      {:left, ["error"]}

      iex> Ior.map_left(Ior.both(:warn, 42), &Atom.to_string/1)
      {:both, ["warn"], 42}

      iex> Ior.map_left(Ior.right(42), &Atom.to_string/1)
      {:right, 42}
  """
  @spec map_left(t(a, e1), (e1 -> e2)) :: t(a, e2) when a: term(), e1: term(), e2: term()
  def map_left({:left, errors}, fun) when is_function(fun, 1), do: {:left, Enum.map(errors, fun)}

  def map_left({:both, errors, value}, fun) when is_function(fun, 1) do
    {:both, Enum.map(errors, fun), value}
  end

  def map_left({:right, _} = right, _fun), do: right

  @doc """
  Maps both value and errors simultaneously.

  ## Examples

      iex> Ior.bimap(Ior.right(5), &(&1 * 2), &Atom.to_string/1)
      {:right, 10}

      iex> Ior.bimap(Ior.both(:warn, 5), &(&1 * 2), &Atom.to_string/1)
      {:both, ["warn"], 10}

      iex> Ior.bimap(Ior.left(:error), &(&1 * 2), &Atom.to_string/1)
      {:left, ["error"]}
  """
  @spec bimap(t(a, e1), (a -> b), (e1 -> e2)) :: t(b, e2)
        when a: term(), b: term(), e1: term(), e2: term()
  def bimap({:right, value}, value_fun, _error_fun), do: {:right, value_fun.(value)}

  def bimap({:both, errors, value}, value_fun, error_fun) do
    {:both, Enum.map(errors, error_fun), value_fun.(value)}
  end

  def bimap({:left, errors}, _value_fun, error_fun), do: {:left, Enum.map(errors, error_fun)}

  # ============================================
  # Monad Operations (and_then/bind)
  # ============================================

  @doc """
  Chains an Ior-returning function over the value.

  Accumulates errors from both this Ior and the result of the function.
  If either is left, the result is left with combined errors.

  ## Examples

      iex> Ior.right(5) |> Ior.and_then(fn x -> Ior.right(x * 2) end)
      {:right, 10}

      iex> Ior.right(5) |> Ior.and_then(fn x -> Ior.both(:computed, x * 2) end)
      {:both, [:computed], 10}

      iex> Ior.both(:input_warn, 5) |> Ior.and_then(fn x -> Ior.both(:computed, x * 2) end)
      {:both, [:input_warn, :computed], 10}

      iex> Ior.both(:warn, 5) |> Ior.and_then(fn _ -> Ior.left(:failed) end)
      {:left, [:warn, :failed]}

      iex> Ior.left(:error) |> Ior.and_then(fn x -> Ior.right(x * 2) end)
      {:left, [:error]}
  """
  @spec and_then(t(a, e), (a -> t(b, e))) :: t(b, e) when a: term(), b: term(), e: term()
  def and_then({:right, value}, fun) when is_function(fun, 1), do: fun.(value)

  def and_then({:both, errors, value}, fun) when is_function(fun, 1) do
    case fun.(value) do
      {:right, new_value} -> {:both, errors, new_value}
      {:both, new_errors, new_value} -> {:both, errors ++ new_errors, new_value}
      {:left, new_errors} -> {:left, errors ++ new_errors}
    end
  end

  def and_then({:left, _} = left, _fun), do: left

  @doc """
  Chains a function that returns an Ior (Monad.bind).

  Alias for `and_then/2`.
  """
  @impl FnTypes.Behaviours.Monad
  @spec bind(t(a, e), (a -> t(b, e))) :: t(b, e) when a: term(), b: term(), e: term()
  def bind(ior, fun), do: and_then(ior, fun)

  @doc """
  Flattens a nested Ior.

  ## Examples

      iex> Ior.flatten(Ior.right(Ior.right(42)))
      {:right, 42}

      iex> Ior.flatten(Ior.right(Ior.both(:inner, 42)))
      {:both, [:inner], 42}

      iex> Ior.flatten(Ior.both(:outer, Ior.both(:inner, 42)))
      {:both, [:outer, :inner], 42}
  """
  @spec flatten(t(t(a, e), e)) :: t(a, e) when a: term(), e: term()
  def flatten({:right, {:right, value}}), do: {:right, value}
  def flatten({:right, {:both, errors, value}}), do: {:both, errors, value}
  def flatten({:right, {:left, errors}}), do: {:left, errors}

  def flatten({:both, outer_errors, {:right, value}}), do: {:both, outer_errors, value}

  def flatten({:both, outer_errors, {:both, inner_errors, value}}) do
    {:both, outer_errors ++ inner_errors, value}
  end

  def flatten({:both, outer_errors, {:left, inner_errors}}),
    do: {:left, outer_errors ++ inner_errors}

  def flatten({:left, _} = left), do: left

  # ============================================
  # Applicative Operations
  # ============================================

  @doc """
  Combines two Iors with a function, accumulating all errors.

  ## Examples

      iex> Ior.map2(Ior.right(1), Ior.right(2), &+/2)
      {:right, 3}

      iex> Ior.map2(Ior.both(:a, 1), Ior.both(:b, 2), &+/2)
      {:both, [:a, :b], 3}

      iex> Ior.map2(Ior.both(:a, 1), Ior.left(:b), &+/2)
      {:left, [:a, :b]}

      iex> Ior.map2(Ior.left(:a), Ior.left(:b), &+/2)
      {:left, [:a, :b]}
  """
  @spec map2(t(a, e), t(b, e), (a, b -> c)) :: t(c, e)
        when a: term(), b: term(), c: term(), e: term()
  @impl FnTypes.Behaviours.Applicative
  def map2({:right, a}, {:right, b}, fun), do: {:right, fun.(a, b)}
  def map2({:right, a}, {:both, errors, b}, fun), do: {:both, errors, fun.(a, b)}
  def map2({:right, _}, {:left, errors}, _fun), do: {:left, errors}
  def map2({:both, errors, a}, {:right, b}, fun), do: {:both, errors, fun.(a, b)}

  def map2({:both, e1, a}, {:both, e2, b}, fun) do
    {:both, e1 ++ e2, fun.(a, b)}
  end

  def map2({:both, e1, _}, {:left, e2}, _fun), do: {:left, e1 ++ e2}
  def map2({:left, errors}, {:right, _}, _fun), do: {:left, errors}
  def map2({:left, e1}, {:both, e2, _}, _fun), do: {:left, e1 ++ e2}
  def map2({:left, e1}, {:left, e2}, _fun), do: {:left, e1 ++ e2}

  @doc """
  Combines three Iors with a function.

  ## Examples

      iex> Ior.map3(Ior.right(1), Ior.right(2), Ior.right(3), fn a, b, c -> a + b + c end)
      {:right, 6}

      iex> Ior.map3(Ior.both(:a, 1), Ior.both(:b, 2), Ior.right(3), fn a, b, c -> a + b + c end)
      {:both, [:a, :b], 6}
  """
  @spec map3(t(a, e), t(b, e), t(c, e), (a, b, c -> d)) :: t(d, e)
        when a: term(), b: term(), c: term(), d: term(), e: term()
  def map3(ior1, ior2, ior3, fun) when is_function(fun, 3) do
    map2(ior1, ior2, fn a, b -> {a, b} end)
    |> map2(ior3, fn {a, b}, c -> fun.(a, b, c) end)
  end

  @doc """
  Applies a wrapped function to a wrapped value.

  ## Examples

      iex> Ior.apply(Ior.right(&String.upcase/1), Ior.right("hello"))
      {:right, "HELLO"}

      iex> Ior.apply(Ior.both(:fn_warn, &String.upcase/1), Ior.both(:val_warn, "hello"))
      {:both, [:fn_warn, :val_warn], "HELLO"}
  """
  @spec apply(t((a -> b), e), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def apply(ior_fun, ior_value), do: map2(ior_fun, ior_value, fn f, v -> f.(v) end)

  # ============================================
  # Collection Operations
  # ============================================

  @doc """
  Combines a list of Iors, accumulating all errors.

  If any are left, returns left with all accumulated errors.
  Otherwise returns right or both with all values.

  ## Examples

      iex> Ior.all([Ior.right(1), Ior.right(2), Ior.right(3)])
      {:right, [1, 2, 3]}

      iex> Ior.all([Ior.right(1), Ior.both(:warn, 2), Ior.right(3)])
      {:both, [:warn], [1, 2, 3]}

      iex> Ior.all([Ior.right(1), Ior.left(:error), Ior.both(:warn, 3)])
      {:left, [:error, :warn]}
  """
  @spec all([t(a, e)]) :: t([a], e) when a: term(), e: term()
  def all([]), do: {:right, []}

  def all(iors) when is_list(iors) do
    Enum.reduce(iors, {:right, []}, fn ior, acc ->
      map2(acc, ior, fn list, val -> list ++ [val] end)
    end)
  end

  @doc """
  Applies an Ior-returning function to each element, accumulating errors.

  ## Examples

      iex> Ior.traverse([1, 2, 3], fn x -> Ior.right(x * 2) end)
      {:right, [2, 4, 6]}

      iex> Ior.traverse([1, 2, 3], fn
      ...>   2 -> Ior.both(:warn_on_2, 4)
      ...>   x -> Ior.right(x * 2)
      ...> end)
      {:both, [:warn_on_2], [2, 4, 6]}
  """
  @spec traverse([a], (a -> t(b, e))) :: t([b], e) when a: term(), b: term(), e: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> all()
  end

  @doc """
  Partitions a list of Iors into separate lists.

  ## Examples

      iex> Ior.partition([Ior.right(1), Ior.left(:a), Ior.both(:b, 2)])
      %{rights: [1], lefts: [[:a]], boths: [{[:b], 2}]}
  """
  @spec partition([t(a, e)]) :: %{rights: [a], lefts: [[e]], boths: [{[e], a}]}
        when a: term(), e: term()
  def partition(iors) when is_list(iors) do
    Enum.reduce(iors, %{rights: [], lefts: [], boths: []}, fn
      {:right, value}, acc -> %{acc | rights: acc.rights ++ [value]}
      {:left, errors}, acc -> %{acc | lefts: acc.lefts ++ [errors]}
      {:both, errors, value}, acc -> %{acc | boths: acc.boths ++ [{errors, value}]}
    end)
  end

  # ============================================
  # Error/Warning Operations
  # ============================================

  @doc """
  Adds a warning/error to the Ior.

  Converts right to both, adds to existing errors in both/left.

  ## Examples

      iex> Ior.add_error(Ior.right(42), :new_warning)
      {:both, [:new_warning], 42}

      iex> Ior.add_error(Ior.both(:existing, 42), :new_warning)
      {:both, [:existing, :new_warning], 42}

      iex> Ior.add_error(Ior.left(:existing), :new_error)
      {:left, [:existing, :new_error]}
  """
  @spec add_error(t(a, e), e) :: t(a, e) when a: term(), e: term()
  def add_error({:right, value}, error), do: {:both, [error], value}
  def add_error({:both, errors, value}, error), do: {:both, errors ++ [error], value}
  def add_error({:left, errors}, error), do: {:left, errors ++ [error]}

  @doc """
  Adds multiple warnings/errors to the Ior.

  ## Examples

      iex> Ior.add_errors(Ior.right(42), [:warn1, :warn2])
      {:both, [:warn1, :warn2], 42}
  """
  @spec add_errors(t(a, e), [e]) :: t(a, e) when a: term(), e: term()
  def add_errors(ior, []), do: ior
  def add_errors({:right, value}, errors), do: {:both, errors, value}
  def add_errors({:both, existing, value}, errors), do: {:both, existing ++ errors, value}
  def add_errors({:left, existing}, errors), do: {:left, existing ++ errors}

  @doc """
  Clears all errors/warnings, keeping the value.

  Converts both to right. Left becomes right with nil.

  ## Examples

      iex> Ior.clear_errors(Ior.both(:warn, 42))
      {:right, 42}

      iex> Ior.clear_errors(Ior.left(:error))
      {:right, nil}
  """
  @spec clear_errors(t(a, e)) :: right(a | nil) when a: term(), e: term()
  def clear_errors({:right, _} = right), do: right
  def clear_errors({:both, _, value}), do: {:right, value}
  def clear_errors({:left, _}), do: {:right, nil}

  @doc """
  Conditionally adds a warning based on a predicate.

  ## Examples

      iex> Ior.warn_if(Ior.right(42), true, :should_warn)
      {:both, [:should_warn], 42}

      iex> Ior.warn_if(Ior.right(42), false, :should_not_warn)
      {:right, 42}

      iex> Ior.warn_if(Ior.right(42), &(&1 > 40), :value_high)
      {:both, [:value_high], 42}
  """
  @spec warn_if(t(a, e), boolean() | (a -> boolean()), e) :: t(a, e) when a: term(), e: term()
  def warn_if(ior, condition, warning)

  def warn_if(ior, true, warning), do: add_error(ior, warning)
  def warn_if(ior, false, _warning), do: ior

  def warn_if({:right, value} = ior, condition, warning) when is_function(condition, 1) do
    if condition.(value), do: add_error(ior, warning), else: ior
  end

  def warn_if({:both, _, value} = ior, condition, warning) when is_function(condition, 1) do
    if condition.(value), do: add_error(ior, warning), else: ior
  end

  def warn_if({:left, _} = left, _condition, _warning), do: left

  @doc """
  Converts warnings to failures based on predicate.

  If the Ior has warnings and the predicate returns true for any,
  converts to left.

  ## Examples

      iex> Ior.fail_if_error(Ior.both(:critical, 42), &(&1 == :critical))
      {:left, [:critical]}

      iex> Ior.fail_if_error(Ior.both(:minor, 42), &(&1 == :critical))
      {:both, [:minor], 42}
  """
  @spec fail_if_error(t(a, e), (e -> boolean())) :: t(a, e) when a: term(), e: term()
  def fail_if_error({:right, _} = right, _pred), do: right

  def fail_if_error({:both, errors, value}, pred) when is_function(pred, 1) do
    if Enum.any?(errors, pred) do
      {:left, errors}
    else
      {:both, errors, value}
    end
  end

  def fail_if_error({:left, _} = left, _pred), do: left

  # ============================================
  # Extraction
  # ============================================

  @doc """
  Gets the value, raising if left.

  ## Examples

      iex> Ior.unwrap!(Ior.right(42))
      42

      iex> Ior.unwrap!(Ior.both(:warn, 42))
      42

      iex> Ior.unwrap!(Ior.left(:error))
      ** (ArgumentError) Cannot unwrap left: [:error]
  """
  @spec unwrap!(t(a, e)) :: a when a: term(), e: term()
  def unwrap!({:right, value}), do: value
  def unwrap!({:both, _, value}), do: value
  def unwrap!({:left, errors}), do: raise(ArgumentError, "Cannot unwrap left: #{inspect(errors)}")

  @doc """
  Gets the value with a default for left.

  ## Examples

      iex> Ior.unwrap_or(Ior.right(42), 0)
      42

      iex> Ior.unwrap_or(Ior.both(:warn, 42), 0)
      42

      iex> Ior.unwrap_or(Ior.left(:error), 0)
      0
  """
  @spec unwrap_or(t(a, e), a) :: a when a: term(), e: term()
  @impl FnTypes.Behaviours.Monad
  def unwrap_or({:right, value}, _default), do: value
  def unwrap_or({:both, _, value}, _default), do: value
  def unwrap_or({:left, _}, default), do: default

  @doc """
  Gets the value or computes default from errors.

  ## Examples

      iex> Ior.unwrap_or_else(Ior.left([:a, :b]), fn errors -> length(errors) end)
      2
  """
  @spec unwrap_or_else(t(a, e), ([e] -> a)) :: a when a: term(), e: term()
  def unwrap_or_else({:right, value}, _fun), do: value
  def unwrap_or_else({:both, _, value}, _fun), do: value
  def unwrap_or_else({:left, errors}, fun) when is_function(fun, 1), do: fun.(errors)

  @doc """
  Gets the errors (empty list for right).

  ## Examples

      iex> Ior.errors(Ior.left([:a, :b]))
      [:a, :b]

      iex> Ior.errors(Ior.both([:warn], 42))
      [:warn]

      iex> Ior.errors(Ior.right(42))
      []
  """
  @spec errors(t(a, e)) :: [e] when a: term(), e: term()
  def errors({:right, _}), do: []
  def errors({:both, errors, _}), do: errors
  def errors({:left, errors}), do: errors

  @doc """
  Gets the value as Maybe.

  ## Examples

      iex> Ior.value(Ior.right(42))
      {:some, 42}

      iex> Ior.value(Ior.both(:warn, 42))
      {:some, 42}

      iex> Ior.value(Ior.left(:error))
      :none
  """
  @spec value(t(a, e)) :: Maybe.t(a) when a: term(), e: term()
  def value({:right, val}), do: {:some, val}
  def value({:both, _, val}), do: {:some, val}
  def value({:left, _}), do: :none

  # ============================================
  # Recovery Operations
  # ============================================

  @doc """
  Recovers from a left using a function.

  ## Examples

      iex> Ior.or_else(Ior.left(:error), fn _ -> Ior.right(0) end)
      {:right, 0}

      iex> Ior.or_else(Ior.right(42), fn _ -> Ior.right(0) end)
      {:right, 42}

      iex> Ior.or_else(Ior.both(:warn, 42), fn _ -> Ior.right(0) end)
      {:both, [:warn], 42}
  """
  @spec or_else(t(a, e), ([e] -> t(a, e))) :: t(a, e) when a: term(), e: term()
  def or_else({:right, _} = right, _fun), do: right
  def or_else({:both, _, _} = both, _fun), do: both
  def or_else({:left, errors}, fun) when is_function(fun, 1), do: fun.(errors)

  @doc """
  Provides a default value for left.

  ## Examples

      iex> Ior.recover(Ior.left(:error), 0)
      {:right, 0}

      iex> Ior.recover(Ior.right(42), 0)
      {:right, 42}
  """
  @spec recover(t(a, e), a) :: t(a, e) when a: term(), e: term()
  def recover({:right, _} = right, _default), do: right
  def recover({:both, _, _} = both, _default), do: both
  def recover({:left, _}, default), do: {:right, default}

  @doc """
  Provides a default value with warnings for left.

  ## Examples

      iex> Ior.recover_with_warning(Ior.left(:error), 0, :used_default)
      {:both, [:used_default], 0}
  """
  @spec recover_with_warning(t(a, e), a, e) :: t(a, e) when a: term(), e: term()
  def recover_with_warning({:right, _} = right, _default, _warning), do: right
  def recover_with_warning({:both, _, _} = both, _default, _warning), do: both
  def recover_with_warning({:left, _}, default, warning), do: {:both, [warning], default}

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts to Result (right/both become ok, left becomes error).

  ## Examples

      iex> Ior.to_result(Ior.right(42))
      {:ok, 42}

      iex> Ior.to_result(Ior.both(:warn, 42))
      {:ok, 42}

      iex> Ior.to_result(Ior.left(:error))
      {:error, [:error]}
  """
  @spec to_result(t(a, e)) :: Result.t(a, [e]) when a: term(), e: term()
  def to_result({:right, value}), do: {:ok, value}
  def to_result({:both, _, value}), do: {:ok, value}
  def to_result({:left, errors}), do: {:error, errors}

  @doc """
  Converts to Result, including warnings in a tuple.

  ## Examples

      iex> Ior.to_result_with_warnings(Ior.right(42))
      {:ok, {42, []}}

      iex> Ior.to_result_with_warnings(Ior.both(:warn, 42))
      {:ok, {42, [:warn]}}

      iex> Ior.to_result_with_warnings(Ior.left(:error))
      {:error, [:error]}
  """
  @spec to_result_with_warnings(t(a, e)) :: Result.t({a, [e]}, [e]) when a: term(), e: term()
  def to_result_with_warnings({:right, value}), do: {:ok, {value, []}}
  def to_result_with_warnings({:both, errors, value}), do: {:ok, {value, errors}}
  def to_result_with_warnings({:left, errors}), do: {:error, errors}

  @doc """
  Creates Ior from Result.

  ## Examples

      iex> Ior.from_result({:ok, 42})
      {:right, 42}

      iex> Ior.from_result({:error, :not_found})
      {:left, [:not_found]}
  """
  @spec from_result(Result.t(a, e)) :: t(a, e) when a: term(), e: term()
  def from_result({:ok, value}), do: {:right, value}
  def from_result({:error, errors}) when is_list(errors), do: {:left, errors}
  def from_result({:error, error}), do: {:left, [error]}

  @doc """
  Converts to Maybe (loses error information).

  ## Examples

      iex> Ior.to_maybe(Ior.right(42))
      {:some, 42}

      iex> Ior.to_maybe(Ior.both(:warn, 42))
      {:some, 42}

      iex> Ior.to_maybe(Ior.left(:error))
      :none
  """
  @spec to_maybe(t(a, e)) :: Maybe.t(a) when a: term(), e: term()
  def to_maybe({:right, value}), do: {:some, value}
  def to_maybe({:both, _, value}), do: {:some, value}
  def to_maybe({:left, _}), do: :none

  @doc """
  Creates Ior from Maybe.

  ## Examples

      iex> Ior.from_maybe({:some, 42}, :was_none)
      {:right, 42}

      iex> Ior.from_maybe(:none, :was_none)
      {:left, [:was_none]}
  """
  @spec from_maybe(Maybe.t(a), e) :: t(a, e) when a: term(), e: term()
  def from_maybe({:some, value}, _error), do: {:right, value}
  def from_maybe(:none, error), do: {:left, [error]}

  @doc """
  Converts to a tuple for pattern matching.

  ## Examples

      iex> Ior.to_tuple(Ior.right(42))
      {:right, 42, []}

      iex> Ior.to_tuple(Ior.both(:warn, 42))
      {:both, 42, [:warn]}

      iex> Ior.to_tuple(Ior.left(:error))
      {:left, nil, [:error]}
  """
  @spec to_tuple(t(a, e)) :: {:right | :both | :left, a | nil, [e]} when a: term(), e: term()
  def to_tuple({:right, value}), do: {:right, value, []}
  def to_tuple({:both, errors, value}), do: {:both, value, errors}
  def to_tuple({:left, errors}), do: {:left, nil, errors}

  # ============================================
  # Utilities
  # ============================================

  @doc """
  Taps into the value for side effects.

  ## Examples

      Ior.right(42)
      |> Ior.tap(fn v -> IO.puts("Value: \#{v}") end)
      |> Ior.map(&(&1 * 2))
  """
  @spec tap(t(a, e), (a -> any())) :: t(a, e) when a: term(), e: term()
  def tap({:right, value} = ior, fun) when is_function(fun, 1) do
    fun.(value)
    ior
  end

  def tap({:both, _, value} = ior, fun) when is_function(fun, 1) do
    fun.(value)
    ior
  end

  def tap({:left, _} = left, _fun), do: left

  @doc """
  Taps into errors for side effects.

  ## Examples

      ior
      |> Ior.tap_left(fn errs -> Logger.warning("Warnings: \#{inspect(errs)}") end)
  """
  @spec tap_left(t(a, e), ([e] -> any())) :: t(a, e) when a: term(), e: term()
  def tap_left({:right, _} = right, _fun), do: right

  def tap_left({:both, errors, _} = ior, fun) when is_function(fun, 1) do
    fun.(errors)
    ior
  end

  def tap_left({:left, errors} = left, fun) when is_function(fun, 1) do
    fun.(errors)
    left
  end

  @doc """
  Swaps left and right.

  ## Examples

      iex> Ior.swap(Ior.right(42))
      {:left, [42]}

      iex> Ior.swap(Ior.left(:error))
      {:right, [:error]}

      iex> Ior.swap(Ior.both([:warn], 42))
      {:both, [42], [:warn]}
  """
  @spec swap(t(a, e)) :: t([e], a) when a: term(), e: term()
  def swap({:right, value}), do: {:left, [value]}
  def swap({:left, errors}), do: {:right, errors}
  def swap({:both, errors, value}), do: {:both, [value], errors}

  @doc """
  Filters value based on predicate.

  If predicate fails on value, converts to left with given error.

  ## Examples

      iex> Ior.filter(Ior.right(42), &(&1 > 0), :must_be_positive)
      {:right, 42}

      iex> Ior.filter(Ior.right(-1), &(&1 > 0), :must_be_positive)
      {:left, [:must_be_positive]}

      iex> Ior.filter(Ior.both(:warn, 42), &(&1 > 0), :must_be_positive)
      {:both, [:warn], 42}
  """
  @spec filter(t(a, e), (a -> boolean()), e) :: t(a, e) when a: term(), e: term()
  def filter({:right, value}, pred, error) when is_function(pred, 1) do
    if pred.(value), do: {:right, value}, else: {:left, [error]}
  end

  def filter({:both, errors, value}, pred, error) when is_function(pred, 1) do
    if pred.(value), do: {:both, errors, value}, else: {:left, errors ++ [error]}
  end

  def filter({:left, _} = left, _pred, _error), do: left

  @doc """
  Ensures a condition on the value, adding warning if false.

  Unlike filter, this doesn't convert to left - just adds a warning.

  ## Examples

      iex> Ior.ensure(Ior.right(42), &(&1 < 100), :value_high)
      {:right, 42}

      iex> Ior.ensure(Ior.right(150), &(&1 < 100), :value_high)
      {:both, [:value_high], 150}
  """
  @spec ensure(t(a, e), (a -> boolean()), e) :: t(a, e) when a: term(), e: term()
  def ensure({:right, value}, pred, warning) when is_function(pred, 1) do
    if pred.(value), do: {:right, value}, else: {:both, [warning], value}
  end

  def ensure({:both, errors, value}, pred, warning) when is_function(pred, 1) do
    if pred.(value), do: {:both, errors, value}, else: {:both, errors ++ [warning], value}
  end

  def ensure({:left, _} = left, _pred, _warning), do: left

  # ============================================
  # Behaviour Implementations
  # ============================================

  @doc """
  Wraps a value in a right Ior (Monad.pure).

  Alias for `right/1`.

  ## Examples

      iex> Ior.pure(42)
      {:right, 42}
  """
  @impl FnTypes.Behaviours.Applicative
  @spec pure(a) :: right(a) when a: term()
  def pure(value), do: right(value)

  @doc """
  Applies a wrapped function to a wrapped value (Applicative.ap).

  Accumulates warnings from both sides.

  ## Examples

      iex> Ior.ap({:right, fn x -> x * 2 end}, {:right, 5})
      {:right, 10}
  """
  @impl FnTypes.Behaviours.Applicative
  @spec ap(t((a -> b), e), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def ap(ior_fun, ior_val), do: __MODULE__.apply(ior_fun, ior_val)

  @doc """
  Combines two Iors, accumulating warnings (Semigroup.combine).

  For successful Iors, keeps the second value.

  ## Examples

      iex> Ior.combine({:right, 1}, {:right, 2})
      {:right, 2}

      iex> Ior.combine({:both, [:w1], 1}, {:both, [:w2], 2})
      {:both, [:w1, :w2], 2}

      iex> Ior.combine({:left, [:e1]}, {:left, [:e2]})
      {:left, [:e1, :e2]}
  """
  @impl FnTypes.Behaviours.Semigroup
  @spec combine(t(a, e), t(a, e)) :: t(a, e) when a: term(), e: term()
  def combine({:right, _}, {:right, b}), do: {:right, b}
  def combine({:right, _}, {:both, e, b}), do: {:both, e, b}
  def combine({:right, _}, {:left, e}), do: {:left, e}
  def combine({:both, e1, _}, {:right, b}), do: {:both, e1, b}
  def combine({:both, e1, _}, {:both, e2, b}), do: {:both, e1 ++ e2, b}
  def combine({:both, e1, _}, {:left, e2}), do: {:left, e1 ++ e2}
  def combine({:left, e1}, {:right, b}), do: {:both, e1, b}
  def combine({:left, e1}, {:both, e2, b}), do: {:both, e1 ++ e2, b}
  def combine({:left, e1}, {:left, e2}), do: {:left, e1 ++ e2}
end
