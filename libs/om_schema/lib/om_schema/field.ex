defmodule OmSchema.Field do
  @moduledoc """
  Field option utilities for OmSchema.

  Provides internal helpers for splitting field options between
  validation options and Ecto schema options.

  Use `use OmSchema` to get the enhanced field macro.
  """

  @app_name Application.compile_env(:om_schema, :app_name, :om_schema)

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
        # Documentation & Meta
        :doc,
        :example,
        # Custom Validators
        :validators,
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

    {validation_opts, ecto_opts} = Keyword.split(opts, validation_keys)

    # For Ecto.Enum, copy :values to validation_opts for introspection
    # (values must remain in ecto_opts for Ecto to work)
    validation_opts =
      if type == Ecto.Enum do
        case Keyword.get(ecto_opts, :values) do
          nil -> validation_opts
          values -> Keyword.put(validation_opts, :values, values)
        end
      else
        validation_opts
      end

    # Copy :default from ecto_opts to validation_opts for introspection
    validation_opts =
      case Keyword.get(ecto_opts, :default) do
        nil -> validation_opts
        default -> Keyword.put(validation_opts, :default, default)
      end

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
