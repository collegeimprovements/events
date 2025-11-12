defmodule Events.Decorator.Types do
  @moduledoc """
  Type decorators for runtime type checking and documentation.

  Provides decorators for common Elixir return type patterns:
  - Result types: `{:ok, value} | {:error, reason}`
  - Maybe/Nullable types: `value | nil`
  - Bang variants: returns value or raises
  - Pipeline-compatible types with consistent error handling

  Inspired by Rust's Result<T, E>, TypeScript's union types, and Haskell's Maybe.

  ## Type Checking Modes

  - **Documentation Only** (default in production) - Generates docs, no runtime checks
  - **Runtime Validation** (dev/test) - Validates return types match specs
  - **Strict Mode** - Raises on type mismatches
  - **Coercion Mode** - Attempts to coerce values to expected types

  ## Common Patterns

      # Result type
      @decorate returns_result(ok: User.t(), error: :atom)
      def get_user(id), do: Repo.get(User, id)

      # Maybe/Optional type
      @decorate returns_maybe(User.t())
      def find_user(email), do: Repo.get_by(User, email: email)

      # Bang variant (raises on error)
      @decorate returns_bang(User.t())
      def get_user!(id), do: Repo.get!(User, id)

      # Struct type
      @decorate returns_struct(User)
      def create_user(attrs), do: %User{} |> User.changeset(attrs) |> Repo.insert!()

      # Union types
      @decorate returns_union([User.t(), Organization.t(), nil])
      def find_entity(id), do: find_user(id) || find_org(id)

      # List types
      @decorate returns_list(User.t())
      def list_users, do: Repo.all(User)
  """

  use Events.Decorator.Define
  alias Events.Decorator.SchemaFragments
  require Logger

  ## Schemas

  @returns_result_schema NimbleOptions.new!(
                           ok: [
                             type: :any,
                             required: false,
                             doc: "Type specification for success value"
                           ],
                           error: [
                             type: :any,
                             required: false,
                             doc: "Type specification for error value"
                           ],
                           validate:
                             SchemaFragments.boolean_field(
                               default: false,
                               doc: "Enable runtime type validation"
                             ),
                           strict:
                             SchemaFragments.boolean_field(
                               default: false,
                               doc: "Raise on type mismatch"
                             ),
                           coerce:
                             SchemaFragments.boolean_field(
                               default: false,
                               doc: "Attempt to coerce values to expected types"
                             )
                         )

  @returns_maybe_schema NimbleOptions.new!(
                          type: [
                            type: :any,
                            required: true,
                            doc: "Type specification for non-nil value"
                          ],
                          validate: SchemaFragments.boolean_field(default: false),
                          strict: SchemaFragments.boolean_field(default: false),
                          default: [
                            type: :any,
                            required: false,
                            doc: "Default value if nil is returned"
                          ]
                        )

  @returns_bang_schema NimbleOptions.new!(
                         type: [
                           type: :any,
                           required: true,
                           doc: "Type specification for return value"
                         ],
                         validate: SchemaFragments.boolean_field(default: false),
                         strict: SchemaFragments.boolean_field(default: false),
                         on_error: [
                           type: {:in, [:raise, :unwrap]},
                           default: :raise,
                           doc: "How to handle {:error, reason} - :raise or :unwrap"
                         ]
                       )

  @returns_struct_schema NimbleOptions.new!(
                           type: [
                             type: :atom,
                             required: true,
                             doc: "Struct module name"
                           ],
                           validate: SchemaFragments.boolean_field(default: false),
                           strict: SchemaFragments.boolean_field(default: false),
                           nullable:
                             SchemaFragments.boolean_field(
                               default: false,
                               doc: "Allow nil returns"
                             )
                         )

  @returns_list_schema NimbleOptions.new!(
                         of: [
                           type: :any,
                           required: true,
                           doc: "Type specification for list elements"
                         ],
                         validate: SchemaFragments.boolean_field(default: false),
                         strict: SchemaFragments.boolean_field(default: false),
                         min_length: [
                           type: :non_neg_integer,
                           required: false,
                           doc: "Minimum list length"
                         ],
                         max_length: [
                           type: :non_neg_integer,
                           required: false,
                           doc: "Maximum list length"
                         ]
                       )

  @returns_union_schema NimbleOptions.new!(
                          types: [
                            type: {:list, :any},
                            required: true,
                            doc: "List of allowed types"
                          ],
                          validate: SchemaFragments.boolean_field(default: false),
                          strict: SchemaFragments.boolean_field(default: false)
                        )

  @returns_pipeline_schema NimbleOptions.new!(
                             ok: [
                               type: :any,
                               required: true,
                               doc: "Type for success case"
                             ],
                             error: [
                               type: :any,
                               default: :atom,
                               doc: "Type for error case"
                             ],
                             validate: SchemaFragments.boolean_field(default: false),
                             strict: SchemaFragments.boolean_field(default: false),
                             chain:
                               SchemaFragments.boolean_field(
                                 default: true,
                                 doc: "Enable pipeline chaining helpers"
                               )
                           )

  @normalize_result_schema NimbleOptions.new!(
                             error_patterns: [
                               type: {:list, :any},
                               default: [:error, :invalid, :failed, :timeout],
                               doc:
                                 "Atoms/strings that indicate error when returned (e.g., :error, :invalid)"
                             ],
                             nil_is_error:
                               SchemaFragments.boolean_field(
                                 default: false,
                                 doc: "Treat nil return as {:error, :nil_value}"
                               ),
                             false_is_error:
                               SchemaFragments.boolean_field(
                                 default: false,
                                 doc: "Treat false return as {:error, :false_value}"
                               ),
                             wrap_exceptions:
                               SchemaFragments.boolean_field(
                                 default: true,
                                 doc: "Catch exceptions and return {:error, exception}"
                               ),
                             error_mapper: [
                               type: {:fun, 1},
                               required: false,
                               doc:
                                 "Function to transform error values: fn error -> transformed_error end"
                             ],
                             success_mapper: [
                               type: {:fun, 1},
                               required: false,
                               doc:
                                 "Function to transform success values: fn value -> transformed_value end"
                             ]
                           )

  ## Decorators

  @doc """
  Declares function returns Result type: `{:ok, value} | {:error, reason}`.

  Common in Elixir for operations that can fail (database, network, validation).

  ## Options

  #{NimbleOptions.docs(@returns_result_schema)}

  ## Examples

      # Basic result type
      @decorate returns_result(ok: User.t(), error: :atom)
      def create_user(attrs) do
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()
      end

      # With validation
      @decorate returns_result(ok: %User{}, error: Ecto.Changeset.t(), validate: true)
      def update_user(user, attrs) do
        user
        |> User.changeset(attrs)
        |> Repo.update()
      end

      # Strict mode (raises on wrong type)
      @decorate returns_result(ok: String.t(), error: :atom, strict: true)
      def format_name(user) do
        if user.name do
          {:ok, String.upcase(user.name)}
        else
          {:error, :no_name}
        end
      end

  ## Type Specifications

  Types can be:
  - Module names: `User`, `Ecto.Changeset`
  - Type specs: `User.t()`, `String.t()`, `:atom`
  - Struct patterns: `%User{}`, `%{id: integer()}`
  - Primitive types: `:string`, `:integer`, `:atom`, `:boolean`
  - Complex types: `[User.t()]`, `%{required(:id) => integer()}`
  """
  def returns_result(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_result_schema)

    ok_type = validated_opts[:ok]
    error_type = validated_opts[:error]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]

    if validate do
      quote do
        result = unquote(body)

        Events.Decorator.Types.validate_result_type(
          result,
          unquote(ok_type),
          unquote(error_type),
          unquote(strict),
          unquote(context)
        )

        result
      end
    else
      body
    end
  end

  @doc """
  Declares function returns Maybe/Optional type: `value | nil`.

  Used for lookups and optional values.

  ## Options

  #{NimbleOptions.docs(@returns_maybe_schema)}

  ## Examples

      # Basic maybe type
      @decorate returns_maybe(User.t())
      def find_user_by_email(email) do
        Repo.get_by(User, email: email)
      end

      # With default value
      @decorate returns_maybe(String.t(), default: "Unknown")
      def get_username(user_id) do
        case Repo.get(User, user_id) do
          %User{name: name} -> name
          nil -> nil
        end
      end

      # With validation
      @decorate returns_maybe(%User{}, validate: true, strict: true)
      def find_active_user(id) do
        Repo.get_by(User, id: id, active: true)
      end
  """
  def returns_maybe(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_maybe_schema)

    type_spec = validated_opts[:type]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]
    default_value = validated_opts[:default]

    cond do
      validate ->
        quote do
          result = unquote(body)

          Events.Decorator.Types.validate_maybe_type(
            result,
            unquote(type_spec),
            unquote(strict),
            unquote(context)
          )

          result
        end

      default_value ->
        quote do
          result = unquote(body)
          result || unquote(default_value)
        end

      true ->
        body
    end
  end

  @doc """
  Declares function returns value or raises (bang variant).

  Converts `{:ok, value}` to `value` and `{:error, reason}` to exception.

  ## Options

  #{NimbleOptions.docs(@returns_bang_schema)}

  ## Examples

      # Basic bang variant
      @decorate returns_bang(User.t())
      def get_user!(id) do
        case Repo.get(User, id) do
          nil -> raise "User not found"
          user -> user
        end
      end

      # Auto-unwrap result tuples
      @decorate returns_bang(User.t(), on_error: :unwrap)
      def create_user!(attrs) do
        # If this returns {:error, changeset}, decorator raises
        User.create(attrs)
      end

      # With validation
      @decorate returns_bang(%User{}, validate: true, strict: true)
      def fetch_user!(id) do
        Repo.get!(User, id)
      end
  """
  def returns_bang(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_bang_schema)

    type_spec = validated_opts[:type]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]
    on_error = validated_opts[:on_error]

    quote do
      result = unquote(body)

      result =
        case unquote(on_error) do
          :unwrap ->
            Events.Decorator.Types.unwrap_result(result, unquote(context))

          :raise ->
            result
        end

      if unquote(validate) do
        Events.Decorator.Types.validate_bang_type(
          result,
          unquote(type_spec),
          unquote(strict),
          unquote(context)
        )
      end

      result
    end
  end

  @doc """
  Declares function returns a specific struct.

  ## Options

  #{NimbleOptions.docs(@returns_struct_schema)}

  ## Examples

      @decorate returns_struct(User)
      def build_user(attrs) do
        struct(User, attrs)
      end

      # Allow nil
      @decorate returns_struct(User, nullable: true)
      def find_user(id) do
        Repo.get(User, id)
      end

      # With validation
      @decorate returns_struct(User, validate: true, strict: true)
      def create_user(attrs) do
        %User{name: attrs.name, email: attrs.email}
      end
  """
  def returns_struct(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_struct_schema)

    struct_module = validated_opts[:type]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]
    nullable = validated_opts[:nullable]

    if validate do
      quote do
        result = unquote(body)

        Events.Decorator.Types.validate_struct_type(
          result,
          unquote(struct_module),
          unquote(nullable),
          unquote(strict),
          unquote(context)
        )

        result
      end
    else
      body
    end
  end

  @doc """
  Declares function returns a list of specific type.

  ## Options

  #{NimbleOptions.docs(@returns_list_schema)}

  ## Examples

      @decorate returns_list(of: User.t())
      def list_users do
        Repo.all(User)
      end

      # With length constraints
      @decorate returns_list(of: %User{}, min_length: 1, max_length: 100)
      def get_active_users do
        User |> where([u], u.active == true) |> Repo.all()
      end

      # With validation
      @decorate returns_list(of: String.t(), validate: true)
      def get_user_names do
        User |> select([u], u.name) |> Repo.all()
      end
  """
  def returns_list(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_list_schema)

    element_type = validated_opts[:of]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]
    min_length = validated_opts[:min_length]
    max_length = validated_opts[:max_length]

    if validate do
      quote do
        result = unquote(body)

        Events.Decorator.Types.validate_list_type(
          result,
          unquote(element_type),
          unquote(min_length),
          unquote(max_length),
          unquote(strict),
          unquote(context)
        )

        result
      end
    else
      body
    end
  end

  @doc """
  Declares function returns one of multiple types (union type).

  ## Options

  #{NimbleOptions.docs(@returns_union_schema)}

  ## Examples

      # String or nil
      @decorate returns_union(types: [String.t(), nil])
      def get_optional_name(user) do
        user.name
      end

      # Multiple struct types
      @decorate returns_union(types: [User.t(), Organization.t()])
      def find_entity(id) do
        Repo.get(User, id) || Repo.get(Organization, id)
      end

      # Result or direct value
      @decorate returns_union(types: [{:ok, User.t()}, {:error, atom()}, User.t()])
      def flexible_get_user(id) do
        # Can return {:ok, user}, {:error, :not_found}, or user directly
      end
  """
  def returns_union(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_union_schema)

    types = validated_opts[:types]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]

    if validate do
      quote do
        result = unquote(body)

        Events.Decorator.Types.validate_union_type(
          result,
          unquote(types),
          unquote(strict),
          unquote(context)
        )

        result
      end
    else
      body
    end
  end

  @doc """
  Declares function returns pipeline-compatible result type.

  Enhanced result type with pipeline helpers like `and_then`, `map_ok`, `map_error`.

  ## Options

  #{NimbleOptions.docs(@returns_pipeline_schema)}

  ## Examples

      @decorate returns_pipeline(ok: User.t(), error: Ecto.Changeset.t())
      def create_user(attrs) do
        %User{}
        |> User.changeset(attrs)
        |> Repo.insert()
      end

      # Usage with pipeline helpers
      def register_user(attrs) do
        create_user(attrs)
        |> and_then(&send_welcome_email/1)
        |> and_then(&create_user_settings/1)
        |> map_ok(&UserView.render/1)
        |> map_error(&format_error/1)
      end
  """
  def returns_pipeline(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @returns_pipeline_schema)

    ok_type = validated_opts[:ok]
    error_type = validated_opts[:error]
    validate = validated_opts[:validate]
    strict = validated_opts[:strict]
    enable_chain = validated_opts[:chain]

    result_validation =
      if validate do
        quote do
          Events.Decorator.Types.validate_result_type(
            result,
            unquote(ok_type),
            unquote(error_type),
            unquote(strict),
            unquote(context)
          )
        end
      end

    if enable_chain do
      quote do
        result = unquote(body)
        unquote(result_validation)

        # Wrap in pipeline-compatible module
        Events.Decorator.Types.PipelineResult.new(result)
      end
    else
      if validate do
        quote do
          result = unquote(body)
          unquote(result_validation)
          result
        end
      else
        body
      end
    end
  end

  @doc """
  Normalizes any return value into `{:ok, result} | {:error, reason}` pattern.

  This decorator ensures all functions return a consistent Result type, regardless
  of what the underlying implementation returns. It handles:

  - Raw values → `{:ok, value}`
  - Tuples already in result format → pass through
  - Error indicators → `{:error, reason}`
  - Exceptions → `{:error, exception}` (if wrap_exceptions is true)
  - nil/false → `{:error, :nil_value}` or `{:error, :false_value}` (if configured)

  ## Options

  #{NimbleOptions.docs(@normalize_result_schema)}

  ## Examples

      # Basic normalization - wraps raw values in {:ok, value}
      @decorate normalize_result()
      def get_user(id) do
        Repo.get(User, id)  # Returns %User{} or nil
      end
      # Returns: {:ok, %User{}} or {:ok, nil}

      # Treat nil as error
      @decorate normalize_result(nil_is_error: true)
      def get_user(id) do
        Repo.get(User, id)
      end
      # Returns: {:ok, %User{}} or {:error, :nil_value}

      # Wrap exceptions
      @decorate normalize_result(wrap_exceptions: true)
      def risky_operation do
        raise "Something went wrong"
      end
      # Returns: {:error, %RuntimeError{message: "Something went wrong"}}

      # Custom error patterns
      @decorate normalize_result(error_patterns: [:not_found, :invalid, "ERROR"])
      def check_status do
        :not_found  # Will be converted to {:error, :not_found}
      end

      # Transform errors
      @decorate normalize_result(error_mapper: fn error -> "Failed: \#{inspect(error)}" end)
      def fetch_data do
        {:error, :timeout}
      end
      # Returns: {:error, "Failed: :timeout"}

      # Transform success values
      @decorate normalize_result(success_mapper: &String.upcase/1)
      def get_name do
        "john"
      end
      # Returns: {:ok, "JOHN"}

      # Combine options
      @decorate normalize_result(
        nil_is_error: true,
        false_is_error: true,
        wrap_exceptions: true,
        error_patterns: [:invalid, :not_found]
      )
      def complex_operation do
        # Any return value is normalized
      end

  ## Normalization Rules

  1. **Already a result tuple** - Pass through unchanged
     - `{:ok, value}` → `{:ok, value}`
     - `{:error, reason}` → `{:error, reason}`

  2. **Error patterns** - Convert to error tuple
     - `:error` → `{:error, :error}`
     - `:invalid` → `{:error, :invalid}`
     - Any atom/string in error_patterns list

  3. **nil handling** - Depends on nil_is_error option
     - If nil_is_error: true → `{:error, :nil_value}`
     - If nil_is_error: false → `{:ok, nil}`

  4. **false handling** - Depends on false_is_error option
     - If false_is_error: true → `{:error, :false_value}`
     - If false_is_error: false → `{:ok, false}`

  5. **Exceptions** - Depends on wrap_exceptions option
     - If true → `{:error, exception}`
     - If false → Reraise exception

  6. **All other values** - Wrap in success tuple
     - `"hello"` → `{:ok, "hello"}`
     - `%User{}` → `{:ok, %User{}}`
     - `[1, 2, 3]` → `{:ok, [1, 2, 3]}`
     - `42` → `{:ok, 42}`

  ## Use Cases

  - **Wrapping external libraries** that don't return result tuples
  - **Normalizing third-party APIs** to consistent format
  - **Converting legacy code** to result pattern
  - **Ensuring consistency** across codebase
  - **Simplifying error handling** with consistent pattern
  """
  def normalize_result(opts, body, _context) do
    validated_opts = NimbleOptions.validate!(opts, @normalize_result_schema)

    error_patterns = validated_opts[:error_patterns]
    nil_is_error = validated_opts[:nil_is_error]
    false_is_error = validated_opts[:false_is_error]
    wrap_exceptions = validated_opts[:wrap_exceptions]
    error_mapper = validated_opts[:error_mapper]
    success_mapper = validated_opts[:success_mapper]

    normalization_code =
      quote do
        Events.Decorator.Types.normalize_to_result(
          result,
          unquote(error_patterns),
          unquote(nil_is_error),
          unquote(false_is_error),
          unquote(error_mapper),
          unquote(success_mapper)
        )
      end

    if wrap_exceptions do
      quote do
        result =
          try do
            unquote(body)
          rescue
            exception -> {:__exception__, exception, __STACKTRACE__}
          catch
            :exit, reason -> {:__exit__, reason}
            thrown_value -> {:__throw__, thrown_value}
          end

        case result do
          {:__exception__, exception, _stacktrace} ->
            error_value =
              if unquote(error_mapper) do
                unquote(error_mapper).(exception)
              else
                exception
              end

            {:error, error_value}

          {:__exit__, reason} ->
            error_value =
              if unquote(error_mapper) do
                unquote(error_mapper).({:exit, reason})
              else
                {:exit, reason}
              end

            {:error, error_value}

          {:__throw__, value} ->
            error_value =
              if unquote(error_mapper) do
                unquote(error_mapper).({:throw, value})
              else
                {:throw, value}
              end

            {:error, error_value}

          result ->
            unquote(normalization_code)
        end
      end
    else
      quote do
        result = unquote(body)
        unquote(normalization_code)
      end
    end
  end

  ## Validation Functions

  @doc false
  def validate_result_type(result, ok_type, error_type, strict, context) do
    case result do
      {:ok, value} ->
        unless check_type(value, ok_type) do
          handle_type_mismatch(
            "Expected {:ok, #{type_name(ok_type)}}, got {:ok, #{type_name(value)}}",
            strict,
            context
          )
        end

      {:error, reason} ->
        unless check_type(reason, error_type) do
          handle_type_mismatch(
            "Expected {:error, #{type_name(error_type)}}, got {:error, #{type_name(reason)}}",
            strict,
            context
          )
        end

      other ->
        handle_type_mismatch(
          "Expected {:ok, _} | {:error, _}, got #{type_name(other)}",
          strict,
          context
        )
    end
  end

  @doc false
  def validate_maybe_type(result, type_spec, strict, context) do
    case result do
      nil ->
        :ok

      value ->
        unless check_type(value, type_spec) do
          handle_type_mismatch(
            "Expected #{type_name(type_spec)} | nil, got #{type_name(value)}",
            strict,
            context
          )
        end
    end
  end

  @doc false
  def validate_bang_type(result, type_spec, strict, context) do
    unless check_type(result, type_spec) do
      handle_type_mismatch(
        "Expected #{type_name(type_spec)}, got #{type_name(result)}",
        strict,
        context
      )
    end
  end

  @doc false
  def validate_struct_type(result, struct_module, nullable, strict, context) do
    cond do
      is_nil(result) and nullable ->
        :ok

      is_nil(result) and not nullable ->
        handle_type_mismatch(
          "Expected %#{Kernel.inspect(struct_module)}{}, got nil",
          strict,
          context
        )

      is_struct(result, struct_module) ->
        :ok

      true ->
        handle_type_mismatch(
          "Expected %#{Kernel.inspect(struct_module)}{}, got #{type_name(result)}",
          strict,
          context
        )
    end
  end

  @doc false
  def validate_list_type(result, element_type, min_length, max_length, strict, context) do
    if not is_list(result) do
      handle_type_mismatch(
        "Expected list, got #{type_name(result)}",
        strict,
        context
      )
    else
      # Check length constraints
      length = length(result)

      if min_length && length < min_length do
        handle_type_mismatch(
          "List length #{length} is less than minimum #{min_length}",
          strict,
          context
        )
      end

      if max_length && length > max_length do
        handle_type_mismatch(
          "List length #{length} exceeds maximum #{max_length}",
          strict,
          context
        )
      end

      # Check element types
      Enum.each(result, fn element ->
        unless check_type(element, element_type) do
          handle_type_mismatch(
            "List element #{type_name(element)} doesn't match expected type #{type_name(element_type)}",
            strict,
            context
          )
        end
      end)
    end

    :ok
  end

  @doc false
  def validate_union_type(result, types, strict, context) do
    matches = Enum.any?(types, fn type -> check_type(result, type) end)

    unless matches do
      type_names = Enum.map_join(types, " | ", &type_name/1)

      handle_type_mismatch(
        "Expected one of [#{type_names}], got #{type_name(result)}",
        strict,
        context
      )
    end
  end

  @doc false
  def unwrap_result({:ok, value}, _context), do: value

  def unwrap_result({:error, reason}, context) do
    raise Events.Decorator.Types.UnwrapError,
      message: "Cannot unwrap {:error, _} in #{Events.Context.full_name(context)}",
      reason: reason
  end

  def unwrap_result(value, _context), do: value

  @doc false
  def normalize_to_result(
        result,
        error_patterns,
        nil_is_error,
        false_is_error,
        error_mapper,
        success_mapper
      ) do
    case result do
      # Already a result tuple - apply mappers if present
      {:ok, value} ->
        if success_mapper do
          {:ok, success_mapper.(value)}
        else
          {:ok, value}
        end

      {:error, reason} ->
        if error_mapper do
          {:error, error_mapper.(reason)}
        else
          {:error, reason}
        end

      # nil handling
      nil ->
        if nil_is_error do
          error_value = if error_mapper, do: error_mapper.(:nil_value), else: :nil_value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(nil), else: nil
          {:ok, success_value}
        end

      # false handling
      false ->
        if false_is_error do
          error_value = if error_mapper, do: error_mapper.(:false_value), else: :false_value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(false), else: false
          {:ok, success_value}
        end

      # Check if result matches error patterns
      value when is_atom(value) or is_binary(value) ->
        if value in error_patterns do
          error_value = if error_mapper, do: error_mapper.(value), else: value
          {:error, error_value}
        else
          success_value = if success_mapper, do: success_mapper.(value), else: value
          {:ok, success_value}
        end

      # All other values are considered success
      value ->
        success_value = if success_mapper, do: success_mapper.(value), else: value
        {:ok, success_value}
    end
  end

  ## Type Checking Helpers

  defp check_type(_value, nil), do: true
  defp check_type(nil, _type), do: true
  defp check_type(_value, :any), do: true
  defp check_type(value, :atom) when is_atom(value), do: true
  defp check_type(value, :string) when is_binary(value), do: true
  defp check_type(value, :integer) when is_integer(value), do: true
  defp check_type(value, :float) when is_float(value), do: true
  defp check_type(value, :boolean) when is_boolean(value), do: true
  defp check_type(value, :list) when is_list(value), do: true
  defp check_type(value, :map) when is_map(value), do: true
  defp check_type(value, :tuple) when is_tuple(value), do: true

  # Struct checking
  defp check_type(value, module) when is_atom(module) do
    is_struct(value, module)
  end

  # Pattern matching
  defp check_type(value, pattern) when is_map(pattern) do
    is_struct(value) && value.__struct__ == pattern.__struct__
  end

  defp check_type(_value, _type), do: true

  defp type_name(nil), do: "nil"
  defp type_name(value) when is_atom(value), do: Kernel.inspect(value)
  defp type_name(value) when is_binary(value), do: "String.t()"
  defp type_name(value) when is_integer(value), do: "integer()"
  defp type_name(value) when is_float(value), do: "float()"
  defp type_name(value) when is_boolean(value), do: "boolean()"
  defp type_name(value) when is_list(value), do: "list()"
  defp type_name(value) when is_map(value) and not is_struct(value), do: "map()"
  defp type_name(%{__struct__: module}), do: "%#{Kernel.inspect(module)}{}"
  defp type_name({:ok, _}), do: "{:ok, _}"
  defp type_name({:error, _}), do: "{:error, _}"
  defp type_name(value), do: Kernel.inspect(value)

  defp handle_type_mismatch(message, true, context) do
    raise Events.Decorator.Types.TypeError,
      message: "Type mismatch in #{Events.Context.full_name(context)}: #{message}"
  end

  defp handle_type_mismatch(message, false, context) do
    Logger.warning("Type mismatch in #{Events.Context.full_name(context)}: #{message}")
  end
