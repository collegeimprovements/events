defmodule OmSchema.Field do
  @moduledoc """
  Enhanced field macro that extends Ecto.Schema.field with validation metadata.

  This module provides a drop-in replacement for Ecto's field macro that:
  - Stores validation rules as module attributes
  - Supports cast: true/false (default: true)
  - Supports required: true/false (default: false)
  - Supports comprehensive validation options per type
  - Generates helper functions for changesets
  """

  @doc """
  Backwards-compatible `field/3` macro that now delegates to `OmSchema.field/3`.

  Prefer `use OmSchema` and its imported macro directly. This definition
  remains so older modules that `import OmSchema.Field` continue to work,
  but the implementation lives in `OmSchema` to avoid divergence.
  """
  @deprecated "Import OmSchema.field/3 via `use OmSchema` instead"
  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      require OmSchema
      OmSchema.field(unquote(name), unquote(type), unquote(opts))
    end
  end

  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)

  @doc false
  def __split_options__(opts, type, field_name \\ :unknown) do
    # Check for warnings if enabled
    if Application.get_env(@app_name, :schema_warnings, true) do
      OmSchema.Warnings.check_field_options(field_name, type, opts)
    end

    # Define which options are validation-specific
    validation_keys =
      [
        # Common
        :cast,
        :required,
        :null,
        :message,
        :messages,
        :validate,
        :validate_if,
        :validate_unless,
        # Behavioral
        :immutable,
        :sensitive,
        :required_when,
        # Documentation
        :doc,
        :example,
        # String
        :min_length,
        :max_length,
        :length,
        :format,
        :trim,
        :normalize,
        :mappers,
        :in,
        :not_in,
        # Number
        :min,
        :max,
        :greater_than,
        :greater_than_or_equal_to,
        :less_than,
        :less_than_or_equal_to,
        :equal_to,
        :gt,
        :gte,
        :lt,
        :lte,
        :eq,
        :positive,
        :non_negative,
        :negative,
        :non_positive,
        :multiple_of,
        # Boolean
        :acceptance,
        # Array
        :unique_items,
        :item_format,
        :item_min,
        :item_max,
        # Map
        :required_keys,
        :optional_keys,
        :forbidden_keys,
        :min_keys,
        :max_keys,
        :schema,
        :value_type,
        # Date/Time
        :after,
        :before,
        :past,
        :future,
        # Constraints
        :unique,
        :foreign_key,
        :check
      ]

    # Handle Ecto.Enum specially - values is an Ecto option
    validation_keys =
      if type == Ecto.Enum do
        validation_keys
      else
        validation_keys
      end

    {validation_opts, ecto_opts} = Keyword.split(opts, validation_keys)

    # Auto-add redact: true when sensitive: true
    ecto_opts =
      if Keyword.get(validation_opts, :sensitive, false) && !Keyword.has_key?(ecto_opts, :redact) do
        Keyword.put(ecto_opts, :redact, true)
      else
        ecto_opts
      end

    {validation_opts, ecto_opts}
  end
end
