defmodule Events.Schema.ValidatorRegistry do
  @moduledoc """
  Registry for field type validators.

  Provides a central registry for mapping field types to their validators.
  This allows for extensibility - custom validators can be registered for
  custom field types.

  ## Built-in Type Mappings

  | Field Type | Validator Module |
  |------------|------------------|
  | `:string`, `:citext` | `Events.Schema.Validators.String` |
  | `:integer`, `:float`, `:decimal` | `Events.Schema.Validators.Number` |
  | `:boolean` | `Events.Schema.Validators.Boolean` |
  | `{:array, _}` | `Events.Schema.Validators.Array` |
  | `:map` | `Events.Schema.Validators.Map` |
  | `:utc_datetime`, `:utc_datetime_usec`, `:date`, `:naive_datetime` | `Events.Schema.Validators.DateTime` |

  ## Custom Validators

  Register custom validators at application startup:

      # In application.ex or config
      Events.Schema.ValidatorRegistry.register(:money, MyApp.MoneyValidator)

  ## Usage

      validator = Events.Schema.ValidatorRegistry.get(:string)
      changeset = validator.validate(changeset, :name, min_length: 2)
  """

  use Agent

  alias Events.Schema.Validators

  @default_validators %{
    # String types
    string: Validators.String,
    citext: Validators.String,

    # Numeric types
    integer: Validators.Number,
    float: Validators.Number,
    decimal: Validators.Number,

    # Boolean
    boolean: Validators.Boolean,

    # Map
    map: Validators.Map,

    # DateTime types
    utc_datetime: Validators.DateTime,
    utc_datetime_usec: Validators.DateTime,
    naive_datetime: Validators.DateTime,
    naive_datetime_usec: Validators.DateTime,
    date: Validators.DateTime,
    time: Validators.DateTime
  }

  @doc """
  Starts the validator registry.

  Called automatically by the Events application supervisor.
  """
  def start_link(_opts) do
    Agent.start_link(fn -> @default_validators end, name: __MODULE__)
  end

  @doc """
  Gets the validator module for a field type.

  Returns `nil` if no validator is registered for the type.

  ## Examples

      iex> Events.Schema.ValidatorRegistry.get(:string)
      Events.Schema.Validators.String

      iex> Events.Schema.ValidatorRegistry.get(:unknown_type)
      nil

      iex> Events.Schema.ValidatorRegistry.get({:array, :string})
      Events.Schema.Validators.Array
  """
  @spec get(atom() | tuple()) :: module() | nil
  def get({:array, _inner_type}), do: Validators.Array
  def get({:map, _inner_type}), do: Validators.Map
  def get({:parameterized, Ecto.Enum, _}), do: Validators.String

  def get(field_type) when is_atom(field_type) do
    case Process.whereis(__MODULE__) do
      nil ->
        # Agent not started, use defaults
        Map.get(@default_validators, field_type)

      _pid ->
        Agent.get(__MODULE__, &Map.get(&1, field_type))
    end
  end

  def get(_), do: nil

  @doc """
  Registers a validator module for a field type.

  The validator module must implement `Events.Schema.Behaviours.Validator`.

  ## Examples

      Events.Schema.ValidatorRegistry.register(:money, MyApp.MoneyValidator)
      Events.Schema.ValidatorRegistry.register(:phone, MyApp.PhoneValidator)

  ## Raises

  - `ArgumentError` if the module doesn't implement the Validator behavior
  """
  @spec register(atom(), module()) :: :ok
  def register(field_type, validator_module)
      when is_atom(field_type) and is_atom(validator_module) do
    # Verify the module implements the behavior
    unless function_exported?(validator_module, :validate, 3) do
      raise ArgumentError,
            "Validator module #{inspect(validator_module)} must implement validate/3 callback"
    end

    case Process.whereis(__MODULE__) do
      nil ->
        raise RuntimeError,
              "ValidatorRegistry not started. Add Events.Schema.ValidatorRegistry to your supervision tree."

      _pid ->
        Agent.update(__MODULE__, &Map.put(&1, field_type, validator_module))
    end
  end

  @doc """
  Unregisters a validator for a field type.

  Reverts to no validator (nil) for that type, unless it's a built-in type,
  in which case it reverts to the default validator.

  ## Examples

      Events.Schema.ValidatorRegistry.unregister(:custom_type)
  """
  @spec unregister(atom()) :: :ok
  def unregister(field_type) when is_atom(field_type) do
    default = Map.get(@default_validators, field_type)

    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      _pid ->
        if default do
          Agent.update(__MODULE__, &Map.put(&1, field_type, default))
        else
          Agent.update(__MODULE__, &Map.delete(&1, field_type))
        end
    end
  end

  @doc """
  Returns all registered validators as a map.

  ## Examples

      iex> Events.Schema.ValidatorRegistry.all()
      %{
        string: Events.Schema.Validators.String,
        integer: Events.Schema.Validators.Number,
        ...
      }
  """
  @spec all() :: %{atom() => module()}
  def all do
    case Process.whereis(__MODULE__) do
      nil -> @default_validators
      _pid -> Agent.get(__MODULE__, & &1)
    end
  end

  @doc """
  Returns the default validators (before any custom registrations).
  """
  @spec defaults() :: %{atom() => module()}
  def defaults, do: @default_validators

  @doc """
  Checks if a validator is registered for a field type.

  ## Examples

      iex> Events.Schema.ValidatorRegistry.registered?(:string)
      true

      iex> Events.Schema.ValidatorRegistry.registered?(:unknown)
      false
  """
  @spec registered?(atom()) :: boolean()
  def registered?(field_type) do
    get(field_type) != nil
  end

  @doc """
  Resets the registry to default validators.

  Useful for testing.
  """
  @spec reset() :: :ok
  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> Agent.update(__MODULE__, fn _ -> @default_validators end)
    end
  end
end