end

defmodule Events.Decorator.Types.TypeError do
  defexception [:message]
end

defmodule Events.Decorator.Types.UnwrapError do
  defexception [:message, :reason]
end

defmodule Events.Decorator.Types.PipelineResult do
  @moduledoc """
  Pipeline-compatible result wrapper with chainable helpers.

  Provides functional programming utilities for working with result types.
  """

  defstruct [:value]

  def new(value), do: %__MODULE__{value: value}

  @doc """
  Chains operations that return results.

  Only executes if previous result was {:ok, value}.

  ## Examples

      create_user(attrs)
      |> and_then(&send_welcome_email/1)
      |> and_then(&create_settings/1)
  """
  def and_then(%__MODULE__{value: {:ok, value}}, fun) do
    case fun.(value) do
      {:ok, _} = result -> new(result)
      {:error, _} = error -> new(error)
      %__MODULE__{} = wrapped -> wrapped
      other -> new({:ok, other})
    end
  end

  def and_then(%__MODULE__{value: {:error, _}} = result, _fun), do: result

  @doc """
  Maps the success value.

  ## Examples

      get_user(id)
      |> map_ok(&UserView.render/1)
  """
  def map_ok(%__MODULE__{value: {:ok, value}}, fun) do
    new({:ok, fun.(value)})
  end

  def map_ok(%__MODULE__{} = result, _fun), do: result

  @doc """
  Maps the error value.

  ## Examples

      create_user(attrs)
      |> map_error(&format_changeset_errors/1)
  """
  def map_error(%__MODULE__{value: {:error, reason}}, fun) do
    new({:error, fun.(reason)})
  end

  def map_error(%__MODULE__{} = result, _fun), do: result

  @doc """
  Unwraps the wrapped value.
  """
  def unwrap(%__MODULE__{value: value}), do: value
end
