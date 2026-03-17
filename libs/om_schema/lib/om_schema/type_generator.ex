defmodule OmSchema.TypeGenerator do
  @moduledoc """
  Generates Elixir typespecs from OmSchema field definitions.

  This module maps Ecto types to their corresponding Elixir types and
  generates `@type t()` definitions based on field validations.

  ## Usage

  This module is used internally by OmSchema to auto-generate typespecs.
  You can also use it directly for introspection:

      # Get Elixir type for an Ecto type
      TypeGenerator.ecto_to_elixir_type(:string)
      # => {:type, :string}

      # Generate type AST from field validations
      TypeGenerator.generate_type_ast(field_validations)

  ## Type Mapping

  | Ecto Type | Elixir Type |
  |-----------|-------------|
  | `:string` | `String.t()` |
  | `:integer` | `integer()` |
  | `:float` | `float()` |
  | `:decimal` | `Decimal.t()` |
  | `:boolean` | `boolean()` |
  | `:binary` | `binary()` |
  | `:binary_id` | `binary()` |
  | `:id` | `integer()` |
  | `:map` | `map()` |
  | `{:map, inner}` | `%{optional(atom()) => inner_type}` |
  | `{:array, inner}` | `[inner_type]` |
  | `:date` | `Date.t()` |
  | `:time` | `Time.t()` |
  | `:naive_datetime` | `NaiveDateTime.t()` |
  | `:utc_datetime` | `DateTime.t()` |
  | `:utc_datetime_usec` | `DateTime.t()` |
  | `Ecto.Enum` | Union of atom literals |
  | `Ecto.UUID` | `String.t()` |
  """

  @doc """
  Maps an Ecto type to its Elixir type representation.

  Returns a tuple of `{:type, type_ast}` or `{:remote, module, type}` for remote types.

  ## Examples

      iex> TypeGenerator.ecto_to_elixir_type(:string)
      {:remote, String, :t}

      iex> TypeGenerator.ecto_to_elixir_type(:integer)
      {:type, :integer}

      iex> TypeGenerator.ecto_to_elixir_type({:array, :string})
      {:list, {:remote, String, :t}}

  """
  @spec ecto_to_elixir_type(atom() | tuple(), keyword()) :: tuple()
  def ecto_to_elixir_type(ecto_type, opts \\ [])

  # String types
  def ecto_to_elixir_type(:string, _opts), do: {:remote, String, :t}
  def ecto_to_elixir_type(:citext, _opts), do: {:remote, String, :t}

  # Numeric types
  def ecto_to_elixir_type(:integer, _opts), do: {:type, :integer}
  def ecto_to_elixir_type(:float, _opts), do: {:type, :float}
  def ecto_to_elixir_type(:decimal, _opts), do: {:remote, Decimal, :t}
  def ecto_to_elixir_type(:id, _opts), do: {:type, :integer}

  # Boolean
  def ecto_to_elixir_type(:boolean, _opts), do: {:type, :boolean}

  # Binary types
  def ecto_to_elixir_type(:binary, _opts), do: {:type, :binary}
  def ecto_to_elixir_type(:binary_id, _opts), do: {:type, :binary}
  def ecto_to_elixir_type(Ecto.UUID, _opts), do: {:remote, String, :t}

  # Map types
  def ecto_to_elixir_type(:map, _opts), do: {:type, :map}

  def ecto_to_elixir_type({:map, inner_type}, opts) do
    inner = ecto_to_elixir_type(inner_type, opts)
    {:map_of, {:type, :atom}, inner}
  end

  # Array types
  def ecto_to_elixir_type({:array, inner_type}, opts) do
    inner = ecto_to_elixir_type(inner_type, opts)
    {:list, inner}
  end

  # Date/Time types
  def ecto_to_elixir_type(:date, _opts), do: {:remote, Date, :t}
  def ecto_to_elixir_type(:time, _opts), do: {:remote, Time, :t}
  def ecto_to_elixir_type(:time_usec, _opts), do: {:remote, Time, :t}
  def ecto_to_elixir_type(:naive_datetime, _opts), do: {:remote, NaiveDateTime, :t}
  def ecto_to_elixir_type(:naive_datetime_usec, _opts), do: {:remote, NaiveDateTime, :t}
  def ecto_to_elixir_type(:utc_datetime, _opts), do: {:remote, DateTime, :t}
  def ecto_to_elixir_type(:utc_datetime_usec, _opts), do: {:remote, DateTime, :t}

  # Enum type - handled specially with values
  def ecto_to_elixir_type(Ecto.Enum, opts) do
    case Keyword.get(opts, :values) do
      nil -> {:type, :atom}
      values when is_list(values) -> {:union, Enum.map(values, &{:literal, &1})}
    end
  end

  # Any type
  def ecto_to_elixir_type(:any, _opts), do: {:type, :any}

  # Parameterized type wrapper
  def ecto_to_elixir_type({:parameterized, type, _params}, opts) do
    ecto_to_elixir_type(type, opts)
  end

  # Fallback for unknown types
  def ecto_to_elixir_type(_type, _opts), do: {:type, :any}

  @doc """
  Generates the complete `@type t()` AST for a schema module.

  Takes a list of field validations `{name, type, opts}` and generates
  the AST for a struct typespec.

  ## Options

    * `:include_id` - Include the `:id` field (default: `true`)
    * `:id_type` - Type for the `:id` field (default: `:binary_id`)

  ## Example

      field_validations = [
        {:name, :string, [required: true]},
        {:age, :integer, [required: false]},
        {:status, Ecto.Enum, [values: [:active, :inactive]]}
      ]

      TypeGenerator.generate_type_ast(field_validations)
      # => AST for %__MODULE__{name: String.t(), age: integer() | nil, ...}

  """
  @spec generate_type_ast([{atom(), atom() | tuple(), keyword()}], keyword()) :: tuple()
  def generate_type_ast(field_validations, opts \\ []) do
    include_id = Keyword.get(opts, :include_id, true)
    id_type = Keyword.get(opts, :id_type, :binary_id)

    # Start with id field if included
    fields =
      if include_id do
        id_spec = type_to_ast(ecto_to_elixir_type(id_type), nullable: true)
        [{:id, id_spec}]
      else
        []
      end

    # Add all schema fields
    fields =
      fields ++
        Enum.map(field_validations, fn {name, type, field_opts} ->
          required = Keyword.get(field_opts, :required, false)
          nullable = not required
          enum_values = Keyword.get(field_opts, :values)

          type_opts =
            if type == Ecto.Enum and enum_values do
              [values: enum_values]
            else
              []
            end

          type_repr = ecto_to_elixir_type(type, type_opts)
          type_ast = type_to_ast(type_repr, nullable: nullable)
          {name, type_ast}
        end)

    # Generate struct type
    struct_ast(fields)
  end

  @doc """
  Converts a type representation to Elixir AST.

  ## Options

    * `:nullable` - Wrap type in `| nil` union (default: `false`)

  """
  @spec type_to_ast(tuple(), keyword()) :: tuple()
  def type_to_ast(type_repr, opts \\ [])

  def type_to_ast({:type, type}, opts) do
    base = {type, [], []}
    maybe_nullable(base, opts)
  end

  def type_to_ast({:remote, module, type}, opts) do
    base =
      {{:., [], [{:__aliases__, [alias: false], [module]}, type]}, [no_parens: true], []}

    maybe_nullable(base, opts)
  end

  def type_to_ast({:list, inner}, opts) do
    inner_ast = type_to_ast(inner, nullable: false)
    base = [inner_ast]
    maybe_nullable(base, opts)
  end

  def type_to_ast({:map_of, key_type, value_type}, opts) do
    key_ast = type_to_ast(key_type, nullable: false)
    value_ast = type_to_ast(value_type, nullable: false)

    base =
      {:%{}, [],
       [
         {{:optional, [], [key_ast]}, value_ast}
       ]}

    maybe_nullable(base, opts)
  end

  def type_to_ast({:union, types}, opts) do
    type_asts = Enum.map(types, &type_to_ast(&1, nullable: false))

    base =
      Enum.reduce(type_asts, fn type, acc ->
        {:|, [], [acc, type]}
      end)

    maybe_nullable(base, opts)
  end

  def type_to_ast({:literal, value}, _opts) when is_atom(value) do
    value
  end

  defp maybe_nullable(ast, opts) do
    if Keyword.get(opts, :nullable, false) do
      {:|, [], [ast, nil]}
    else
      ast
    end
  end

  defp struct_ast(fields) do
    field_asts =
      Enum.map(fields, fn {name, type_ast} ->
        {name, type_ast}
      end)

    {:%, [],
     [
       {:__MODULE__, [], Elixir},
       {:%{}, [], field_asts}
     ]}
  end

  @doc """
  Generates the `@type t()` definition as quoted code.

  Returns a quote block that can be injected into a module.

  ## Example

      TypeGenerator.generate_type_definition(field_validations)
      # Returns quoted code for:
      # @type t() :: %__MODULE__{...}

  """
  @spec generate_type_definition([{atom(), atom() | tuple(), keyword()}], keyword()) ::
          Macro.t()
  def generate_type_definition(field_validations, opts \\ []) do
    type_ast = generate_type_ast(field_validations, opts)

    quote do
      @type t() :: unquote(type_ast)
    end
  end

  @doc """
  Returns the typespec string representation for a schema.

  Useful for documentation and debugging.

  ## Example

      TypeGenerator.to_typespec_string(field_validations)
      # => "@type t() :: %__MODULE__{name: String.t(), age: integer() | nil}"

  """
  @spec to_typespec_string([{atom(), atom() | tuple(), keyword()}], keyword()) :: String.t()
  def to_typespec_string(field_validations, opts \\ []) do
    type_def = generate_type_definition(field_validations, opts)
    Macro.to_string(type_def)
  end
end
