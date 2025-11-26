defmodule Events.Migration.Behaviours.FieldBuilder do
  @moduledoc """
  Behaviour for migration field builders.

  Field builders are modules that add predefined sets of fields to a migration token.
  They follow a consistent pattern for configuration and field generation.

  ## Implementing a Field Builder

      defmodule MyApp.Migration.CustomFields do
        @behaviour Events.Migration.Behaviours.FieldBuilder

        @impl true
        def default_config do
          %{
            type: :string,
            null: true,
            fields: [:custom_field_1, :custom_field_2]
          }
        end

        @impl true
        def build(token, config) do
          Enum.reduce(config.fields, token, fn field_name, acc ->
            Token.add_field(acc, field_name, config.type, null: config.null)
          end)
        end
      end
  """

  alias Events.Migration.Token

  @type config :: map()

  @doc """
  Returns the default configuration for this field builder.

  The config map typically includes:
  - `:type` - The field type (:string, :citext, :integer, etc.)
  - `:null` - Whether fields can be null
  - `:fields` - List of field names to generate
  - Additional builder-specific options
  """
  @callback default_config() :: config()

  @doc """
  Builds fields onto the token using the given configuration.

  The configuration is the result of merging user options with `default_config/0`.
  """
  @callback build(Token.t(), config()) :: Token.t()

  @doc """
  Optional callback for additional indexes.

  Return a list of index specifications to be added to the token.
  """
  @callback indexes(config()) :: [{atom(), [atom()], keyword()}]

  @optional_callbacks [indexes: 1]

  # ============================================
  # Helper Functions for Implementations
  # ============================================

  @doc """
  Merges user options with default config, handling :only and :except filters.

  ## Examples

      config = FieldBuilder.merge_config(
        %{type: :string, fields: [:a, :b, :c]},
        [only: [:a, :b], type: :citext]
      )
      # => %{type: :citext, fields: [:a, :b]}
  """
  @spec merge_config(config(), keyword()) :: config()
  def merge_config(defaults, opts) when is_map(defaults) and is_list(opts) do
    # Convert opts to map for merging
    opts_map = Map.new(opts)

    # Start with defaults
    config = Map.merge(defaults, opts_map)

    # Apply field filtering if :fields is present
    case Map.get(defaults, :fields) do
      nil ->
        config

      all_fields ->
        filtered = filter_fields(all_fields, opts)
        Map.put(config, :fields, filtered)
    end
  end

  @doc """
  Filters fields based on :only and :except options.
  """
  @spec filter_fields([atom()], keyword()) :: [atom()]
  def filter_fields(all_fields, opts) do
    only = Keyword.get(opts, :only)
    except = Keyword.get(opts, :except, [])

    fields =
      case only do
        nil -> Enum.reject(all_fields, &(&1 in except))
        only_list -> Enum.filter(all_fields, &(&1 in only_list))
      end

    case fields do
      [] ->
        raise ArgumentError,
              "No fields selected after filtering with only: #{inspect(only)}, except: #{inspect(except)}"

      filtered ->
        filtered
    end
  end

  @doc """
  Applies a field builder module to a token with options.

  This is the standard way to invoke a field builder:

      token
      |> FieldBuilder.apply(Events.Migration.FieldBuilders.Timestamps, with_deleted: true)
  """
  @spec apply(Token.t(), module(), keyword()) :: Token.t()
  def apply(%Token{} = token, module, opts \\ []) when is_atom(module) do
    defaults = module.default_config()
    config = merge_config(defaults, opts)

    token
    |> module.build(config)
    |> maybe_add_indexes(module, config)
  end

  defp maybe_add_indexes(token, module, config) do
    if function_exported?(module, :indexes, 1) do
      module.indexes(config)
      |> Enum.reduce(token, fn {name, columns, opts}, acc ->
        Token.add_index(acc, name, columns, opts)
      end)
    else
      token
    end
  end
end
