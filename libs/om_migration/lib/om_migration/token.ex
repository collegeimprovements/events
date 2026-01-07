defmodule OmMigration.Token do
  @moduledoc """
  The core token that flows through migration pipelines.

  A token represents a migration operation (table, index, etc.) and accumulates
  changes as it flows through the pipeline. Tokens are immutable - each operation
  returns a new token.

  ## Token Types

  - `:table` - Creates a new table with fields, indexes, and constraints
  - `:index` - Creates a standalone index
  - `:constraint` - Creates a standalone constraint
  - `:alter` - Alters an existing table

  ## Pipeline Pattern

  Tokens flow through a pipeline of transformations:

      create_table(:users)
      |> with_uuid_primary_key()
      |> with_timestamps()
      |> with_soft_delete()
      |> run()

  ## Validation

  Before execution, tokens are validated to ensure they have all required fields.
  Use `validate/1` or `validate!/1` to check a token manually.
  """

  @type token_type :: :table | :index | :constraint | :alter
  @type field_type :: atom() | {:array, atom()} | {:references, atom(), keyword()}
  @type field :: {atom(), field_type(), keyword()}
  @type index_spec :: {atom(), [atom()], keyword()}
  @type constraint_spec :: {atom(), atom(), keyword()}

  @type t :: %__MODULE__{
          type: token_type(),
          name: atom() | String.t(),
          fields: [field()],
          indexes: [index_spec()],
          constraints: [constraint_spec()],
          options: keyword(),
          meta: map()
        }

  @enforce_keys [:type, :name]
  defstruct type: nil,
            name: nil,
            fields: [],
            indexes: [],
            constraints: [],
            options: [],
            meta: %{}

  @doc """
  Creates a new migration token.

  ## Examples

      Token.new(:table, :users)
      Token.new(:index, :users, columns: [:email])
  """
  @spec new(atom(), atom() | String.t(), keyword()) :: t()
  def new(type, name, opts \\ []) do
    %__MODULE__{
      type: type,
      name: name,
      fields: [],
      indexes: [],
      constraints: [],
      options: opts,
      meta: %{created_at: DateTime.utc_now()}
    }
  end

  @doc """
  Adds a field to the token.

  ## Examples

      token
      |> Token.add_field(:email, :string, null: false)
      |> Token.add_field(:age, :integer, min: 0)
  """
  @spec add_field(t(), atom(), atom(), keyword()) :: t()
  def add_field(%__MODULE__{fields: fields} = token, name, type, opts \\ []) do
    %{token | fields: fields ++ [{name, type, opts}]}
  end

  @doc """
  Adds multiple fields to the token.
  """
  @spec add_fields(t(), list(field())) :: t()
  def add_fields(%__MODULE__{fields: fields} = token, new_fields) do
    %{token | fields: fields ++ new_fields}
  end

  @doc """
  Adds an index to the token.
  """
  @spec add_index(t(), atom(), list(atom()), keyword()) :: t()
  def add_index(%__MODULE__{indexes: indexes} = token, name, columns, opts \\ []) do
    %{token | indexes: indexes ++ [{name, columns, opts}]}
  end

  @doc """
  Adds a constraint to the token.
  """
  @spec add_constraint(t(), atom(), atom(), keyword()) :: t()
  def add_constraint(%__MODULE__{constraints: constraints} = token, name, type, opts \\ []) do
    %{token | constraints: constraints ++ [{name, type, opts}]}
  end

  @doc """
  Updates token options.
  """
  @spec put_option(t(), atom(), any()) :: t()
  def put_option(%__MODULE__{options: opts} = token, key, value) do
    %{token | options: Keyword.put(opts, key, value)}
  end

  @doc """
  Merges options into the token.
  """
  @spec merge_options(t(), keyword()) :: t()
  def merge_options(%__MODULE__{options: opts} = token, new_opts) do
    %{token | options: Keyword.merge(opts, new_opts)}
  end

  @doc """
  Updates token metadata.
  """
  @spec put_meta(t(), atom(), any()) :: t()
  def put_meta(%__MODULE__{meta: meta} = token, key, value) do
    %{token | meta: Map.put(meta, key, value)}
  end

  @doc """
  Validates the token before execution.

  Returns `{:ok, token}` if valid, `{:error, message}` otherwise.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{type: :table, name: name, fields: []} = _token) do
    {:error, "Table #{name} has no fields defined"}
  end

  def validate(%__MODULE__{type: :table, name: name} = token) do
    case has_primary_key?(token) do
      true -> {:ok, token}
      false -> {:error, "Table #{name} has no primary key defined"}
    end
  end

  def validate(%__MODULE__{type: :index, name: name, options: opts} = token) do
    case Keyword.get(opts, :columns, []) do
      [] -> {:error, "Index #{name} has no columns defined"}
      _columns -> {:ok, token}
    end
  end

  def validate(%__MODULE__{} = token), do: {:ok, token}

  @doc """
  Validates the token, raising on error.

  Same as `validate/1` but raises `ArgumentError` on failure.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = token) do
    case validate(token) do
      {:ok, valid_token} -> valid_token
      {:error, message} -> raise ArgumentError, message
    end
  end

  # ============================================
  # Query Functions
  # ============================================

  @doc """
  Returns true if the token has a primary key defined.
  """
  @spec has_primary_key?(t()) :: boolean()
  def has_primary_key?(%__MODULE__{fields: fields, options: opts}) do
    field_has_pk? = Enum.any?(fields, &field_is_primary_key?/1)
    opts_has_pk? = Keyword.get(opts, :primary_key, true) != false
    field_has_pk? or opts_has_pk?
  end

  @doc """
  Returns the field names defined in the token.
  """
  @spec field_names(t()) :: [atom()]
  def field_names(%__MODULE__{fields: fields}) do
    Enum.map(fields, fn {name, _type, _opts} -> name end)
  end

  @doc """
  Returns the index names defined in the token.
  """
  @spec index_names(t()) :: [atom()]
  def index_names(%__MODULE__{indexes: indexes}) do
    Enum.map(indexes, fn {name, _columns, _opts} -> name end)
  end

  @doc """
  Checks if a field exists in the token.
  """
  @spec has_field?(t(), atom()) :: boolean()
  def has_field?(%__MODULE__{fields: fields}, field_name) do
    Enum.any?(fields, fn {name, _type, _opts} -> name == field_name end)
  end

  @doc """
  Gets a field definition by name.
  """
  @spec get_field(t(), atom()) :: field() | nil
  def get_field(%__MODULE__{fields: fields}, field_name) do
    Enum.find(fields, fn {name, _type, _opts} -> name == field_name end)
  end

  @doc """
  Checks if an index exists in the token.
  """
  @spec has_index?(t(), atom()) :: boolean()
  def has_index?(%__MODULE__{indexes: indexes}, index_name) do
    Enum.any?(indexes, fn {name, _columns, _opts} -> name == index_name end)
  end

  @doc """
  Gets an index definition by name.
  """
  @spec get_index(t(), atom()) :: index_spec() | nil
  def get_index(%__MODULE__{indexes: indexes}, index_name) do
    Enum.find(indexes, fn {name, _columns, _opts} -> name == index_name end)
  end

  @doc """
  Returns the constraint names defined in the token.
  """
  @spec constraint_names(t()) :: [atom()]
  def constraint_names(%__MODULE__{constraints: constraints}) do
    Enum.map(constraints, fn {name, _type, _opts} -> name end)
  end

  @doc """
  Checks if a constraint exists in the token.
  """
  @spec has_constraint?(t(), atom()) :: boolean()
  def has_constraint?(%__MODULE__{constraints: constraints}, constraint_name) do
    Enum.any?(constraints, fn {name, _type, _opts} -> name == constraint_name end)
  end

  @doc """
  Gets a constraint definition by name.
  """
  @spec get_constraint(t(), atom()) :: constraint_spec() | nil
  def get_constraint(%__MODULE__{constraints: constraints}, constraint_name) do
    Enum.find(constraints, fn {name, _type, _opts} -> name == constraint_name end)
  end

  @doc """
  Returns all foreign key fields in the token.
  """
  @spec foreign_keys(t()) :: [field()]
  def foreign_keys(%__MODULE__{fields: fields}) do
    Enum.filter(fields, fn
      {_name, {:references, _table, _opts}, _field_opts} -> true
      _ -> false
    end)
  end

  @doc """
  Returns the referenced table names from foreign keys.
  """
  @spec referenced_tables(t()) :: [atom()]
  def referenced_tables(%__MODULE__{} = token) do
    token
    |> foreign_keys()
    |> Enum.map(fn {_name, {:references, table, _opts}, _field_opts} -> table end)
    |> Enum.uniq()
  end

  @doc """
  Returns fields that have unique constraints (via index or field option).
  """
  @spec unique_fields(t()) :: [atom()]
  def unique_fields(%__MODULE__{fields: fields, indexes: indexes}) do
    # Fields with unique: true option
    unique_from_fields =
      fields
      |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :unique, false) end)
      |> Enum.map(fn {name, _type, _opts} -> name end)

    # Single-column unique indexes
    unique_from_indexes =
      indexes
      |> Enum.filter(fn {_name, columns, opts} ->
        Keyword.get(opts, :unique, false) and length(columns) == 1
      end)
      |> Enum.flat_map(fn {_name, columns, _opts} -> columns end)

    Enum.uniq(unique_from_fields ++ unique_from_indexes)
  end

  @doc """
  Returns fields that are required (not null).
  """
  @spec required_fields(t()) :: [atom()]
  def required_fields(%__MODULE__{fields: fields}) do
    fields
    |> Enum.filter(fn {_name, _type, opts} -> Keyword.get(opts, :null) == false end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  @doc """
  Returns fields with default values.
  """
  @spec fields_with_defaults(t()) :: [{atom(), any()}]
  def fields_with_defaults(%__MODULE__{fields: fields}) do
    fields
    |> Enum.filter(fn {_name, _type, opts} -> Keyword.has_key?(opts, :default) end)
    |> Enum.map(fn {name, _type, opts} -> {name, Keyword.get(opts, :default)} end)
  end

  @doc """
  Returns a summary map of the token for debugging/inspection.
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = token) do
    %{
      type: token.type,
      name: token.name,
      field_count: length(token.fields),
      fields: field_names(token),
      index_count: length(token.indexes),
      indexes: index_names(token),
      constraint_count: length(token.constraints),
      constraints: constraint_names(token),
      has_primary_key: has_primary_key?(token),
      foreign_keys: referenced_tables(token),
      unique_fields: unique_fields(token),
      required_fields: required_fields(token)
    }
  end

  @doc """
  Generates Elixir schema field definitions from the token.

  Useful for documentation or schema generation.

  ## Examples

      Token.to_schema_fields(token)
      # => ["field :email, :string", "field :age, :integer"]
  """
  @spec to_schema_fields(t()) :: [String.t()]
  def to_schema_fields(%__MODULE__{fields: fields}) do
    Enum.map(fields, fn {name, type, opts} ->
      type_str = format_type(type)
      opts_str = format_schema_opts(opts)

      if opts_str == "" do
        "field :#{name}, #{type_str}"
      else
        "field :#{name}, #{type_str}, #{opts_str}"
      end
    end)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp field_is_primary_key?({_name, _type, opts}) do
    Keyword.get(opts, :primary_key, false)
  end

  defp format_type({:array, inner}), do: "{:array, :#{inner}}"
  defp format_type({:references, table, _opts}), do: "references(:#{table})"
  defp format_type(type), do: ":#{type}"

  defp format_schema_opts(opts) do
    schema_relevant = [:null, :default, :primary_key]

    opts
    |> Keyword.take(schema_relevant)
    |> Enum.map(fn
      {:null, false} -> "null: false"
      {:null, true} -> "null: true"
      {:default, val} when is_binary(val) -> "default: #{inspect(val)}"
      {:default, val} -> "default: #{inspect(val)}"
      {:primary_key, true} -> "primary_key: true"
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end
end
