defmodule FnTypes.Validation do
  @moduledoc """
  Applicative validation with error accumulation.

  Unlike `Result` which fails fast on the first error, `Validation` collects
  ALL errors, making it ideal for form validation, API input validation, and
  any scenario where you want to report multiple issues at once.

  ## Implemented Behaviours

  - `FnTypes.Behaviours.Applicative` - pure, ap, map
  - `FnTypes.Behaviours.Functor` - map
  - `FnTypes.Behaviours.Semigroup` - combine (error accumulation)

  ## Core Concept

  `Validation` is an applicative functor, not a monad. This means:
  - **`map`/`map2`/`map3`**: Transform values if all validations pass
  - **`check`/`validate`**: Add validation rules that accumulate errors
  - **No `and_then`**: Use `Result` when you need fail-fast chaining

  ## Representation

  - `{:ok, value}` - Valid value
  - `{:error, errors}` - List of accumulated errors

  ## Basic Usage

      alias FnTypes.Validation, as: V

      # Validate a map of params
      V.new(params)
      |> V.field(:email, [required(), format(:email)])
      |> V.field(:age, [required(), min(18)])
      |> V.field(:username, [required(), min_length(3), max_length(20)])
      |> V.to_result()
      #=> {:ok, params} | {:error, %{email: [...], age: [...]}}

  ## Standalone Validation

      # Validate a single value
      V.validate("test@example.com", [format(:email), max_length(255)])
      #=> {:ok, "test@example.com"}

      V.validate("invalid", [format(:email)])
      #=> {:error, ["must be a valid email"]}

  ## Combining Validations

      # All must pass (AND semantics)
      V.all([
        V.validate(email, [format(:email)]),
        V.validate(age, [min(18)]),
        V.validate(name, [required()])
      ])
      #=> {:ok, [email, age, name]} | {:error, [all_errors]}

      # Combine into a struct
      V.map3(
        V.validate(params[:email], [required(), format(:email)]),
        V.validate(params[:name], [required()]),
        V.validate(params[:age], [min(18)]),
        fn email, name, age -> %User{email: email, name: name, age: age} end
      )
      #=> {:ok, %User{}} | {:error, [all_errors]}

  ## Conditional Validation

      V.new(params)
      |> V.field(:phone, [required()], when: & &1[:contact_method] == :phone)
      |> V.field(:email, [required()], when: & &1[:contact_method] == :email)

  ## Cross-Field Validation

      V.new(params)
      |> V.field(:password, [required(), min_length(8)])
      |> V.field(:password_confirmation, [required()])
      |> V.check(:password_confirmation, &match_field(&1, :password, :password_confirmation))

  ## Integration with Result

      # Convert to Result
      validation |> V.to_result()
      #=> {:ok, value} | {:error, errors}

      # From Result (single error becomes list)
      V.from_result({:error, :not_found})
      #=> {:error, [:not_found]}

  ## Error Formats

  Errors can be:
  - Atoms: `:required`, `:invalid_format`
  - Strings: `"must be at least 18"`
  - Tuples: `{:min, 18}`, `{:format, :email}`
  - Maps: `%{code: :invalid, message: "...", field: :email}`

  The module preserves error format - you control how errors look.
  """

  @behaviour FnTypes.Behaviours.Applicative
  @behaviour FnTypes.Behaviours.Functor
  @behaviour FnTypes.Behaviours.Semigroup

  alias FnTypes.{Result, Maybe, Error}

  # ============================================
  # Types
  # ============================================

  @type value :: term()
  @type error :: atom() | String.t() | tuple() | map()
  @type errors :: [error()]
  @type field_errors :: %{atom() => errors()}

  @type t(a) :: {:ok, a} | {:error, errors()}
  @type t() :: t(term())

  @type validator(a) :: (a -> t(a))
  @type field_validator :: (term() -> t(term()))
  @type predicate :: (term() -> boolean())

  @type check_opts :: [
          when: predicate() | boolean(),
          unless: predicate() | boolean(),
          message: String.t() | (term() -> String.t()),
          code: atom()
        ]

  # Field validation context for multi-field validation
  @type field_context :: %{
          data: map(),
          field: atom(),
          value: term(),
          errors: field_errors()
        }

  # ============================================
  # Core Construction
  # ============================================

  @doc """
  Creates a valid validation from a value.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.ok(42)
      {:ok, 42}

      iex> alias FnTypes.Validation
      iex> Validation.ok(%{name: "Alice"})
      {:ok, %{name: "Alice"}}
  """
  @spec ok(a) :: t(a) when a: term()
  def ok(value), do: {:ok, value}

  @doc """
  Creates an invalid validation with errors.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.error(:required)
      {:error, [:required]}

      iex> alias FnTypes.Validation
      iex> Validation.error([:too_short, :invalid_format])
      {:error, [:too_short, :invalid_format]}
  """
  @spec error(error() | errors()) :: t(term())
  def error(errors) when is_list(errors), do: {:error, errors}
  def error(error), do: {:error, [error]}

  @doc """
  Creates a new validation context from a map or struct.

  Returns a validation context that can be piped through field validations.

  ## Examples

      Validation.new(%{email: "test@example.com", age: 25})
      |> Validation.field(:email, [required(), format(:email)])
      |> Validation.field(:age, [min(18)])
      |> Validation.to_result()
  """
  @spec new(map()) :: {:context, map(), field_errors()}
  def new(data) when is_map(data) do
    {:context, data, %{}}
  end

  # ============================================
  # Type Checking
  # ============================================

  @doc """
  Checks if validation is valid (ok).

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.valid?({:ok, 42})
      true

      iex> alias FnTypes.Validation
      iex> Validation.valid?({:error, [:required]})
      false
  """
  @spec valid?(t()) :: boolean()
  def valid?({:ok, _}), do: true
  def valid?({:error, _}), do: false
  def valid?({:context, _, errors}), do: errors == %{}

  @doc """
  Checks if validation has errors.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.invalid?({:error, [:required]})
      true

      iex> alias FnTypes.Validation
      iex> Validation.invalid?({:ok, 42})
      false
  """
  @spec invalid?(t()) :: boolean()
  def invalid?(validation), do: not valid?(validation)

  # ============================================
  # Single Value Validation
  # ============================================

  @doc """
  Validates a single value against a list of validators.

  All validators are run and errors are accumulated.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.validate("test@example.com", [
      ...>   Validation.required(),
      ...>   Validation.format(:email)
      ...> ])
      {:ok, "test@example.com"}

      iex> alias FnTypes.Validation
      iex> Validation.validate("", [
      ...>   Validation.required(),
      ...>   Validation.min_length(5)
      ...> ])
      {:error, [:required, {:min_length, 5}]}

      iex> alias FnTypes.Validation
      iex> Validation.validate(15, [
      ...>   Validation.min(18, message: "must be 18 or older")
      ...> ])
      {:error, ["must be 18 or older"]}
  """
  @spec validate(value(), [validator(value())]) :: t(value())
  def validate(value, validators) when is_list(validators) do
    validators
    |> Enum.reduce({:ok, value}, fn validator, acc ->
      combine_errors(acc, validator.(value))
    end)
    |> normalize_result(value)
  end

  @doc """
  Validates a value with a single predicate function.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.check_value(18, &(&1 >= 18), :must_be_adult)
      {:ok, 18}

      iex> alias FnTypes.Validation
      iex> Validation.check_value(15, &(&1 >= 18), :must_be_adult)
      {:error, [:must_be_adult]}

      iex> alias FnTypes.Validation
      iex> Validation.check_value("", &(&1 != ""), message: "cannot be empty")
      {:error, ["cannot be empty"]}
  """
  @spec check_value(value(), predicate(), error() | keyword()) :: t(value())
  def check_value(value, predicate, error_or_opts \\ :invalid)

  def check_value(value, predicate, opts) when is_list(opts) do
    error = Keyword.get(opts, :message) || Keyword.get(opts, :code, :invalid)
    check_value(value, predicate, error)
  end

  def check_value(value, predicate, error) when is_function(predicate, 1) do
    case predicate.(value) do
      true -> {:ok, value}
      false -> {:error, [error]}
    end
  end

  # ============================================
  # Field Validation (Map/Struct Context)
  # ============================================

  @doc """
  Validates a field in the context with given validators.

  ## Options

  - `:when` - Only validate if condition is true (function or boolean)
  - `:unless` - Skip validation if condition is true
  - `:transform` - Transform value before validation (e.g., trim)
  - `:default` - Default value if field is nil

  ## Examples

      Validation.new(%{email: "test@example.com"})
      |> Validation.field(:email, [required(), format(:email)])
      |> Validation.field(:age, [min(18)], when: & &1[:requires_age_check])
      |> Validation.to_result()
  """
  @spec field({:context, map(), field_errors()}, atom(), [validator(term())], keyword()) ::
          {:context, map(), field_errors()}
  def field(context, field_name, validators, opts \\ [])

  def field({:context, data, errors}, field_name, validators, opts) do
    should_validate = should_validate?(data, opts)

    case should_validate do
      false ->
        {:context, data, errors}

      true ->
        value = get_field_value(data, field_name, opts)
        transformed = apply_transform(value, opts)

        case validate(transformed, validators) do
          {:ok, _} ->
            {:context, data, errors}

          {:error, field_errors} ->
            new_errors = Map.update(errors, field_name, field_errors, &(&1 ++ field_errors))
            {:context, data, new_errors}
        end
    end
  end

  @doc """
  Adds a custom check on a field using the full context.

  Useful for cross-field validation.

  ## Examples

      Validation.new(params)
      |> Validation.field(:password, [required()])
      |> Validation.field(:password_confirmation, [required()])
      |> Validation.check(:password_confirmation, fn ctx ->
        if ctx.data[:password] == ctx.data[:password_confirmation] do
          :ok
        else
          {:error, :passwords_must_match}
        end
      end)
  """
  @spec check(
          {:context, map(), field_errors()},
          atom(),
          (field_context() -> :ok | {:error, error()}),
          keyword()
        ) ::
          {:context, map(), field_errors()}
  def check({:context, data, errors}, field_name, check_fn, opts \\ []) do
    should_validate = should_validate?(data, opts)

    case should_validate do
      false ->
        {:context, data, errors}

      true ->
        ctx = %{
          data: data,
          field: field_name,
          value: Map.get(data, field_name),
          errors: errors
        }

        case check_fn.(ctx) do
          :ok ->
            {:context, data, errors}

          {:error, error} ->
            new_errors = Map.update(errors, field_name, [error], &[error | &1])
            {:context, data, new_errors}

          {:error, field, error} when is_atom(field) ->
            new_errors = Map.update(errors, field, [error], &[error | &1])
            {:context, data, new_errors}
        end
    end
  end

  @doc """
  Adds a global check that can add errors to any field.

  ## Examples

      Validation.new(params)
      |> Validation.global_check(fn ctx ->
        cond do
          ctx.data[:start_date] > ctx.data[:end_date] ->
            {:error, :end_date, :must_be_after_start_date}
          true ->
            :ok
        end
      end)
  """
  @spec global_check({:context, map(), field_errors()}, (field_context() ->
                                                           :ok | {:error, atom(), error()})) ::
          {:context, map(), field_errors()}
  def global_check({:context, data, errors}, check_fn) do
    ctx = %{data: data, field: nil, value: nil, errors: errors}

    case check_fn.(ctx) do
      :ok ->
        {:context, data, errors}

      {:error, field, error} ->
        new_errors = Map.update(errors, field, [error], &[error | &1])
        {:context, data, new_errors}

      {:error, error} ->
        # Add to :base if no field specified
        new_errors = Map.update(errors, :base, [error], &[error | &1])
        {:context, data, new_errors}
    end
  end

  @doc """
  Validates multiple fields with the same validators.

  ## Examples

      Validation.new(params)
      |> Validation.fields([:first_name, :last_name], [required(), max_length(100)])
  """
  @spec fields({:context, map(), field_errors()}, [atom()], [validator(term())], keyword()) ::
          {:context, map(), field_errors()}
  def fields(context, field_names, validators, opts \\ []) do
    Enum.reduce(field_names, context, fn field_name, ctx ->
      field(ctx, field_name, validators, opts)
    end)
  end

  @doc """
  Validates nested data within a field.

  ## Examples

      Validation.new(%{
        user: %{email: "test@example.com", profile: %{name: "Alice"}}
      })
      |> Validation.nested(:user, fn user_ctx ->
        user_ctx
        |> Validation.field(:email, [required(), format(:email)])
        |> Validation.nested(:profile, fn profile_ctx ->
          profile_ctx
          |> Validation.field(:name, [required()])
        end)
      end)
  """
  @spec nested({:context, map(), field_errors()}, atom(), (t() -> t()), keyword()) ::
          {:context, map(), field_errors()}
  def nested({:context, data, errors}, field_name, validator_fn, opts \\ []) do
    should_validate = should_validate?(data, opts)
    nested_data = Map.get(data, field_name, %{})

    case {should_validate, is_map(nested_data)} do
      {false, _} ->
        {:context, data, errors}

      {true, false} ->
        new_errors = Map.update(errors, field_name, [:must_be_map], &[:must_be_map | &1])
        {:context, data, new_errors}

      {true, true} ->
        {:context, _, nested_errors} = validator_fn.(new(nested_data))

        case nested_errors do
          empty when map_size(empty) == 0 ->
            {:context, data, errors}

          _ ->
            # Prefix nested errors with parent field name
            prefixed =
              Enum.reduce(nested_errors, %{}, fn {nested_field, field_errs}, acc ->
                key = :"#{field_name}.#{nested_field}"
                Map.put(acc, key, field_errs)
              end)

            {:context, data, Map.merge(errors, prefixed)}
        end
    end
  end

  @doc """
  Validates a list of items, accumulating all errors with indices.

  ## Examples

      Validation.new(%{items: [%{name: "A"}, %{name: ""}, %{name: "C"}]})
      |> Validation.each(:items, fn item_ctx ->
        item_ctx |> Validation.field(:name, [required()])
      end)
      #=> errors: %{"items.1.name" => [:required]}
  """
  @spec each({:context, map(), field_errors()}, atom(), (t() -> t()), keyword()) ::
          {:context, map(), field_errors()}
  def each({:context, data, errors}, field_name, validator_fn, _opts \\ []) do
    items = Map.get(data, field_name, [])

    case is_list(items) do
      false ->
        new_errors = Map.update(errors, field_name, [:must_be_list], &[:must_be_list | &1])
        {:context, data, new_errors}

      true ->
        indexed_errors =
          items
          |> Enum.with_index()
          |> Enum.reduce(%{}, fn {item, index}, acc ->
            item_map = if is_map(item), do: item, else: %{value: item}
            {:context, _, item_errors} = validator_fn.(new(item_map))

            Enum.reduce(item_errors, acc, fn {item_field, field_errs}, inner_acc ->
              key = :"#{field_name}.#{index}.#{item_field}"
              Map.put(inner_acc, key, field_errs)
            end)
          end)

        {:context, data, Map.merge(errors, indexed_errors)}
    end
  end

  # ============================================
  # Applicative Operations
  # ============================================

  @doc """
  Maps a function over a valid value.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.map({:ok, 5}, &(&1 * 2))
      {:ok, 10}

      iex> alias FnTypes.Validation
      iex> Validation.map({:error, [:required]}, &(&1 * 2))
      {:error, [:required]}
  """
  @spec map(t(a), (a -> b)) :: t(b) when a: term(), b: term()
  @impl FnTypes.Behaviours.Functor
  def map({:ok, value}, fun) when is_function(fun, 1), do: {:ok, fun.(value)}
  def map({:error, _} = error, _fun), do: error

  @doc """
  Combines two validations with a function.

  Accumulates errors from both if either fails.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.map2({:ok, 1}, {:ok, 2}, &+/2)
      {:ok, 3}

      iex> alias FnTypes.Validation
      iex> Validation.map2({:error, [:a]}, {:error, [:b]}, &+/2)
      {:error, [:a, :b]}

      iex> alias FnTypes.Validation
      iex> Validation.map2({:ok, 1}, {:error, [:b]}, &+/2)
      {:error, [:b]}
  """
  @spec map2(t(a), t(b), (a, b -> c)) :: t(c) when a: term(), b: term(), c: term()
  @impl FnTypes.Behaviours.Applicative
  def map2({:ok, a}, {:ok, b}, fun) when is_function(fun, 2), do: {:ok, fun.(a, b)}
  def map2({:ok, _}, {:error, errors}, _fun), do: {:error, errors}
  def map2({:error, errors}, {:ok, _}, _fun), do: {:error, errors}

  def map2({:error, errors1}, {:error, errors2}, _fun) do
    {:error, errors1 ++ errors2}
  end

  @doc """
  Combines three validations with a function.

  ## Examples

      Validation.map3(
        Validation.validate(email, [required(), format(:email)]),
        Validation.validate(name, [required()]),
        Validation.validate(age, [min(18)]),
        fn e, n, a -> %{email: e, name: n, age: a} end
      )
  """
  @spec map3(t(a), t(b), t(c), (a, b, c -> d)) :: t(d)
        when a: term(), b: term(), c: term(), d: term()
  def map3(v1, v2, v3, fun) when is_function(fun, 3) do
    case {v1, v2, v3} do
      {{:ok, a}, {:ok, b}, {:ok, c}} ->
        {:ok, fun.(a, b, c)}

      _ ->
        errors =
          [v1, v2, v3]
          |> Enum.flat_map(fn
            {:error, errs} -> errs
            {:ok, _} -> []
          end)

        {:error, errors}
    end
  end

  @doc """
  Combines four validations with a function.
  """
  @spec map4(t(a), t(b), t(c), t(d), (a, b, c, d -> e)) :: t(e)
        when a: term(), b: term(), c: term(), d: term(), e: term()
  def map4(v1, v2, v3, v4, fun) when is_function(fun, 4) do
    case {v1, v2, v3, v4} do
      {{:ok, a}, {:ok, b}, {:ok, c}, {:ok, d}} ->
        {:ok, fun.(a, b, c, d)}

      _ ->
        errors =
          [v1, v2, v3, v4]
          |> Enum.flat_map(fn
            {:error, errs} -> errs
            {:ok, _} -> []
          end)

        {:error, errors}
    end
  end

  @doc """
  Combines N validations with a function.

  ## Examples

      Validation.map_n(
        [v1, v2, v3, v4, v5],
        fn [a, b, c, d, e] -> build_struct(a, b, c, d, e) end
      )
  """
  @spec map_n([t(term())], ([term()] -> b)) :: t(b) when b: term()
  def map_n(validations, fun) when is_list(validations) and is_function(fun, 1) do
    case all(validations) do
      {:ok, values} -> {:ok, fun.(values)}
      {:error, _} = error -> error
    end
  end

  # ============================================
  # Collection Operations
  # ============================================

  @doc """
  Combines a list of validations, accumulating all errors.

  Returns `{:ok, values}` if all pass, `{:error, all_errors}` otherwise.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.all([{:ok, 1}, {:ok, 2}, {:ok, 3}])
      {:ok, [1, 2, 3]}

      iex> alias FnTypes.Validation
      iex> Validation.all([{:ok, 1}, {:error, [:a]}, {:error, [:b]}])
      {:error, [:a, :b]}
  """
  @spec all([t(a)]) :: t([a]) when a: term()
  def all([]), do: {:ok, []}

  def all(validations) when is_list(validations) do
    {values, errors} =
      Enum.reduce(validations, {[], []}, fn
        {:ok, value}, {vals, errs} -> {[value | vals], errs}
        {:error, errs}, {vals, acc_errs} -> {vals, acc_errs ++ errs}
      end)

    case errors do
      [] -> {:ok, Enum.reverse(values)}
      _ -> {:error, errors}
    end
  end

  @doc """
  Applies validators to each item in a list, accumulating all errors.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.traverse([1, 2, 3], fn x ->
      ...>   if x > 0, do: {:ok, x * 2}, else: {:error, [:must_be_positive]}
      ...> end)
      {:ok, [2, 4, 6]}

      iex> alias FnTypes.Validation
      iex> Validation.traverse([1, -2, -3], fn x ->
      ...>   if x > 0, do: {:ok, x}, else: {:error, [{:negative, x}]}
      ...> end)
      {:error, [{:negative, -2}, {:negative, -3}]}
  """
  @spec traverse([a], (a -> t(b))) :: t([b]) when a: term(), b: term()
  def traverse(list, fun) when is_list(list) and is_function(fun, 1) do
    list
    |> Enum.map(fun)
    |> all()
  end

  @doc """
  Like traverse but includes index in error context.

  ## Examples

      Validation.traverse_indexed(items, fn item, index ->
        case validate_item(item) do
          {:ok, v} -> {:ok, v}
          {:error, e} -> {:error, [{:at_index, index, e}]}
        end
      end)
  """
  @spec traverse_indexed([a], (a, non_neg_integer() -> t(b))) :: t([b]) when a: term(), b: term()
  def traverse_indexed(list, fun) when is_list(list) and is_function(fun, 2) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {item, index} -> fun.(item, index) end)
    |> all()
  end

  @doc """
  Partitions validations into successes and failures.

  Unlike `all/1`, this doesn't fail - it separates results.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.partition([{:ok, 1}, {:error, [:a]}, {:ok, 3}])
      %{ok: [1, 3], errors: [[:a]]}
  """
  @spec partition([t(a)]) :: %{ok: [a], errors: [errors()]} when a: term()
  def partition(validations) when is_list(validations) do
    Enum.reduce(validations, %{ok: [], errors: []}, fn
      {:ok, value}, acc -> %{acc | ok: [value | acc.ok]}
      {:error, errs}, acc -> %{acc | errors: [errs | acc.errors]}
    end)
    |> then(fn acc ->
      %{ok: Enum.reverse(acc.ok), errors: Enum.reverse(acc.errors)}
    end)
  end

  # ============================================
  # Built-in Validators
  # ============================================

  @doc """
  Validator: value must be present (not nil, not empty string).

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.required().("hello")
      {:ok, "hello"}

      iex> alias FnTypes.Validation
      iex> Validation.required().(nil)
      {:error, [:required]}

      iex> alias FnTypes.Validation
      iex> Validation.required(message: "is mandatory").(nil)
      {:error, ["is mandatory"]}
  """
  @spec required(keyword()) :: validator(term())
  def required(opts \\ []) do
    error = Keyword.get(opts, :message) || Keyword.get(opts, :code, :required)

    fn
      nil -> {:error, [error]}
      "" -> {:error, [error]}
      value -> {:ok, value}
    end
  end

  @doc """
  Validator: value must be nil or pass validators (for optional fields).

  ## Examples

      # Validates format only if value is present
      Validation.validate(email, [optional([format(:email)])])
  """
  @spec optional([validator(term())]) :: validator(term())
  def optional(validators) when is_list(validators) do
    fn
      nil -> {:ok, nil}
      "" -> {:ok, ""}
      value -> validate(value, validators)
    end
  end

  @doc """
  Validator: string must match format.

  ## Supported Formats

  - `:email` - Email address
  - `:url` - HTTP/HTTPS URL
  - `:uuid` - UUID v4
  - `:phone` - Phone number (digits, spaces, dashes, parens)
  - `:slug` - URL slug (lowercase, dashes, numbers)
  - `:alpha` - Letters only
  - `:alphanumeric` - Letters and numbers
  - `:numeric` - Digits only
  - `~r/pattern/` - Custom regex

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.format(:email).("test@example.com")
      {:ok, "test@example.com"}

      iex> alias FnTypes.Validation
      iex> Validation.format(:email).("invalid")
      {:error, [{:format, :email}]}

      iex> alias FnTypes.Validation
      iex> Validation.format(~r/^[A-Z]+$/, message: "must be uppercase").("abc")
      {:error, ["must be uppercase"]}
  """
  @spec format(atom() | Regex.t(), keyword()) :: validator(String.t())
  def format(format_type, opts \\ [])

  def format(:email, opts) do
    error = Keyword.get(opts, :message) || {:format, :email}
    regex = ~r/^[^\s]+@[^\s]+\.[^\s]+$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:url, opts) do
    error = Keyword.get(opts, :message) || {:format, :url}
    regex = ~r/^https?:\/\/[^\s]+$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:uuid, opts) do
    error = Keyword.get(opts, :message) || {:format, :uuid}
    regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:phone, opts) do
    error = Keyword.get(opts, :message) || {:format, :phone}
    regex = ~r/^[\d\s\-\(\)\+]+$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:slug, opts) do
    error = Keyword.get(opts, :message) || {:format, :slug}
    regex = ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:alpha, opts) do
    error = Keyword.get(opts, :message) || {:format, :alpha}
    regex = ~r/^[a-zA-Z]+$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:alphanumeric, opts) do
    error = Keyword.get(opts, :message) || {:format, :alphanumeric}
    regex = ~r/^[a-zA-Z0-9]+$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(:numeric, opts) do
    error = Keyword.get(opts, :message) || {:format, :numeric}
    regex = ~r/^\d+$/

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  def format(%Regex{} = regex, opts) do
    error = Keyword.get(opts, :message) || {:format, :custom}

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  @doc """
  Validator: number must be >= min.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.min(18).(20)
      {:ok, 20}

      iex> alias FnTypes.Validation
      iex> Validation.min(18).(15)
      {:error, [{:min, 18}]}
  """
  @spec min(number(), keyword()) :: validator(number())
  def min(minimum, opts \\ []) do
    error = Keyword.get(opts, :message) || {:min, minimum}

    fn
      nil -> {:ok, nil}
      value when is_number(value) and value >= minimum -> {:ok, value}
      value when is_number(value) -> {:error, [error]}
      _ -> {:error, [:not_a_number]}
    end
  end

  @doc """
  Validator: number must be <= max.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.max(100).(50)
      {:ok, 50}

      iex> alias FnTypes.Validation
      iex> Validation.max(100).(150)
      {:error, [{:max, 100}]}
  """
  @spec max(number(), keyword()) :: validator(number())
  def max(maximum, opts \\ []) do
    error = Keyword.get(opts, :message) || {:max, maximum}

    fn
      nil -> {:ok, nil}
      value when is_number(value) and value <= maximum -> {:ok, value}
      value when is_number(value) -> {:error, [error]}
      _ -> {:error, [:not_a_number]}
    end
  end

  @doc """
  Validator: number must be in range (inclusive).

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.between(1, 10).(5)
      {:ok, 5}

      iex> alias FnTypes.Validation
      iex> Validation.between(1, 10).(15)
      {:error, [{:between, 1, 10}]}
  """
  @spec between(number(), number(), keyword()) :: validator(number())
  def between(min_val, max_val, opts \\ []) do
    error = Keyword.get(opts, :message) || {:between, min_val, max_val}

    fn
      nil -> {:ok, nil}
      value when is_number(value) and value >= min_val and value <= max_val -> {:ok, value}
      value when is_number(value) -> {:error, [error]}
      _ -> {:error, [:not_a_number]}
    end
  end

  @doc """
  Validator: number must be positive (> 0).

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.positive().(5)
      {:ok, 5}

      iex> alias FnTypes.Validation
      iex> Validation.positive().(0)
      {:error, [:must_be_positive]}
  """
  @spec positive(keyword()) :: validator(number())
  def positive(opts \\ []) do
    error = Keyword.get(opts, :message) || :must_be_positive

    fn
      nil -> {:ok, nil}
      value when is_number(value) and value > 0 -> {:ok, value}
      value when is_number(value) -> {:error, [error]}
      _ -> {:error, [:not_a_number]}
    end
  end

  @doc """
  Validator: number must be non-negative (>= 0).

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.non_negative().(0)
      {:ok, 0}

      iex> alias FnTypes.Validation
      iex> Validation.non_negative().(-5)
      {:error, [:must_be_non_negative]}
  """
  @spec non_negative(keyword()) :: validator(number())
  def non_negative(opts \\ []) do
    error = Keyword.get(opts, :message) || :must_be_non_negative

    fn
      nil -> {:ok, nil}
      value when is_number(value) and value >= 0 -> {:ok, value}
      value when is_number(value) -> {:error, [error]}
      _ -> {:error, [:not_a_number]}
    end
  end

  @doc """
  Validator: string must have minimum length.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.min_length(3).("hello")
      {:ok, "hello"}

      iex> alias FnTypes.Validation
      iex> Validation.min_length(3).("hi")
      {:error, [{:min_length, 3}]}
  """
  @spec min_length(non_neg_integer(), keyword()) :: validator(String.t())
  def min_length(min_len, opts \\ []) do
    error = Keyword.get(opts, :message) || {:min_length, min_len}

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if String.length(value) >= min_len, do: {:ok, value}, else: {:error, [error]}

      value when is_list(value) ->
        if length(value) >= min_len, do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [:invalid_type]}
    end
  end

  @doc """
  Validator: string must have maximum length.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.max_length(10).("hello")
      {:ok, "hello"}

      iex> alias FnTypes.Validation
      iex> Validation.max_length(3).("hello")
      {:error, [{:max_length, 3}]}
  """
  @spec max_length(non_neg_integer(), keyword()) :: validator(String.t())
  def max_length(max_len, opts \\ []) do
    error = Keyword.get(opts, :message) || {:max_length, max_len}

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if String.length(value) <= max_len, do: {:ok, value}, else: {:error, [error]}

      value when is_list(value) ->
        if length(value) <= max_len, do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [:invalid_type]}
    end
  end

  @doc """
  Validator: string must have exact length.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.exact_length(5).("hello")
      {:ok, "hello"}

      iex> alias FnTypes.Validation
      iex> Validation.exact_length(5).("hi")
      {:error, [{:length, 5}]}
  """
  @spec exact_length(non_neg_integer(), keyword()) :: validator(String.t())
  def exact_length(exact_len, opts \\ []) do
    error = Keyword.get(opts, :message) || {:length, exact_len}

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if String.length(value) == exact_len, do: {:ok, value}, else: {:error, [error]}

      value when is_list(value) ->
        if Kernel.length(value) == exact_len, do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [:invalid_type]}
    end
  end

  @doc """
  Validator: value must be in list of allowed values.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.inclusion([:active, :inactive]).(:active)
      {:ok, :active}

      iex> alias FnTypes.Validation
      iex> Validation.inclusion([:active, :inactive]).(:deleted)
      {:error, [{:inclusion, [:active, :inactive]}]}
  """
  @spec inclusion([term()], keyword()) :: validator(term())
  def inclusion(allowed, opts \\ []) do
    error = Keyword.get(opts, :message) || {:inclusion, allowed}

    fn
      nil -> {:ok, nil}
      value -> if value in allowed, do: {:ok, value}, else: {:error, [error]}
    end
  end

  @doc """
  Validator: value must NOT be in list of disallowed values.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.exclusion([:admin, :superuser]).(:user)
      {:ok, :user}

      iex> alias FnTypes.Validation
      iex> Validation.exclusion([:admin, :superuser]).(:admin)
      {:error, [{:exclusion, [:admin, :superuser]}]}
  """
  @spec exclusion([term()], keyword()) :: validator(term())
  def exclusion(disallowed, opts \\ []) do
    error = Keyword.get(opts, :message) || {:exclusion, disallowed}

    fn
      nil -> {:ok, nil}
      value -> if value in disallowed, do: {:error, [error]}, else: {:ok, value}
    end
  end

  @doc """
  Validator: value must be of specific type.

  ## Supported Types

  - `:string`, `:binary` - Binary strings
  - `:integer` - Integers
  - `:float` - Floats
  - `:number` - Integer or float
  - `:boolean`, `:bool` - Boolean
  - `:atom` - Atoms
  - `:list` - Lists
  - `:map` - Maps
  - `:tuple` - Tuples
  - `:function` - Functions
  - `:pid` - PIDs

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.type(:string).("hello")
      {:ok, "hello"}

      iex> alias FnTypes.Validation
      iex> Validation.type(:integer).("hello")
      {:error, [{:type, :integer}]}
  """
  @spec type(atom(), keyword()) :: validator(term())
  def type(expected_type, opts \\ []) do
    error = Keyword.get(opts, :message) || {:type, expected_type}

    fn
      nil -> {:ok, nil}
      value -> if matches_type?(value, expected_type), do: {:ok, value}, else: {:error, [error]}
    end
  end

  @doc """
  Validator: custom predicate function.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.predicate(&(&1 > 0), :must_be_positive).(5)
      {:ok, 5}

      iex> alias FnTypes.Validation
      iex> Validation.predicate(&(&1 > 0), :must_be_positive).(-1)
      {:error, [:must_be_positive]}

      iex> alias FnTypes.Validation
      iex> Validation.predicate(&String.contains?(&1, "@"), message: "must contain @").("test")
      {:error, ["must contain @"]}
  """
  @spec predicate(predicate(), error() | keyword()) :: validator(term())
  def predicate(pred_fn, error_or_opts \\ :invalid)

  def predicate(pred_fn, opts) when is_function(pred_fn, 1) and is_list(opts) do
    error = Keyword.get(opts, :message) || Keyword.get(opts, :code, :invalid)
    predicate(pred_fn, error)
  end

  def predicate(pred_fn, error) when is_function(pred_fn, 1) do
    fn
      nil -> {:ok, nil}
      value -> if pred_fn.(value), do: {:ok, value}, else: {:error, [error]}
    end
  end

  @doc """
  Validator: value must equal expected value.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.equals("expected").("expected")
      {:ok, "expected"}

      iex> alias FnTypes.Validation
      iex> Validation.equals("expected").("other")
      {:error, [:not_equal]}
  """
  @spec equals(term(), keyword()) :: validator(term())
  def equals(expected, opts \\ []) do
    error = Keyword.get(opts, :message) || :not_equal

    fn value ->
      if value == expected, do: {:ok, value}, else: {:error, [error]}
    end
  end

  @doc """
  Validator: value must not equal disallowed value.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.not_equals("forbidden").("allowed")
      {:ok, "allowed"}

      iex> alias FnTypes.Validation
      iex> Validation.not_equals("forbidden").("forbidden")
      {:error, [:equals_forbidden_value]}
  """
  @spec not_equals(term(), keyword()) :: validator(term())
  def not_equals(disallowed, opts \\ []) do
    error = Keyword.get(opts, :message) || :equals_forbidden_value

    fn value ->
      if value != disallowed, do: {:ok, value}, else: {:error, [error]}
    end
  end

  @doc """
  Validator: applies validation only when condition is met.

  ## Examples

      # Only validate phone if contact_method is :phone
      Validation.when_present(
        params[:contact_method] == :phone,
        Validation.format(:phone)
      )
  """
  @spec when_present(boolean() | predicate(), validator(term())) :: validator(term())
  def when_present(condition, validator)

  def when_present(false, _validator), do: fn value -> {:ok, value} end
  def when_present(true, validator), do: validator

  def when_present(condition, validator) when is_function(condition, 1) do
    fn value ->
      if condition.(value), do: validator.(value), else: {:ok, value}
    end
  end

  @doc """
  Validator: UUID v7 format (with timestamp prefix).

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.uuid_v7().("018c5a5e-7c8b-7000-8000-000000000000")
      {:ok, "018c5a5e-7c8b-7000-8000-000000000000"}
  """
  @spec uuid_v7(keyword()) :: validator(String.t())
  def uuid_v7(opts \\ []) do
    error = Keyword.get(opts, :message) || {:format, :uuid_v7}
    regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

    fn
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        if Regex.match?(regex, value), do: {:ok, value}, else: {:error, [error]}

      _ ->
        {:error, [error]}
    end
  end

  @doc """
  Validator: date/datetime must be in the past.

  ## Examples

      iex> alias FnTypes.Validation
      iex> past_date = ~D[2020-01-01]
      iex> Validation.past().(past_date)
      {:ok, ~D[2020-01-01]}
  """
  @spec past(keyword()) :: validator(Date.t() | DateTime.t())
  def past(opts \\ []) do
    error = Keyword.get(opts, :message) || :must_be_in_past

    fn
      nil ->
        {:ok, nil}

      %Date{} = date ->
        if Date.compare(date, Date.utc_today()) == :lt, do: {:ok, date}, else: {:error, [error]}

      %DateTime{} = dt ->
        if DateTime.compare(dt, DateTime.utc_now()) == :lt, do: {:ok, dt}, else: {:error, [error]}

      _ ->
        {:error, [:invalid_date]}
    end
  end

  @doc """
  Validator: date/datetime must be in the future.

  ## Examples

      iex> alias FnTypes.Validation
      iex> future_date = Date.add(Date.utc_today(), 30)
      iex> Validation.future().(future_date)
      {:ok, future_date}
  """
  @spec future(keyword()) :: validator(Date.t() | DateTime.t())
  def future(opts \\ []) do
    error = Keyword.get(opts, :message) || :must_be_in_future

    fn
      nil ->
        {:ok, nil}

      %Date{} = date ->
        if Date.compare(date, Date.utc_today()) == :gt, do: {:ok, date}, else: {:error, [error]}

      %DateTime{} = dt ->
        if DateTime.compare(dt, DateTime.utc_now()) == :gt, do: {:ok, dt}, else: {:error, [error]}

      _ ->
        {:error, [:invalid_date]}
    end
  end

  @doc """
  Validator: value must be a boolean that is true.

  Useful for terms of service acceptance.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.acceptance().(true)
      {:ok, true}

      iex> alias FnTypes.Validation
      iex> Validation.acceptance().(false)
      {:error, [:must_be_accepted]}
  """
  @spec acceptance(keyword()) :: validator(boolean())
  def acceptance(opts \\ []) do
    error = Keyword.get(opts, :message) || :must_be_accepted

    fn
      true -> {:ok, true}
      _ -> {:error, [error]}
    end
  end

  # ============================================
  # Cross-Field Validators (for use with check/3)
  # ============================================

  @doc """
  Cross-field validator: two fields must match.

  ## Examples

      Validation.new(params)
      |> Validation.field(:password, [required()])
      |> Validation.field(:password_confirmation, [required()])
      |> Validation.check(:password_confirmation, &Validation.matches_field(&1, :password))
  """
  @spec matches_field(field_context(), atom(), keyword()) :: :ok | {:error, error()}
  def matches_field(ctx, other_field, opts \\ []) do
    error = Keyword.get(opts, :message) || {:must_match, other_field}
    other_value = Map.get(ctx.data, other_field)

    if ctx.value == other_value do
      :ok
    else
      {:error, error}
    end
  end

  @doc """
  Cross-field validator: field must be greater than another field.

  ## Examples

      Validation.new(params)
      |> Validation.check(:end_date, &Validation.greater_than_field(&1, :start_date))
  """
  @spec greater_than_field(field_context(), atom(), keyword()) :: :ok | {:error, error()}
  def greater_than_field(ctx, other_field, opts \\ []) do
    error = Keyword.get(opts, :message) || {:must_be_greater_than, other_field}
    other_value = Map.get(ctx.data, other_field)

    cond do
      is_nil(ctx.value) or is_nil(other_value) -> :ok
      ctx.value > other_value -> :ok
      true -> {:error, error}
    end
  end

  @doc """
  Cross-field validator: field must be less than another field.
  """
  @spec less_than_field(field_context(), atom(), keyword()) :: :ok | {:error, error()}
  def less_than_field(ctx, other_field, opts \\ []) do
    error = Keyword.get(opts, :message) || {:must_be_less_than, other_field}
    other_value = Map.get(ctx.data, other_field)

    cond do
      is_nil(ctx.value) or is_nil(other_value) -> :ok
      ctx.value < other_value -> :ok
      true -> {:error, error}
    end
  end

  @doc """
  Cross-field validator: at least one of the fields must be present.

  ## Examples

      Validation.new(params)
      |> Validation.global_check(&Validation.at_least_one_of(&1, [:email, :phone]))
  """
  @spec at_least_one_of(field_context(), [atom()], keyword()) :: :ok | {:error, atom(), error()}
  def at_least_one_of(ctx, fields, opts \\ []) do
    error = Keyword.get(opts, :message) || {:at_least_one_required, fields}

    has_value =
      Enum.any?(fields, fn field ->
        value = Map.get(ctx.data, field)
        not is_nil(value) and value != ""
      end)

    if has_value do
      :ok
    else
      {:error, List.first(fields), error}
    end
  end

  @doc """
  Cross-field validator: exactly one of the fields must be present.
  """
  @spec exactly_one_of(field_context(), [atom()], keyword()) :: :ok | {:error, atom(), error()}
  def exactly_one_of(ctx, fields, opts \\ []) do
    error = Keyword.get(opts, :message) || {:exactly_one_required, fields}

    present_count =
      Enum.count(fields, fn field ->
        value = Map.get(ctx.data, field)
        not is_nil(value) and value != ""
      end)

    if present_count == 1 do
      :ok
    else
      {:error, List.first(fields), error}
    end
  end

  @doc """
  Cross-field validator: all specified fields must be present or all absent.
  """
  @spec all_or_none_of(field_context(), [atom()], keyword()) :: :ok | {:error, atom(), error()}
  def all_or_none_of(ctx, fields, opts \\ []) do
    error = Keyword.get(opts, :message) || {:all_or_none_required, fields}

    present_count =
      Enum.count(fields, fn field ->
        value = Map.get(ctx.data, field)
        not is_nil(value) and value != ""
      end)

    if present_count == 0 or present_count == length(fields) do
      :ok
    else
      {:error, List.first(fields), error}
    end
  end

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts context validation to Result.

  ## Examples

      Validation.new(params)
      |> Validation.field(:email, [required()])
      |> Validation.to_result()
      #=> {:ok, params} | {:error, %{email: [:required]}}
  """
  @spec to_result({:context, map(), field_errors()} | t()) :: Result.t()
  def to_result({:context, data, errors}) when map_size(errors) == 0, do: {:ok, data}
  def to_result({:context, _data, errors}), do: {:error, errors}
  def to_result({:ok, _} = ok), do: ok
  def to_result({:error, _} = error), do: error

  @doc """
  Converts to Result, transforming errors with FnTypes.Error.

  ## Options

  - `:message` - Custom error message (default: "Validation failed")
  - `:code` - Custom error code (default: :validation_error)
  - `:context` - Additional context to attach to the error
  - `:include_summary` - Include a summary of failed fields (default: true)

  ## Examples

      Validation.new(params)
      |> Validation.field(:email, [required()])
      |> Validation.to_error()
      #=> {:ok, params} | {:error, %Error{type: :validation, details: %{...}}}

      # With custom options
      Validation.new(params)
      |> Validation.field(:email, [required()])
      |> Validation.to_error(
        message: "User registration failed",
        code: :registration_validation_failed,
        context: %{form: :registration}
      )
  """
  @spec to_error({:context, map(), field_errors()} | t(), keyword()) :: Result.t(term(), Error.t())
  def to_error(validation, opts \\ [])

  def to_error({:context, data, errors}, _opts) when map_size(errors) == 0 do
    {:ok, data}
  end

  def to_error({:context, _data, errors}, opts) do
    message = Keyword.get(opts, :message, "Validation failed")
    code = Keyword.get(opts, :code, :validation_error)
    context = Keyword.get(opts, :context, %{})
    include_summary = Keyword.get(opts, :include_summary, true)

    details =
      if include_summary do
        %{
          errors: errors,
          fields: Map.keys(errors),
          error_count: errors |> Map.values() |> List.flatten() |> length()
        }
      else
        %{errors: errors}
      end

    {:error,
     Error.new(:validation, code,
       message: message,
       details: details,
       context: context
     )}
  end

  def to_error({:ok, _} = ok, _opts), do: ok

  def to_error({:error, errors}, opts) do
    message = Keyword.get(opts, :message, "Validation failed")
    code = Keyword.get(opts, :code, :validation_error)
    context = Keyword.get(opts, :context, %{})

    {:error,
     Error.new(:validation, code,
       message: message,
       details: %{base: errors, error_count: length(errors)},
       context: context
     )}
  end

  @doc """
  Converts field errors to a list of individual Error structs.

  Useful when you need to process each validation error separately,
  for example, to display inline errors in a UI.

  ## Options

  - `:context` - Additional context to attach to each error

  ## Examples

      Validation.new(%{email: "", age: 15})
      |> Validation.field(:email, [required()])
      |> Validation.field(:age, [min(18)])
      |> Validation.to_error_list()
      #=> [
      #=>   %Error{type: :validation, code: :email_required, details: %{field: :email}},
      #=>   %Error{type: :validation, code: :age_min, details: %{field: :age, constraint: 18}}
      #=> ]
  """
  @spec to_error_list({:context, map(), field_errors()} | t(), keyword()) :: [Error.t()]
  def to_error_list(validation, opts \\ [])

  def to_error_list({:context, _data, errors}, opts) when map_size(errors) == 0 do
    _ = opts
    []
  end

  def to_error_list({:context, _data, errors}, opts) do
    context = Keyword.get(opts, :context, %{})

    Enum.flat_map(errors, fn {field, field_errors} ->
      Enum.map(field_errors, fn error ->
        {code, message, details} = parse_validation_error(field, error)

        Error.new(:validation, code,
          message: message,
          details: Map.merge(details, %{field: field}),
          context: context
        )
      end)
    end)
  end

  def to_error_list({:ok, _}, _opts), do: []

  def to_error_list({:error, errors}, opts) do
    context = Keyword.get(opts, :context, %{})

    Enum.map(errors, fn error ->
      {code, message, details} = parse_validation_error(:base, error)

      Error.new(:validation, code,
        message: message,
        details: details,
        context: context
      )
    end)
  end

  # Parse validation errors into code, message, and details
  defp parse_validation_error(field, :required) do
    {:required, "#{field} is required", %{}}
  end

  defp parse_validation_error(field, {:min, value}) do
    {:min_constraint, "#{field} must be at least #{value}", %{constraint: value}}
  end

  defp parse_validation_error(field, {:max, value}) do
    {:max_constraint, "#{field} must be at most #{value}", %{constraint: value}}
  end

  defp parse_validation_error(field, {:min_length, value}) do
    {:min_length, "#{field} must be at least #{value} characters", %{constraint: value}}
  end

  defp parse_validation_error(field, {:max_length, value}) do
    {:max_length, "#{field} must be at most #{value} characters", %{constraint: value}}
  end

  defp parse_validation_error(field, {:format, format_type}) do
    {:invalid_format, "#{field} has invalid format", %{expected_format: format_type}}
  end

  defp parse_validation_error(field, {:inclusion, allowed}) do
    {:invalid_value, "#{field} must be one of: #{inspect(allowed)}", %{allowed: allowed}}
  end

  defp parse_validation_error(field, {:exclusion, disallowed}) do
    {:forbidden_value, "#{field} cannot be one of: #{inspect(disallowed)}",
     %{disallowed: disallowed}}
  end

  defp parse_validation_error(field, {:type, expected_type}) do
    {:invalid_type, "#{field} must be of type #{expected_type}", %{expected_type: expected_type}}
  end

  defp parse_validation_error(field, {:between, min_val, max_val}) do
    {:out_of_range, "#{field} must be between #{min_val} and #{max_val}",
     %{min: min_val, max: max_val}}
  end

  defp parse_validation_error(field, {:must_match, other_field}) do
    {:mismatch, "#{field} must match #{other_field}", %{must_match: other_field}}
  end

  defp parse_validation_error(field, message) when is_binary(message) do
    code = field |> to_string() |> Kernel.<>("_invalid") |> String.to_atom()
    {code, message, %{}}
  end

  defp parse_validation_error(field, code) when is_atom(code) do
    message = code |> to_string() |> String.replace("_", " ")
    {code, "#{field} #{message}", %{}}
  end

  defp parse_validation_error(field, other) do
    {:validation_error, "#{field} is invalid: #{inspect(other)}", %{raw_error: other}}
  end

  @doc """
  Checks if there are errors for a specific field.

  ## Examples

      ctx = Validation.new(%{email: ""}) |> Validation.field(:email, [required()])
      Validation.has_error?(ctx, :email)
      #=> true
  """
  @spec has_error?({:context, map(), field_errors()}, atom()) :: boolean()
  def has_error?({:context, _data, errors}, field) do
    case Map.get(errors, field) do
      nil -> false
      [] -> false
      _ -> true
    end
  end

  @doc """
  Gets errors for a specific field.

  ## Examples

      ctx = Validation.new(%{email: ""}) |> Validation.field(:email, [required()])
      Validation.errors_for(ctx, :email)
      #=> [:required]
  """
  @spec errors_for({:context, map(), field_errors()}, atom()) :: errors()
  def errors_for({:context, _data, errors}, field) do
    Map.get(errors, field, [])
  end

  @doc """
  Returns a count of total validation errors.

  ## Examples

      ctx = Validation.new(%{email: "", name: ""})
      |> Validation.field(:email, [required()])
      |> Validation.field(:name, [required()])
      Validation.error_count(ctx)
      #=> 2
  """
  @spec error_count({:context, map(), field_errors()} | t()) :: non_neg_integer()
  def error_count({:context, _data, errors}) do
    errors
    |> Map.values()
    |> List.flatten()
    |> length()
  end

  def error_count({:error, errors}) when is_list(errors), do: length(errors)
  def error_count({:ok, _}), do: 0

  @doc """
  Creates validation from a Result.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.from_result({:ok, 42})
      {:ok, 42}

      iex> alias FnTypes.Validation
      iex> Validation.from_result({:error, :not_found})
      {:error, [:not_found]}
  """
  @spec from_result(Result.t()) :: t()
  def from_result({:ok, value}), do: {:ok, value}
  def from_result({:error, reason}) when is_list(reason), do: {:error, reason}
  def from_result({:error, reason}), do: {:error, [reason]}

  @doc """
  Creates validation from a Maybe.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.from_maybe({:some, 42}, :required)
      {:ok, 42}

      iex> alias FnTypes.Validation
      iex> Validation.from_maybe(:none, :required)
      {:error, [:required]}
  """
  @spec from_maybe(Maybe.t(), error()) :: t()
  def from_maybe({:some, value}, _error), do: {:ok, value}
  def from_maybe(:none, error), do: {:error, [error]}

  @doc """
  Converts validation to Maybe.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.to_maybe({:ok, 42})
      {:some, 42}

      iex> alias FnTypes.Validation
      iex> Validation.to_maybe({:error, [:required]})
      :none
  """
  @spec to_maybe(t()) :: Maybe.t()
  def to_maybe({:ok, value}), do: {:some, value}
  def to_maybe({:error, _}), do: :none

  # ============================================
  # Utilities
  # ============================================

  @doc """
  Returns the errors from a validation.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.errors({:error, [:a, :b]})
      [:a, :b]

      iex> alias FnTypes.Validation
      iex> Validation.errors({:ok, 42})
      []

      iex> alias FnTypes.Validation
      iex> Validation.errors({:context, %{}, %{email: [:required]}})
      %{email: [:required]}
  """
  @spec errors(t() | {:context, map(), field_errors()}) :: errors() | field_errors()
  def errors({:error, errors}), do: errors
  def errors({:ok, _}), do: []
  def errors({:context, _, errors}), do: errors

  @doc """
  Returns the value from a valid validation.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.value({:ok, 42})
      42

      iex> alias FnTypes.Validation
      iex> Validation.value({:error, [:required]})
      nil

      iex> alias FnTypes.Validation
      iex> Validation.value({:context, %{name: "Alice"}, %{}})
      %{name: "Alice"}
  """
  @spec value(t() | {:context, map(), field_errors()}) :: term() | nil
  def value({:ok, value}), do: value
  def value({:error, _}), do: nil
  def value({:context, data, _}), do: data

  @doc """
  Unwraps value, raising on error.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.unwrap!({:ok, 42})
      42
  """
  @spec unwrap!(t()) :: term() | no_return()
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, errors}), do: raise(ArgumentError, "Validation failed: #{inspect(errors)}")

  @doc """
  Unwraps value with default on error.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.unwrap_or({:ok, 42}, 0)
      42

      iex> alias FnTypes.Validation
      iex> Validation.unwrap_or({:error, [:required]}, 0)
      0
  """
  @spec unwrap_or(t(a), a) :: a when a: term()
  def unwrap_or({:ok, value}, _default), do: value
  def unwrap_or({:error, _}, default), do: default

  @doc """
  Taps into valid value for side effects.

  ## Examples

      {:ok, 42}
      |> Validation.tap(&IO.inspect/1)
      |> Validation.map(&(&1 * 2))
  """
  @spec tap(t(a), (a -> any())) :: t(a) when a: term()
  def tap({:ok, value} = validation, fun) when is_function(fun, 1) do
    fun.(value)
    validation
  end

  def tap({:error, _} = error, _fun), do: error

  @doc """
  Taps into errors for side effects.

  ## Examples

      validation
      |> Validation.tap_error(&Logger.warning("Validation failed: \#{inspect(&1)}"))
  """
  @spec tap_error(t(a), (errors() -> any())) :: t(a) when a: term()
  def tap_error({:ok, _} = ok, _fun), do: ok

  def tap_error({:error, errors} = error, fun) when is_function(fun, 1) do
    fun.(errors)
    error
  end

  @doc """
  Maps over errors.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.map_error({:error, [:a, :b]}, &Atom.to_string/1)
      {:error, ["a", "b"]}
  """
  @spec map_error(t(a), (error() -> error())) :: t(a) when a: term()
  def map_error({:ok, _} = ok, _fun), do: ok

  def map_error({:error, errors}, fun) when is_function(fun, 1) do
    {:error, Enum.map(errors, fun)}
  end

  @doc """
  Flattens nested validation.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.flatten({:ok, {:ok, 42}})
      {:ok, 42}

      iex> alias FnTypes.Validation
      iex> Validation.flatten({:ok, {:error, [:a]}})
      {:error, [:a]}
  """
  @spec flatten(t(t(a))) :: t(a) when a: term()
  def flatten({:ok, {:ok, value}}), do: {:ok, value}
  def flatten({:ok, {:error, errors}}), do: {:error, errors}
  def flatten({:error, _} = error), do: error

  # ============================================
  # Composition Helpers
  # ============================================

  @doc """
  Composes multiple validators into one.

  ## Examples

      email_validator = Validation.compose([
        Validation.required(),
        Validation.format(:email),
        Validation.max_length(255)
      ])

      Validation.validate(email, [email_validator])
  """
  @spec compose([validator(a)]) :: validator(a) when a: term()
  def compose(validators) when is_list(validators) do
    fn value -> validate(value, validators) end
  end

  @doc """
  Creates a named validator for reuse.

  ## Examples

      defmodule MyValidators do
        def email do
          Validation.named(:email, [
            Validation.required(),
            Validation.format(:email),
            Validation.max_length(255)
          ])
        end
      end

      Validation.validate(email, [MyValidators.email()])
  """
  @spec named(atom(), [validator(a)]) :: validator(a) when a: term()
  def named(_name, validators) when is_list(validators) do
    compose(validators)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp should_validate?(data, opts) do
    when_cond = Keyword.get(opts, :when, true)
    unless_cond = Keyword.get(opts, :unless, false)

    when_result =
      case when_cond do
        true -> true
        false -> false
        fun when is_function(fun, 1) -> fun.(data)
      end

    unless_result =
      case unless_cond do
        true -> true
        false -> false
        fun when is_function(fun, 1) -> fun.(data)
      end

    when_result and not unless_result
  end

  defp get_field_value(data, field, opts) do
    default = Keyword.get(opts, :default)

    case Map.fetch(data, field) do
      {:ok, nil} -> default
      {:ok, value} -> value
      :error -> default
    end
  end

  defp apply_transform(value, opts) do
    transform = Keyword.get(opts, :transform)

    case transform do
      nil -> value
      :trim when is_binary(value) -> String.trim(value)
      :downcase when is_binary(value) -> String.downcase(value)
      :upcase when is_binary(value) -> String.upcase(value)
      fun when is_function(fun, 1) -> fun.(value)
      _ -> value
    end
  end

  defp combine_errors({:ok, _}, {:ok, value}), do: {:ok, value}
  defp combine_errors({:ok, _}, {:error, errors}), do: {:error, errors}
  defp combine_errors({:error, errors}, {:ok, _}), do: {:error, errors}
  defp combine_errors({:error, e1}, {:error, e2}), do: {:error, e1 ++ e2}

  defp normalize_result({:ok, _}, value), do: {:ok, value}
  defp normalize_result({:error, errors}, _value), do: {:error, errors}

  defp matches_type?(value, :string), do: is_binary(value)
  defp matches_type?(value, :binary), do: is_binary(value)
  defp matches_type?(value, :integer), do: is_integer(value)
  defp matches_type?(value, :float), do: is_float(value)
  defp matches_type?(value, :number), do: is_number(value)
  defp matches_type?(value, :boolean), do: is_boolean(value)
  defp matches_type?(value, :bool), do: is_boolean(value)
  defp matches_type?(value, :atom), do: is_atom(value)
  defp matches_type?(value, :list), do: is_list(value)
  defp matches_type?(value, :map), do: is_map(value)
  defp matches_type?(value, :tuple), do: is_tuple(value)
  defp matches_type?(value, :function), do: is_function(value)
  defp matches_type?(value, :pid), do: is_pid(value)
  defp matches_type?(value, :reference), do: is_reference(value)
  defp matches_type?(value, :port), do: is_port(value)
  defp matches_type?(_, _), do: false

  # ============================================
  # Behaviour Implementations
  # ============================================

  @doc """
  Wraps a value in a valid Validation (Applicative.pure).

  Alias for `ok/1`.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.pure(42)
      {:ok, 42}
  """
  @impl FnTypes.Behaviours.Applicative
  @spec pure(a) :: t(a) when a: term()
  def pure(value), do: ok(value)

  @doc """
  Applies a wrapped function to a wrapped value (Applicative.ap).

  Accumulates errors from both sides if both fail.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.ap({:ok, fn x -> x * 2 end}, {:ok, 5})
      {:ok, 10}

      iex> alias FnTypes.Validation
      iex> Validation.ap({:error, [:fn_error]}, {:error, [:val_error]})
      {:error, [:fn_error, :val_error]}
  """
  @impl FnTypes.Behaviours.Applicative
  @spec ap(t((a -> b)), t(a)) :: t(b) when a: term(), b: term()
  def ap({:ok, fun}, {:ok, value}) when is_function(fun, 1), do: {:ok, fun.(value)}
  def ap({:ok, _}, {:error, errors}), do: {:error, errors}
  def ap({:error, errors}, {:ok, _}), do: {:error, errors}
  def ap({:error, e1}, {:error, e2}), do: {:error, e1 ++ e2}

  @doc """
  Combines two Validations, accumulating errors (Semigroup.combine).

  For successful validations, keeps the second value.
  For failed validations, combines all errors.

  ## Examples

      iex> alias FnTypes.Validation
      iex> Validation.combine({:ok, 1}, {:ok, 2})
      {:ok, 2}

      iex> alias FnTypes.Validation
      iex> Validation.combine({:error, [:e1]}, {:error, [:e2]})
      {:error, [:e1, :e2]}
  """
  @impl FnTypes.Behaviours.Semigroup
  @spec combine(t(a), t(a)) :: t(a) when a: term()
  def combine({:ok, _}, {:ok, b}), do: {:ok, b}
  def combine({:ok, _}, {:error, _} = e), do: e
  def combine({:error, _} = e, {:ok, _}), do: e
  def combine({:error, e1}, {:error, e2}), do: {:error, e1 ++ e2}
end
