defmodule Events.Migration.Token do
  @moduledoc """
  The core token that flows through migration pipelines.

  A token represents a migration operation (table, index, etc.) and accumulates
  changes as it flows through the pipeline.
  """

  defstruct [
    # :table, :index, :constraint, etc.
    :type,
    # Table or index name
    :name,
    # List of field definitions
    :fields,
    # List of index definitions
    :indexes,
    # List of constraints
    :constraints,
    # Additional options
    :options,
    # Metadata for tracking
    :meta
  ]

  @type field :: {atom(), atom(), keyword()}
  @type index :: {atom(), list(atom()), keyword()}
  @type constraint :: {atom(), atom(), keyword()}

  @type t :: %__MODULE__{
          type: atom(),
          name: atom() | String.t(),
          fields: list(field()),
          indexes: list(index()),
          constraints: list(constraint()),
          options: keyword(),
          meta: map()
        }

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
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{type: :table, name: name, fields: fields} = token)
      when is_atom(name) or is_binary(name) do
    cond do
      length(fields) == 0 ->
        {:error, "Table #{name} has no fields defined"}

      not has_primary_key?(token) ->
        {:error, "Table #{name} has no primary key defined"}

      true ->
        {:ok, token}
    end
  end

  def validate(%__MODULE__{type: :index, name: name} = token) do
    columns = Keyword.get(token.options, :columns, [])

    if length(columns) == 0 do
      {:error, "Index #{name} has no columns defined"}
    else
      {:ok, token}
    end
  end

  def validate(token), do: {:ok, token}

  defp has_primary_key?(token) do
    token.fields
    |> Enum.any?(fn {_name, _type, opts} ->
      Keyword.get(opts, :primary_key, false)
    end) ||
      Keyword.get(token.options, :primary_key, true) != false
  end
end
