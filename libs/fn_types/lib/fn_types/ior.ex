defmodule FnTypes.Ior do
  @moduledoc """
  Inclusive Or - represents success with warnings, failure, or success.

  `Ior` (Inclusive Or) fills the gap between `Result` and `Validation`:
  - `Result`: Either success OR failure (exclusive)
  - `Validation`: Accumulates errors, no value if any error
  - `Ior`: Can have BOTH a value AND accumulated warnings/errors

  ## Implemented Behaviours

  - `FnTypes.Behaviours.Chainable` (Monad) - pure, bind, map
  - `FnTypes.Behaviours.Combinable` (Applicative) - pure, ap, map
  - `FnTypes.Behaviours.Mappable` (Functor) - map
  - `FnTypes.Behaviours.Appendable` (Semigroup) - combine (warning accumulation)
  - `FnTypes.Behaviours.Traversable` - traverse, sequence
  - `FnTypes.Behaviours.BiMappable` (Bifunctor) - bimap, map_failure

  ## Representation

  - `{:success, value}` - Pure success, no warnings
  - `{:failure, errors}` - Failure, no value
  - `{:partial, warnings, value}` - Success with warnings

  ## Use Cases

  - Parsing with warnings (deprecated fields, type coercions)
  - Configuration loading (missing optional values)
  - Data import (partial success with issues)
  - API responses that succeed but have warnings

  ## Example

      alias FnTypes.Ior

      # Parse config that may have deprecation warnings
      def parse_config(params) do
        Ior.success(%{})
        |> Ior.and_then(fn config ->
          case params[:old_api_key] do
            nil -> Ior.success(config)
            key -> Ior.partial([:deprecated_old_api_key], Map.put(config, :api_key, key))
          end
        end)
        |> Ior.and_then(fn config ->
          case params[:timeout] do
            nil -> Ior.success(Map.put(config, :timeout, 5000))
            val when is_integer(val) -> Ior.success(Map.put(config, :timeout, val))
            _val -> Ior.failure([:invalid_timeout])
          end
        end)
      end

      parse_config(%{old_api_key: "abc123", timeout: 3000})
      #=> {:partial, [:deprecated_old_api_key], %{api_key: "abc123", timeout: 3000}}

  ## BiMappable (Bifunctor)

  Transform both success values and failures/warnings with expressive keyword API:

      # Transform both sides
      Ior.bimap(outcome,
        on_success: &process_value/1,
        on_failure: &format_warning/1
      )

      # Transform only failures/warnings
      Ior.bimap(outcome, on_failure: &normalize_error/1)

      # Transform only success
      Ior.bimap(outcome, on_success: &format_response/1)

  ## Comparison with Result and Validation

  | Type | Fail-Fast? | Accumulates? | Value on Error? |
  |------|------------|--------------|-----------------|
  | Result | Yes | No | No |
  | Validation | No | Yes | No |
  | Ior | No | Yes | Yes (with warnings) |

  """

  @behaviour FnTypes.Behaviours.Chainable
  @behaviour FnTypes.Behaviours.Combinable
  @behaviour FnTypes.Behaviours.Mappable
  @behaviour FnTypes.Behaviours.Appendable
  @behaviour FnTypes.Behaviours.Traversable
  @behaviour FnTypes.Behaviours.BiMappable

  alias FnTypes.{Result, Maybe}

  # ============================================
  # Types
  # ============================================

  @type value :: term()
  @type error :: term()
  @type errors :: [error()]

  @typedoc "Pure success with no warnings"
  @type success(a) :: {:success, a}

  @typedoc "Failure with errors"
  @type failure(e) :: {:failure, [e]}

  @typedoc "Partial success with warnings"
  @type partial(e, a) :: {:partial, [e], a}

  @type t(a, e) :: success(a) | failure(e) | partial(e, a)
  @type t(a) :: t(a, term())
  @type t() :: t(term(), term())

  # ============================================
  # Construction
  # ============================================

  @doc """
  Creates a pure success with no warnings.

  ## Examples

      iex> Ior.success(42)
      {:success, 42}

      iex> Ior.success(%{config: "loaded"})
      {:success, %{config: "loaded"}}
  """
  @spec success(a) :: success(a) when a: term()
  def success(value), do: {:success, value}

  @doc """
  Creates a failure with errors.

  ## Examples

      iex> Ior.failure(:not_found)
      {:failure, [:not_found]}

      iex> Ior.failure([:error1, :error2])
      {:failure, [:error1, :error2]}
  """
  @spec failure(error() | errors()) :: failure(error())
  def failure(errors) when is_list(errors), do: {:failure, errors}
  def failure(error), do: {:failure, [error]}

  @doc """
  Creates a partial success with warnings.

  Use this when an operation succeeds but has warnings or non-fatal issues.

  ## Examples

      iex> Ior.partial(:deprecated_field, %{value: 42})
      {:partial, [:deprecated_field], %{value: 42}}

      iex> Ior.partial([:warn1, :warn2], "processed")
      {:partial, [:warn1, :warn2], "processed"}

      # Real-world: Config loaded with deprecation warning
      Ior.partial(:deprecated_api_key, %{api_key: "abc123"})
  """
  @spec partial(error() | errors(), a) :: partial(error(), a) when a: term()
  def partial(errors, value) when is_list(errors), do: {:partial, errors, value}
  def partial(error, value), do: {:partial, [error], value}

  # ============================================
  # Type Checking
  # ============================================

  @doc """
  Checks if this is a pure success (no warnings).

  ## Examples

      iex> Ior.success?(Ior.success(42))
      true

      iex> Ior.success?(Ior.partial(:warn, 42))
      false

      iex> Ior.success?(Ior.failure(:error))
      false
  """
  @spec success?(t()) :: boolean()
  def success?({:success, _}), do: true
  def success?(_), do: false

  @doc """
  Checks if this is a failure.

  ## Examples

      iex> Ior.failure?(Ior.failure(:error))
      true

      iex> Ior.failure?(Ior.success(42))
      false

      iex> Ior.failure?(Ior.partial(:warn, 42))
      false
  """
  @spec failure?(t()) :: boolean()
  def failure?({:failure, _}), do: true
  def failure?(_), do: false

  @doc """
  Checks if this is a partial success (success with warnings).

  ## Examples

      iex> Ior.partial?(Ior.partial(:warn, 42))
      true

      iex> Ior.partial?(Ior.success(42))
      false

      iex> Ior.partial?(Ior.failure(:error))
      false
  """
  @spec partial?(t()) :: boolean()
  def partial?({:partial, _, _}), do: true
  def partial?(_), do: false

  @doc """
  Checks if this has a value (success or partial).

  ## Examples

      iex> Ior.has_value?(Ior.success(42))
      true

      iex> Ior.has_value?(Ior.partial(:warn, 42))
      true

      iex> Ior.has_value?(Ior.failure(:error))
      false
  """
  @spec has_value?(t()) :: boolean()
  def has_value?({:success, _}), do: true
  def has_value?({:partial, _, _}), do: true
  def has_value?({:failure, _}), do: false

  @doc """
  Checks if this has errors/warnings (failure or partial).

  ## Examples

      iex> Ior.has_errors?(Ior.failure(:error))
      true

      iex> Ior.has_errors?(Ior.partial(:warn, 42))
      true

      iex> Ior.has_errors?(Ior.success(42))
      false
  """
  @spec has_errors?(t()) :: boolean()
  def has_errors?({:failure, _}), do: true
  def has_errors?({:partial, _, _}), do: true
  def has_errors?({:success, _}), do: false

  # ============================================
  # Functor Operations (map)
  # ============================================

  @doc """
  Maps a function over the value (if present).

  ## Examples

      iex> Ior.map(Ior.success(5), &(&1 * 2))
      {:success, 10}

      iex> Ior.map(Ior.partial(:warn, 5), &(&1 * 2))
      {:partial, [:warn], 10}

      iex> Ior.map(Ior.failure(:error), &(&1 * 2))
      {:failure, [:error]}
  """
  @spec map(t(a, e), (a -> b)) :: t(b, e) when a: term(), b: term(), e: term()
  @impl FnTypes.Behaviours.Mappable
  def map({:success, value}, fun) when is_function(fun, 1), do: {:success, fun.(value)}

  def map({:partial, errors, value}, fun) when is_function(fun, 1),
    do: {:partial, errors, fun.(value)}

  def map({:failure, _} = failure, _fun), do: failure

  @doc """
  Maps a function over the failures/warnings.

  Part of the BiMappable behaviour. Transforms each error/warning in the list.

  ## Examples

      iex> Ior.map_failure(Ior.failure(:error), &Atom.to_string/1)
      {:failure, ["error"]}

      iex> Ior.map_failure(Ior.partial(:warn, 42), &Atom.to_string/1)
      {:partial, ["warn"], 42}

      iex> Ior.map_failure(Ior.success(42), &Atom.to_string/1)
      {:success, 42}

      # Real-world: Format warnings for logging
      Ior.map_failure(outcome, fn warn ->
        "WARNING: \#{inspect(warn)}"
      end)
  """
  @spec map_failure(t(a, e1), (e1 -> e2)) :: t(a, e2) when a: term(), e1: term(), e2: term()
  def map_failure({:failure, errors}, fun) when is_function(fun, 1),
    do: {:failure, Enum.map(errors, fun)}

  def map_failure({:partial, errors, value}, fun) when is_function(fun, 1) do
    {:partial, Enum.map(errors, fun), value}
  end

  def map_failure({:success, _} = success, _fun), do: success

  # Alias for BiMappable compliance (uses "error" terminology)
  @doc false
  @impl FnTypes.Behaviours.BiMappable
  @spec map_error(t(a, e1), (e1 -> e2)) :: t(a, e2) when a: term(), e1: term(), e2: term()
  def map_error(ior, fun), do: map_failure(ior, fun)

  @doc """
  Maps both value and failures/warnings using keyword options.

  Part of the BiMappable behaviour. Use `on_success:` to transform values
  and `on_failure:` to transform warnings/errors. Either can be omitted.

  ## Examples

      # Transform both sides
      iex> Ior.bimap(Ior.success(5), on_success: &(&1 * 2), on_failure: &Atom.to_string/1)
      {:success, 10}

      iex> Ior.bimap(Ior.partial(:warn, 5), on_success: &(&1 * 2), on_failure: &Atom.to_string/1)
      {:partial, ["warn"], 10}

      iex> Ior.bimap(Ior.failure(:error), on_success: &(&1 * 2), on_failure: &Atom.to_string/1)
      {:failure, ["error"]}

      # Transform only failures (success passes through)
      iex> Ior.bimap(Ior.partial(:warn, 42), on_failure: &Atom.to_string/1)
      {:partial, ["warn"], 42}

      # Transform only success (failures pass through)
      iex> Ior.bimap(Ior.success(5), on_success: &(&1 * 2))
      {:success, 10}

  ## Real-world Examples

      # Format API response with warnings
      parse_config(input)
      |> Ior.bimap(
        on_success: &struct!(Config, &1),
        on_failure: fn warn -> %{type: :warning, message: inspect(warn)} end
      )

      # Log warnings while keeping them
      Ior.bimap(outcome,
        on_failure: fn warn ->
          Logger.warn("Processing warning: \#{inspect(warn)}")
          warn
        end
      )
  """
  @impl FnTypes.Behaviours.BiMappable
  @spec bimap(t(a, e1), keyword()) :: t(b, e2)
        when a: term(), b: term(), e1: term(), e2: term()
  def bimap(ior, opts) when is_list(opts) do
    on_success = Keyword.get(opts, :on_success)
    on_failure = Keyword.get(opts, :on_failure)

    case ior do
      {:success, value} when is_function(on_success, 1) ->
        {:success, on_success.(value)}

      {:success, _} = success ->
        success

      {:partial, errors, value} ->
        new_value = if is_function(on_success, 1), do: on_success.(value), else: value
        new_errors = if is_function(on_failure, 1), do: Enum.map(errors, on_failure), else: errors
        {:partial, new_errors, new_value}

      {:failure, errors} when is_function(on_failure, 1) ->
        {:failure, Enum.map(errors, on_failure)}

      {:failure, _} = failure ->
        failure
    end
  end

  # ============================================
  # Monad Operations (and_then/bind)
  # ============================================

  @doc """
  Chains an Ior-returning function over the value.

  Accumulates warnings from both this Ior and the result of the function.
  If either is a failure, the result is a failure with combined errors.

  ## Examples

      iex> Ior.success(5) |> Ior.and_then(fn x -> Ior.success(x * 2) end)
      {:success, 10}

      iex> Ior.success(5) |> Ior.and_then(fn x -> Ior.partial(:computed, x * 2) end)
      {:partial, [:computed], 10}

      iex> Ior.partial(:input_warn, 5) |> Ior.and_then(fn x -> Ior.partial(:computed, x * 2) end)
      {:partial, [:input_warn, :computed], 10}

      iex> Ior.partial(:warn, 5) |> Ior.and_then(fn _ -> Ior.failure(:failed) end)
      {:failure, [:warn, :failed]}

      iex> Ior.failure(:error) |> Ior.and_then(fn x -> Ior.success(x * 2) end)
      {:failure, [:error]}
  """
  @spec and_then(t(a, e), (a -> t(b, e))) :: t(b, e) when a: term(), b: term(), e: term()
  def and_then({:success, value}, fun) when is_function(fun, 1), do: fun.(value)

  def and_then({:partial, errors, value}, fun) when is_function(fun, 1) do
    case fun.(value) do
      {:success, new_value} -> {:partial, errors, new_value}
      {:partial, new_errors, new_value} -> {:partial, errors ++ new_errors, new_value}
      {:failure, new_errors} -> {:failure, errors ++ new_errors}
    end
  end

  def and_then({:failure, _} = failure, _fun), do: failure

  @doc """
  Chains a function that returns an Ior (Monad.bind).

  Alias for `and_then/2`.
  """
  @impl FnTypes.Behaviours.Chainable
  @spec bind(t(a, e), (a -> t(b, e))) :: t(b, e) when a: term(), b: term(), e: term()
  def bind(ior, fun), do: and_then(ior, fun)

  @doc """
  Flattens a nested Ior.

  ## Examples

      iex> Ior.flatten(Ior.success(Ior.success(42)))
      {:success, 42}

      iex> Ior.flatten(Ior.success(Ior.partial(:inner, 42)))
      {:partial, [:inner], 42}

      iex> Ior.flatten(Ior.partial(:outer, Ior.partial(:inner, 42)))
      {:partial, [:outer, :inner], 42}
  """
  @spec flatten(t(t(a, e), e)) :: t(a, e) when a: term(), e: term()
  def flatten({:success, {:success, value}}), do: {:success, value}
  def flatten({:success, {:partial, errors, value}}), do: {:partial, errors, value}
  def flatten({:success, {:failure, errors}}), do: {:failure, errors}

  def flatten({:partial, outer_errors, {:success, value}}), do: {:partial, outer_errors, value}

  def flatten({:partial, outer_errors, {:partial, inner_errors, value}}) do
    {:partial, outer_errors ++ inner_errors, value}
  end

  def flatten({:partial, outer_errors, {:failure, inner_errors}}),
    do: {:failure, outer_errors ++ inner_errors}

  def flatten({:failure, _} = failure), do: failure

  # ============================================
  # Applicative Operations
  # ============================================

  @doc """
  Combines two Iors with a function, accumulating all warnings/errors.

  ## Examples

      iex> Ior.map2(Ior.success(1), Ior.success(2), &+/2)
      {:success, 3}

      iex> Ior.map2(Ior.partial(:a, 1), Ior.partial(:b, 2), &+/2)
      {:partial, [:a, :b], 3}

      iex> Ior.map2(Ior.partial(:a, 1), Ior.failure(:b), &+/2)
      {:failure, [:a, :b]}

      iex> Ior.map2(Ior.failure(:a), Ior.failure(:b), &+/2)
      {:failure, [:a, :b]}
  """
  @spec map2(t(a, e), t(b, e), (a, b -> c)) :: t(c, e)
        when a: term(), b: term(), c: term(), e: term()
  @impl FnTypes.Behaviours.Combinable
  def map2({:success, a}, {:success, b}, fun), do: {:success, fun.(a, b)}
  def map2({:success, a}, {:partial, errors, b}, fun), do: {:partial, errors, fun.(a, b)}
  def map2({:success, _}, {:failure, errors}, _fun), do: {:failure, errors}
  def map2({:partial, errors, a}, {:success, b}, fun), do: {:partial, errors, fun.(a, b)}

  def map2({:partial, e1, a}, {:partial, e2, b}, fun) do
    {:partial, e1 ++ e2, fun.(a, b)}
  end

  def map2({:partial, e1, _}, {:failure, e2}, _fun), do: {:failure, e1 ++ e2}
  def map2({:failure, errors}, {:success, _}, _fun), do: {:failure, errors}
  def map2({:failure, e1}, {:partial, e2, _}, _fun), do: {:failure, e1 ++ e2}
  def map2({:failure, e1}, {:failure, e2}, _fun), do: {:failure, e1 ++ e2}

  @doc """
  Combines three Iors with a function.

  ## Examples

      iex> Ior.map3(Ior.success(1), Ior.success(2), Ior.success(3), fn a, b, c -> a + b + c end)
      {:success, 6}

      iex> Ior.map3(Ior.partial(:a, 1), Ior.partial(:b, 2), Ior.success(3), fn a, b, c -> a + b + c end)
      {:partial, [:a, :b], 6}
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

      iex> Ior.apply(Ior.success(&String.upcase/1), Ior.success("hello"))
      {:success, "HELLO"}

      iex> Ior.apply(Ior.partial(:fn_warn, &String.upcase/1), Ior.partial(:val_warn, "hello"))
      {:partial, [:fn_warn, :val_warn], "HELLO"}
  """
  @spec apply(t((a -> b), e), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def apply(ior_fun, ior_value), do: map2(ior_fun, ior_value, fn f, v -> f.(v) end)

  # ============================================
  # Collection Operations
  # ============================================

  @doc """
  Combines a list of Iors, accumulating all warnings/errors.

  If any are failures, returns failure with all accumulated errors.
  Otherwise returns success or partial with all values.

  ## Examples

      iex> Ior.all([Ior.success(1), Ior.success(2), Ior.success(3)])
      {:success, [1, 2, 3]}

      iex> Ior.all([Ior.success(1), Ior.partial(:warn, 2), Ior.success(3)])
      {:partial, [:warn], [1, 2, 3]}

      iex> Ior.all([Ior.success(1), Ior.failure(:error), Ior.partial(:warn, 3)])
      {:failure, [:error, :warn]}
  """
  @spec all([t(a, e)]) :: t([a], e) when a: term(), e: term()
  def all([]), do: {:success, []}

  def all(iors) when is_list(iors) do
    Enum.reduce(iors, {:success, []}, fn ior, acc ->
      map2(acc, ior, fn list, val -> list ++ [val] end)
    end)
  end

  @doc """
  Applies an Ior-returning function to each element, accumulating warnings/errors.

  ## Examples

      iex> Ior.traverse([1, 2, 3], fn x -> Ior.success(x * 2) end)
      {:success, [2, 4, 6]}

      iex> Ior.traverse([1, 2, 3], fn
      ...>   2 -> Ior.partial(:warn_on_2, 4)
      ...>   x -> Ior.success(x * 2)
      ...> end)
      {:partial, [:warn_on_2], [2, 4, 6]}
  """
  @impl FnTypes.Behaviours.Traversable
  @spec traverse([a], (a -> t(b, e))) :: t([b], e) when a: term(), b: term(), e: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> all()
  end

  @doc """
  Sequences a list of Iors into an Ior of list.

  Alias for `all/1`. Provided for Traversable behaviour compliance.
  Accumulates all warnings while preserving values.

  ## Examples

      iex> Ior.sequence([Ior.success(1), Ior.success(2)])
      {:success, [1, 2]}

      iex> Ior.sequence([Ior.success(1), Ior.partial(:warn, 2)])
      {:partial, [:warn], [1, 2]}
  """
  @impl FnTypes.Behaviours.Traversable
  @spec sequence([t(a, e)]) :: t([a], e) when a: term(), e: term()
  def sequence(iors), do: all(iors)

  @doc """
  Partitions a list of Iors into separate lists.

  ## Examples

      iex> Ior.partition([Ior.success(1), Ior.failure(:a), Ior.partial(:b, 2)])
      %{successes: [1], failures: [[:a]], partials: [{[:b], 2}]}
  """
  @spec partition([t(a, e)]) :: %{successes: [a], failures: [[e]], partials: [{[e], a}]}
        when a: term(), e: term()
  def partition(iors) when is_list(iors) do
    Enum.reduce(iors, %{successes: [], failures: [], partials: []}, fn
      {:success, value}, acc -> %{acc | successes: acc.successes ++ [value]}
      {:failure, errors}, acc -> %{acc | failures: acc.failures ++ [errors]}
      {:partial, errors, value}, acc -> %{acc | partials: acc.partials ++ [{errors, value}]}
    end)
  end

  # ============================================
  # Error/Warning Operations
  # ============================================

  @doc """
  Adds a warning/error to the Ior.

  Converts success to partial, adds to existing errors in partial/failure.

  ## Examples

      iex> Ior.add_warning(Ior.success(42), :new_warning)
      {:partial, [:new_warning], 42}

      iex> Ior.add_warning(Ior.partial(:existing, 42), :new_warning)
      {:partial, [:existing, :new_warning], 42}

      iex> Ior.add_warning(Ior.failure(:existing), :new_error)
      {:failure, [:existing, :new_error]}
  """
  @spec add_warning(t(a, e), e) :: t(a, e) when a: term(), e: term()
  def add_warning({:success, value}, error), do: {:partial, [error], value}
  def add_warning({:partial, errors, value}, error), do: {:partial, errors ++ [error], value}
  def add_warning({:failure, errors}, error), do: {:failure, errors ++ [error]}

  @doc """
  Adds multiple warnings/errors to the Ior.

  ## Examples

      iex> Ior.add_warnings(Ior.success(42), [:warn1, :warn2])
      {:partial, [:warn1, :warn2], 42}
  """
  @spec add_warnings(t(a, e), [e]) :: t(a, e) when a: term(), e: term()
  def add_warnings(ior, []), do: ior
  def add_warnings({:success, value}, errors), do: {:partial, errors, value}
  def add_warnings({:partial, existing, value}, errors), do: {:partial, existing ++ errors, value}
  def add_warnings({:failure, existing}, errors), do: {:failure, existing ++ errors}

  @doc """
  Clears all warnings/errors, keeping the value.

  Converts partial to success. Failure becomes success with nil.

  ## Examples

      iex> Ior.clear_warnings(Ior.partial(:warn, 42))
      {:success, 42}

      iex> Ior.clear_warnings(Ior.failure(:error))
      {:success, nil}
  """
  @spec clear_warnings(t(a, e)) :: success(a | nil) when a: term(), e: term()
  def clear_warnings({:success, _} = success), do: success
  def clear_warnings({:partial, _, value}), do: {:success, value}
  def clear_warnings({:failure, _}), do: {:success, nil}

  @doc """
  Conditionally adds a warning based on a predicate.

  ## Examples

      iex> Ior.warn_if(Ior.success(42), true, :should_warn)
      {:partial, [:should_warn], 42}

      iex> Ior.warn_if(Ior.success(42), false, :should_not_warn)
      {:success, 42}

      iex> Ior.warn_if(Ior.success(42), &(&1 > 40), :value_high)
      {:partial, [:value_high], 42}
  """
  @spec warn_if(t(a, e), boolean() | (a -> boolean()), e) :: t(a, e) when a: term(), e: term()
  def warn_if(ior, condition, warning)

  def warn_if(ior, true, warning), do: add_warning(ior, warning)
  def warn_if(ior, false, _warning), do: ior

  def warn_if({:success, value} = ior, condition, warning) when is_function(condition, 1) do
    if condition.(value), do: add_warning(ior, warning), else: ior
  end

  def warn_if({:partial, _, value} = ior, condition, warning) when is_function(condition, 1) do
    if condition.(value), do: add_warning(ior, warning), else: ior
  end

  def warn_if({:failure, _} = failure, _condition, _warning), do: failure

  @doc """
  Converts partial to failure based on predicate.

  If the Ior has warnings and the predicate returns true for any,
  converts to failure.

  ## Examples

      iex> Ior.fail_if_warning(Ior.partial(:critical, 42), &(&1 == :critical))
      {:failure, [:critical]}

      iex> Ior.fail_if_warning(Ior.partial(:minor, 42), &(&1 == :critical))
      {:partial, [:minor], 42}
  """
  @spec fail_if_warning(t(a, e), (e -> boolean())) :: t(a, e) when a: term(), e: term()
  def fail_if_warning({:success, _} = success, _pred), do: success

  def fail_if_warning({:partial, errors, value}, pred) when is_function(pred, 1) do
    if Enum.any?(errors, pred) do
      {:failure, errors}
    else
      {:partial, errors, value}
    end
  end

  def fail_if_warning({:failure, _} = failure, _pred), do: failure

  # ============================================
  # Extraction
  # ============================================

  @doc """
  Gets the value, raising if failure.

  ## Examples

      iex> Ior.unwrap!(Ior.success(42))
      42

      iex> Ior.unwrap!(Ior.partial(:warn, 42))
      42

      iex> Ior.unwrap!(Ior.failure(:error))
      ** (ArgumentError) Cannot unwrap failure: [:error]
  """
  @spec unwrap!(t(a, e)) :: a when a: term(), e: term()
  def unwrap!({:success, value}), do: value
  def unwrap!({:partial, _, value}), do: value

  def unwrap!({:failure, errors}),
    do: raise(ArgumentError, "Cannot unwrap failure: #{inspect(errors)}")

  @doc """
  Gets the value with a default for failure.

  ## Examples

      iex> Ior.unwrap_or(Ior.success(42), 0)
      42

      iex> Ior.unwrap_or(Ior.partial(:warn, 42), 0)
      42

      iex> Ior.unwrap_or(Ior.failure(:error), 0)
      0
  """
  @spec unwrap_or(t(a, e), a) :: a when a: term(), e: term()
  @impl FnTypes.Behaviours.Chainable
  def unwrap_or({:success, value}, _default), do: value
  def unwrap_or({:partial, _, value}, _default), do: value
  def unwrap_or({:failure, _}, default), do: default

  @doc """
  Gets the value or computes default from errors.

  ## Examples

      iex> Ior.unwrap_or_else(Ior.failure([:a, :b]), fn errors -> length(errors) end)
      2
  """
  @spec unwrap_or_else(t(a, e), ([e] -> a)) :: a when a: term(), e: term()
  def unwrap_or_else({:success, value}, _fun), do: value
  def unwrap_or_else({:partial, _, value}, _fun), do: value
  def unwrap_or_else({:failure, errors}, fun) when is_function(fun, 1), do: fun.(errors)

  @doc """
  Gets the warnings/errors (empty list for success).

  ## Examples

      iex> Ior.warnings(Ior.failure([:a, :b]))
      [:a, :b]

      iex> Ior.warnings(Ior.partial([:warn], 42))
      [:warn]

      iex> Ior.warnings(Ior.success(42))
      []
  """
  @spec warnings(t(a, e)) :: [e] when a: term(), e: term()
  def warnings({:success, _}), do: []
  def warnings({:partial, errors, _}), do: errors
  def warnings({:failure, errors}), do: errors

  @doc """
  Gets the value as Maybe.

  ## Examples

      iex> Ior.value(Ior.success(42))
      {:some, 42}

      iex> Ior.value(Ior.partial(:warn, 42))
      {:some, 42}

      iex> Ior.value(Ior.failure(:error))
      :none
  """
  @spec value(t(a, e)) :: Maybe.t(a) when a: term(), e: term()
  def value({:success, val}), do: {:some, val}
  def value({:partial, _, val}), do: {:some, val}
  def value({:failure, _}), do: :none

  # ============================================
  # Recovery Operations
  # ============================================

  @doc """
  Recovers from a failure using a function.

  ## Examples

      iex> Ior.or_else(Ior.failure(:error), fn _ -> Ior.success(0) end)
      {:success, 0}

      iex> Ior.or_else(Ior.success(42), fn _ -> Ior.success(0) end)
      {:success, 42}

      iex> Ior.or_else(Ior.partial(:warn, 42), fn _ -> Ior.success(0) end)
      {:partial, [:warn], 42}
  """
  @spec or_else(t(a, e), ([e] -> t(a, e))) :: t(a, e) when a: term(), e: term()
  def or_else({:success, _} = success, _fun), do: success
  def or_else({:partial, _, _} = partial, _fun), do: partial
  def or_else({:failure, errors}, fun) when is_function(fun, 1), do: fun.(errors)

  @doc """
  Provides a default value for failure.

  ## Examples

      iex> Ior.recover(Ior.failure(:error), 0)
      {:success, 0}

      iex> Ior.recover(Ior.success(42), 0)
      {:success, 42}
  """
  @spec recover(t(a, e), a) :: t(a, e) when a: term(), e: term()
  def recover({:success, _} = success, _default), do: success
  def recover({:partial, _, _} = partial, _default), do: partial
  def recover({:failure, _}, default), do: {:success, default}

  @doc """
  Provides a default value with warning for failure.

  ## Examples

      iex> Ior.recover_with_warning(Ior.failure(:error), 0, :used_default)
      {:partial, [:used_default], 0}
  """
  @spec recover_with_warning(t(a, e), a, e) :: t(a, e) when a: term(), e: term()
  def recover_with_warning({:success, _} = success, _default, _warning), do: success
  def recover_with_warning({:partial, _, _} = partial, _default, _warning), do: partial
  def recover_with_warning({:failure, _}, default, warning), do: {:partial, [warning], default}

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts to Result (success/partial become ok, failure becomes error).

  ## Examples

      iex> Ior.to_result(Ior.success(42))
      {:ok, 42}

      iex> Ior.to_result(Ior.partial(:warn, 42))
      {:ok, 42}

      iex> Ior.to_result(Ior.failure(:error))
      {:error, [:error]}
  """
  @spec to_result(t(a, e)) :: Result.t(a, [e]) when a: term(), e: term()
  def to_result({:success, value}), do: {:ok, value}
  def to_result({:partial, _, value}), do: {:ok, value}
  def to_result({:failure, errors}), do: {:error, errors}

  @doc """
  Converts to Result, including warnings in a tuple.

  ## Examples

      iex> Ior.to_result_with_warnings(Ior.success(42))
      {:ok, {42, []}}

      iex> Ior.to_result_with_warnings(Ior.partial(:warn, 42))
      {:ok, {42, [:warn]}}

      iex> Ior.to_result_with_warnings(Ior.failure(:error))
      {:error, [:error]}
  """
  @spec to_result_with_warnings(t(a, e)) :: Result.t({a, [e]}, [e]) when a: term(), e: term()
  def to_result_with_warnings({:success, value}), do: {:ok, {value, []}}
  def to_result_with_warnings({:partial, errors, value}), do: {:ok, {value, errors}}
  def to_result_with_warnings({:failure, errors}), do: {:error, errors}

  @doc """
  Creates Ior from Result.

  ## Examples

      iex> Ior.from_result({:ok, 42})
      {:success, 42}

      iex> Ior.from_result({:error, :not_found})
      {:failure, [:not_found]}
  """
  @spec from_result(Result.t(a, e)) :: t(a, e) when a: term(), e: term()
  def from_result({:ok, value}), do: {:success, value}
  def from_result({:error, errors}) when is_list(errors), do: {:failure, errors}
  def from_result({:error, error}), do: {:failure, [error]}

  @doc """
  Converts to Maybe (loses error information).

  ## Examples

      iex> Ior.to_maybe(Ior.success(42))
      {:some, 42}

      iex> Ior.to_maybe(Ior.partial(:warn, 42))
      {:some, 42}

      iex> Ior.to_maybe(Ior.failure(:error))
      :none
  """
  @spec to_maybe(t(a, e)) :: Maybe.t(a) when a: term(), e: term()
  def to_maybe({:success, value}), do: {:some, value}
  def to_maybe({:partial, _, value}), do: {:some, value}
  def to_maybe({:failure, _}), do: :none

  @doc """
  Creates Ior from Maybe.

  ## Examples

      iex> Ior.from_maybe({:some, 42}, :was_none)
      {:success, 42}

      iex> Ior.from_maybe(:none, :was_none)
      {:failure, [:was_none]}
  """
  @spec from_maybe(Maybe.t(a), e) :: t(a, e) when a: term(), e: term()
  def from_maybe({:some, value}, _error), do: {:success, value}
  def from_maybe(:none, error), do: {:failure, [error]}

  @doc """
  Converts to a tuple for pattern matching.

  ## Examples

      iex> Ior.to_tuple(Ior.success(42))
      {:success, 42, []}

      iex> Ior.to_tuple(Ior.partial(:warn, 42))
      {:partial, 42, [:warn]}

      iex> Ior.to_tuple(Ior.failure(:error))
      {:failure, nil, [:error]}
  """
  @spec to_tuple(t(a, e)) :: {:success | :partial | :failure, a | nil, [e]}
        when a: term(), e: term()
  def to_tuple({:success, value}), do: {:success, value, []}
  def to_tuple({:partial, errors, value}), do: {:partial, value, errors}
  def to_tuple({:failure, errors}), do: {:failure, nil, errors}

  # ============================================
  # Utilities
  # ============================================

  @doc """
  Taps into the value for side effects.

  ## Examples

      Ior.success(42)
      |> Ior.tap(fn v -> IO.puts("Value: \#{v}") end)
      |> Ior.map(&(&1 * 2))
  """
  @spec tap(t(a, e), (a -> any())) :: t(a, e) when a: term(), e: term()
  def tap({:success, value} = ior, fun) when is_function(fun, 1) do
    fun.(value)
    ior
  end

  def tap({:partial, _, value} = ior, fun) when is_function(fun, 1) do
    fun.(value)
    ior
  end

  def tap({:failure, _} = failure, _fun), do: failure

  @doc """
  Taps into warnings/errors for side effects.

  ## Examples

      ior
      |> Ior.tap_warnings(fn warns -> Logger.warning("Warnings: \#{inspect(warns)}") end)
  """
  @spec tap_warnings(t(a, e), ([e] -> any())) :: t(a, e) when a: term(), e: term()
  def tap_warnings({:success, _} = success, _fun), do: success

  def tap_warnings({:partial, errors, _} = ior, fun) when is_function(fun, 1) do
    fun.(errors)
    ior
  end

  def tap_warnings({:failure, errors} = failure, fun) when is_function(fun, 1) do
    fun.(errors)
    failure
  end

  @doc """
  Swaps success and failure.

  ## Examples

      iex> Ior.swap(Ior.success(42))
      {:failure, [42]}

      iex> Ior.swap(Ior.failure(:error))
      {:success, [:error]}

      iex> Ior.swap(Ior.partial([:warn], 42))
      {:partial, [42], [:warn]}
  """
  @spec swap(t(a, e)) :: t([e], a) when a: term(), e: term()
  def swap({:success, value}), do: {:failure, [value]}
  def swap({:failure, errors}), do: {:success, errors}
  def swap({:partial, errors, value}), do: {:partial, [value], errors}

  @doc """
  Filters value based on predicate.

  If predicate fails on value, converts to failure with given error.

  ## Examples

      iex> Ior.filter(Ior.success(42), &(&1 > 0), :must_be_positive)
      {:success, 42}

      iex> Ior.filter(Ior.success(-1), &(&1 > 0), :must_be_positive)
      {:failure, [:must_be_positive]}

      iex> Ior.filter(Ior.partial(:warn, 42), &(&1 > 0), :must_be_positive)
      {:partial, [:warn], 42}
  """
  @spec filter(t(a, e), (a -> boolean()), e) :: t(a, e) when a: term(), e: term()
  def filter({:success, value}, pred, error) when is_function(pred, 1) do
    if pred.(value), do: {:success, value}, else: {:failure, [error]}
  end

  def filter({:partial, errors, value}, pred, error) when is_function(pred, 1) do
    if pred.(value), do: {:partial, errors, value}, else: {:failure, errors ++ [error]}
  end

  def filter({:failure, _} = failure, _pred, _error), do: failure

  @doc """
  Ensures a condition on the value, adding warning if false.

  Unlike filter, this doesn't convert to failure - just adds a warning.

  ## Examples

      iex> Ior.ensure(Ior.success(42), &(&1 < 100), :value_high)
      {:success, 42}

      iex> Ior.ensure(Ior.success(150), &(&1 < 100), :value_high)
      {:partial, [:value_high], 150}
  """
  @spec ensure(t(a, e), (a -> boolean()), e) :: t(a, e) when a: term(), e: term()
  def ensure({:success, value}, pred, warning) when is_function(pred, 1) do
    if pred.(value), do: {:success, value}, else: {:partial, [warning], value}
  end

  def ensure({:partial, errors, value}, pred, warning) when is_function(pred, 1) do
    if pred.(value), do: {:partial, errors, value}, else: {:partial, errors ++ [warning], value}
  end

  def ensure({:failure, _} = failure, _pred, _warning), do: failure

  # ============================================
  # Behaviour Implementations
  # ============================================

  @doc """
  Wraps a value in a success Ior (Monad.pure).

  Alias for `success/1`.

  ## Examples

      iex> Ior.pure(42)
      {:success, 42}
  """
  @impl FnTypes.Behaviours.Combinable
  @spec pure(a) :: success(a) when a: term()
  def pure(value), do: success(value)

  @doc """
  Applies a wrapped function to a wrapped value (Applicative.ap).

  Accumulates warnings from both sides.

  ## Examples

      iex> Ior.ap({:success, fn x -> x * 2 end}, {:success, 5})
      {:success, 10}
  """
  @impl FnTypes.Behaviours.Combinable
  @spec ap(t((a -> b), e), t(a, e)) :: t(b, e) when a: term(), b: term(), e: term()
  def ap(ior_fun, ior_val), do: __MODULE__.apply(ior_fun, ior_val)

  @doc """
  Combines two Iors, accumulating warnings (Semigroup.combine).

  For successful Iors, keeps the second value.

  ## Examples

      iex> Ior.combine({:success, 1}, {:success, 2})
      {:success, 2}

      iex> Ior.combine({:partial, [:w1], 1}, {:partial, [:w2], 2})
      {:partial, [:w1, :w2], 2}

      iex> Ior.combine({:failure, [:e1]}, {:failure, [:e2]})
      {:failure, [:e1, :e2]}
  """
  @impl FnTypes.Behaviours.Appendable
  @spec combine(t(a, e), t(a, e)) :: t(a, e) when a: term(), e: term()
  def combine({:success, _}, {:success, b}), do: {:success, b}
  def combine({:success, _}, {:partial, e, b}), do: {:partial, e, b}
  def combine({:success, _}, {:failure, e}), do: {:failure, e}
  def combine({:partial, e1, _}, {:success, b}), do: {:partial, e1, b}
  def combine({:partial, e1, _}, {:partial, e2, b}), do: {:partial, e1 ++ e2, b}
  def combine({:partial, e1, _}, {:failure, e2}), do: {:failure, e1 ++ e2}
  def combine({:failure, e1}, {:success, b}), do: {:partial, e1, b}
  def combine({:failure, e1}, {:partial, e2, b}), do: {:partial, e1 ++ e2, b}
  def combine({:failure, e1}, {:failure, e2}), do: {:failure, e1 ++ e2}
end
