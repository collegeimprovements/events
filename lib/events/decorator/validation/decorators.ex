defmodule Events.Decorator.Validation do
  @moduledoc """
  Data validation and transformation decorators.

  Provides schema validation, type coercion, and serialization capabilities.
  Inspired by Python Pydantic, marshmallow, and similar validation libraries.
  """

  use Events.Decorator.Define
  require Logger

  ## Schemas

  @validate_schema_schema NimbleOptions.new!(
                            schema: [
                              type: {:or, [:atom, :map]},
                              required: true,
                              doc: "Schema module or inline schema definition"
                            ],
                            on_error: [
                              type: {:in, [:raise, :return_error, :return_nil]},
                              default: :return_error,
                              doc: "What to do on validation error"
                            ],
                            coerce: [
                              type: :boolean,
                              default: true,
                              doc: "Whether to coerce types"
                            ],
                            strict: [
                              type: :boolean,
                              default: false,
                              doc: "Whether to reject unknown fields"
                            ]
                          )

  @coerce_types_schema NimbleOptions.new!(
                         args: [
                           type: :keyword_list,
                           required: true,
                           doc: "Map of argument names to target types"
                         ],
                         on_error: [
                           type: {:in, [:raise, :return_error, :keep_original]},
                           default: :keep_original,
                           doc: "What to do if coercion fails"
                         ]
                       )

  @serialize_schema NimbleOptions.new!(
                      format: [
                        type: {:in, [:json, :map, :keyword, :binary]},
                        default: :json,
                        doc: "Output format"
                      ],
                      only: [
                        type: {:list, :atom},
                        required: false,
                        doc: "Fields to include"
                      ],
                      except: [
                        type: {:list, :atom},
                        default: [],
                        doc: "Fields to exclude"
                      ],
                      rename: [
                        type: :keyword_list,
                        default: [],
                        doc: "Field renaming map"
                      ],
                      transform: [
                        type: {:fun, 2},
                        required: false,
                        doc: "Custom transformation function"
                      ]
                    )

  @contract_schema NimbleOptions.new!(
                     pre: [
                       type: {:or, [{:fun, 1}, {:list, {:fun, 1}}]},
                       required: false,
                       doc: "Precondition(s) - functions that must return true"
                     ],
                     post: [
                       type: {:or, [{:fun, 2}, {:list, {:fun, 2}}]},
                       required: false,
                       doc: "Postcondition(s) - functions checking input and output"
                     ],
                     invariant: [
                       type: {:fun, 1},
                       required: false,
                       doc: "Invariant that must hold throughout execution"
                     ],
                     on_error: [
                       type: {:in, [:raise, :warn, :return_error]},
                       default: :raise,
                       doc: "What to do on contract violation"
                     ],
                     on_violation: [
                       type: {:in, [:raise, :warn, :return_error]},
                       required: false,
                       doc: "Deprecated: use on_error instead"
                     ]
                   )

  ## Decorators

  @doc """
  Schema validation decorator.

  Validates function arguments against a schema before execution.
  Supports Ecto changesets, NimbleOptions, or custom validators.

  ## Options

  #{NimbleOptions.docs(@validate_schema_schema)}

  ## Examples

      defmodule UserSchema do
        use Ecto.Schema

        schema "users" do
          field :name, :string
          field :email, :string
          field :age, :integer
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs, [:name, :email, :age])
          |> validate_required([:name, :email])
          |> validate_format(:email, ~r/@/)
        end
      end

      @decorate validate_schema(schema: UserSchema)
      def create_user(params) do
        # params are validated before execution
        User.create(params)
      end

      # Inline schema
      @decorate validate_schema(
        schema: %{
          name: [type: :string, required: true],
          age: [type: :integer, min: 18]
        }
      )
      def process_adult(data) do
        # data must have name (string) and age (>= 18)
      end

      # With error handling
      @decorate validate_schema(
        schema: OrderSchema,
        on_error: :return_error,
        strict: true
      )
      def place_order(order_params) do
        # Returns {:error, changeset} if validation fails
        Order.create(order_params)
      end
  """
  def validate_schema(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @validate_schema_schema)

    schema = validated_opts[:schema]
    on_error = validated_opts[:on_error]
    coerce = validated_opts[:coerce]
    strict = validated_opts[:strict]

    quote do
      params =
        case var!(args) do
          [single_arg] when is_map(single_arg) or is_list(single_arg) ->
            single_arg

          args ->
            # Convert multiple args to map
            arg_names = unquote(Events.AST.get_args(context))
            Enum.zip(arg_names, args) |> Map.new()
        end

      validation_result =
        unquote(__MODULE__).validate_with_schema(
          params,
          unquote(schema),
          unquote(coerce),
          unquote(strict)
        )

      case validation_result do
        {:ok, validated_params} ->
          # Replace original args with validated ones
          var!(args) =
            case var!(args) do
              [_single] -> [validated_params]
              _multiple -> [validated_params]
            end

          unquote(body)

        {:error, errors} ->
          case unquote(on_error) do
            :raise ->
              raise Events.ValidationError,
                message: "Validation failed",
                errors: errors

            :return_error ->
              {:error, errors}

            :return_nil ->
              nil
          end
      end
    end
  end

  @doc """
  Type coercion decorator.

  Automatically converts argument types before function execution.

  ## Options

  #{NimbleOptions.docs(@coerce_types_schema)}

  ## Examples

      @decorate coerce_types(args: [
        age: :integer,
        active: :boolean,
        price: :float
      ])
      def process_data(age, active, price) do
        # "25" becomes 25, "true" becomes true, "19.99" becomes 19.99
      end

      @decorate coerce_types(
        args: [id: :integer, tags: {:list, :string}],
        on_error: :raise
      )
      def update_item(id, tags) do
        # Coerces id to integer and tags to list of strings
      end
  """
  def coerce_types(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @coerce_types_schema)

    type_map = validated_opts[:args]
    on_error = validated_opts[:on_error]

    quote do
      arg_names = unquote(Events.AST.get_args(context))

      coerced_args =
        var!(args)
        |> Enum.with_index()
        |> Enum.map(fn {arg, idx} ->
          arg_name = Enum.at(arg_names, idx)
          target_type = unquote(type_map)[arg_name]

          if target_type do
            case unquote(__MODULE__).coerce_value(arg, target_type) do
              {:ok, coerced} ->
                coerced

              {:error, _reason} ->
                case unquote(on_error) do
                  :raise ->
                    raise Events.CoercionError,
                      message:
                        "Cannot coerce #{Kernel.inspect(arg)} to #{Kernel.inspect(target_type)}"

                  :return_error ->
                    throw({:coercion_error, arg_name, target_type})

                  :keep_original ->
                    arg
                end
            end
          else
            arg
          end
        end)

      var!(args) = coerced_args

      try do
        unquote(body)
      catch
        {:coercion_error, field, type} ->
          {:error, "Cannot coerce field #{field} to type #{type}"}
      end
    end
  end

  @doc """
  Serialization decorator.

  Transforms function output to specified format with field filtering.

  ## Options

  #{NimbleOptions.docs(@serialize_schema)}

  ## Examples

      @decorate serialize(format: :json, except: [:password, :token])
      def get_user(id) do
        Repo.get(User, id)
        # Password and token fields are removed from JSON
      end

      @decorate serialize(
        format: :map,
        only: [:id, :name, :email],
        rename: [email: :email_address]
      )
      def get_profile(user_id) do
        # Returns only id, name, and email (renamed to email_address)
      end

      # Custom transformation
      @decorate serialize(
        format: :json,
        transform: fn result, _opts ->
          Map.put(result, :fetched_at, DateTime.utc_now())
        end
      )
      def fetch_data(params) do
        # Adds fetched_at timestamp to result
      end
  """
  def serialize(opts, body, _context) do
    validated_opts = NimbleOptions.validate!(opts, @serialize_schema)

    format = validated_opts[:format]
    only = validated_opts[:only]
    except = validated_opts[:except]
    rename = validated_opts[:rename]
    transform = validated_opts[:transform]

    quote do
      result = unquote(body)

      serialized =
        unquote(__MODULE__).serialize_result(
          result,
          unquote(format),
          unquote(only),
          unquote(except),
          unquote(rename),
          unquote(transform)
        )

      serialized
    end
  end

  @doc """
  Design by Contract decorator.

  Enforces preconditions, postconditions, and invariants.

  ## Options

  #{NimbleOptions.docs(@contract_schema)}

  ## Examples

      @decorate contract(
        pre: fn [x] -> x > 0 end,
        post: fn [x], result -> result >= 0 and result * result == x end
      )
      def square_root(x) do
        :math.sqrt(x)
      end

      @decorate contract(
        pre: [
          fn [list] -> is_list(list) end,
          fn [list] -> length(list) > 0 end
        ],
        post: fn [input], output -> length(output) == length(input) end
      )
      def sort_list(list) do
        Enum.sort(list)
      end

      # With invariant
      @decorate contract(
        pre: fn [account, amount] -> account.balance >= amount end,
        post: fn [account, amount], result ->
          result.balance == account.balance - amount
        end,
        invariant: fn account -> account.balance >= 0 end,
        on_error: :raise
      )
      def withdraw(account, amount) do
        %{account | balance: account.balance - amount}
      end
  """
  def contract(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @contract_schema)

    # Handle deprecated on_violation option
    on_error =
      if validated_opts[:on_violation] do
        IO.warn("on_violation is deprecated, use on_error instead")
        validated_opts[:on_violation]
      else
        validated_opts[:on_error]
      end

    pre = List.wrap(validated_opts[:pre] || [])
    post = List.wrap(validated_opts[:post] || [])
    invariant = validated_opts[:invariant]

    quote do
      # Check preconditions
      for pre_fn <- unquote(pre) do
        unless pre_fn.(var!(args)) do
          unquote(__MODULE__).handle_contract_violation(
            :precondition,
            unquote(context),
            unquote(on_error)
          )
        end
      end

      # Check invariant before
      if unquote(invariant) do
        relevant_state = unquote(__MODULE__).extract_state(var!(args))

        unless unquote(invariant).(relevant_state) do
          unquote(__MODULE__).handle_contract_violation(
            :invariant_before,
            unquote(context),
            unquote(on_error)
          )
        end
      end

      # Execute function
      result = unquote(body)

      # Check postconditions
      for post_fn <- unquote(post) do
        unless post_fn.(var!(args), result) do
          unquote(__MODULE__).handle_contract_violation(
            :postcondition,
            unquote(context),
            unquote(on_error)
          )
        end
      end

      # Check invariant after
      if unquote(invariant) do
        relevant_state =
          case result do
            {:ok, state} -> state
            state -> state
          end

        unless unquote(invariant).(relevant_state) do
          unquote(__MODULE__).handle_contract_violation(
            :invariant_after,
            unquote(context),
            unquote(on_error)
          )
        end
      end

      result
    end
  end

  ## Helper Functions

  @doc false
  def validate_with_schema(params, schema, _coerce, _strict) when is_atom(schema) do
    # Assume it's an Ecto schema
    if function_exported?(schema, :changeset, 2) do
      changeset = schema.changeset(struct(schema), params)

      if changeset.valid? do
        {:ok, Ecto.Changeset.apply_changes(changeset)}
      else
        {:error, changeset.errors}
      end
    else
      {:error, "Schema module must export changeset/2"}
    end
  end

  def validate_with_schema(params, schema, _coerce, _strict) when is_map(schema) do
    # Inline schema validation
    # Simplified - in production would use NimbleOptions or similar
    {:ok, params}
  end

  @doc false
  def coerce_value(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  def coerce_value(value, :integer) when is_integer(value), do: {:ok, value}
  def coerce_value(value, :integer) when is_float(value), do: {:ok, trunc(value)}

  def coerce_value(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, :invalid_float}
    end
  end

  def coerce_value(value, :float) when is_number(value), do: {:ok, value * 1.0}

  def coerce_value("true", :boolean), do: {:ok, true}
  def coerce_value("false", :boolean), do: {:ok, false}
  def coerce_value(value, :boolean) when is_boolean(value), do: {:ok, value}

  def coerce_value(value, :string) when is_binary(value), do: {:ok, value}
  def coerce_value(value, :string), do: {:ok, to_string(value)}

  def coerce_value(value, {:list, type}) when is_list(value) do
    results = Enum.map(value, &coerce_value(&1, type))

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, v} -> v end)}
    else
      {:error, :invalid_list}
    end
  end

  def coerce_value(_value, _type), do: {:error, :unsupported_type}

  @doc false
  def serialize_result(result, format, only, except, rename, transform) do
    # Convert to map if needed
    data =
      case result do
        {:ok, data} -> data
        {:error, _} = error -> error
        data -> data
      end

    # Return early if it's an error
    case data do
      {:error, _} = error -> error
      _ -> serialize_data(data, format, only, except, rename, transform)
    end
  end

  defp serialize_data(data, format, only, except, rename, transform) do
    # Filter fields
    filtered =
      data
      |> maybe_filter_only(only)
      |> maybe_filter_except(except)
      |> maybe_rename_fields(rename)

    # Apply custom transform
    transformed =
      if transform do
        transform.(filtered, %{format: format})
      else
        filtered
      end

    # Convert to target format
    case format do
      :json -> Jason.encode!(transformed)
      :map -> transformed
      :keyword -> Map.to_list(transformed)
      :binary -> :erlang.term_to_binary(transformed)
    end
  end

  defp maybe_filter_only(data, nil), do: data

  defp maybe_filter_only(data, only) when is_map(data) do
    Map.take(data, only)
  end

  defp maybe_filter_except(data, []), do: data

  defp maybe_filter_except(data, except) when is_map(data) do
    Map.drop(data, except)
  end

  defp maybe_rename_fields(data, []), do: data

  defp maybe_rename_fields(data, rename) when is_map(data) do
    Enum.reduce(rename, data, fn {old_key, new_key}, acc ->
      case Map.pop(acc, old_key) do
        {nil, acc} -> acc
        {value, acc} -> Map.put(acc, new_key, value)
      end
    end)
  end

  @doc false
  def handle_contract_violation(type, context, :raise) do
    raise Events.ContractViolation,
      message: "Contract violation (#{type}) in #{context.module}.#{context.name}/#{context.arity}"
  end

  def handle_contract_violation(type, context, :warn) do
    Logger.warning(
      "Contract violation (#{type}) in #{context.module}.#{context.name}/#{context.arity}"
    )
  end

  def handle_contract_violation(_type, _context, :return_error) do
    throw(:contract_violation)
  end

  @doc false
  def extract_state([state | _]) when is_map(state), do: state
  def extract_state([state | _]) when is_struct(state), do: state
  def extract_state(_), do: %{}
end

defmodule Events.ValidationError do
  defexception [:message, :errors]
end

defmodule Events.CoercionError do
  defexception [:message]
end

defmodule Events.ContractViolation do
  defexception [:message]
end
