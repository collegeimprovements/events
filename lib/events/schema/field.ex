defmodule Events.Schema.Field do
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
  Define a field with enhanced validation support.

  All standard Ecto field options are supported, plus additional validation options.

  ## Common Options

    * `:cast` - Include in changeset cast (default: true)
    * `:required` - Mark as required field (default: false)
    * `:null` - Allow nil values (default: true if not required, false if required)
    * `:message` - Default error message for all validations
    * `:messages` - Map of validation-specific error messages

  ## String Validation Options

    * `:min_length` - Minimum length
    * `:max_length` - Maximum length
    * `:length` - Exact length or range
    * `:format` - Regex pattern or named format (:email, :url, etc.)
    * `:trim` - Auto-trim whitespace (default: true)
    * `:normalize` - Normalization function (:downcase, :upcase, :slugify, etc.)
    * `:in` - List of allowed values
    * `:not_in` - List of disallowed values

  ## Number Validation Options

    * `:min` - Minimum value (alias for :greater_than_or_equal_to)
    * `:max` - Maximum value (alias for :less_than_or_equal_to)
    * `:greater_than` - Must be greater than
    * `:greater_than_or_equal_to` - Must be greater than or equal to
    * `:less_than` - Must be less than
    * `:less_than_or_equal_to` - Must be less than or equal to
    * `:equal_to` - Must be equal to
    * `:positive` - Must be > 0
    * `:non_negative` - Must be >= 0
    * `:negative` - Must be < 0
    * `:non_positive` - Must be <= 0
    * `:in` - List of allowed values

  ## Examples

      # Simple field with default cast: true
      field :name, :string

      # Required field with validation
      field :email, :string,
        required: true,
        format: :email,
        max_length: 255

      # Number with shortcuts
      field :age, :integer,
        positive: true,
        max: 150

      # Enum field
      field :status, :string,
        in: ["active", "inactive"],
        default: "active"

      # Slugified field
      field :slug, :string,
        normalize: {:slugify, uniquify: true}
  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      # Split validation options from Ecto options
      {validation_opts, ecto_opts} =
        Events.Schema.Field.__split_options__(opts, type)

      # Set defaults for cast and required
      validation_opts =
        validation_opts
        |> Keyword.put_new(:cast, true)
        |> Keyword.put_new(:required, false)

      # Handle null default based on required
      validation_opts =
        if Keyword.has_key?(validation_opts, :null) do
          validation_opts
        else
          null_default = !Keyword.get(validation_opts, :required, false)
          Keyword.put(validation_opts, :null, null_default)
        end

      # Store validation metadata
      Module.put_attribute(__MODULE__, :field_validations, {name, type, validation_opts})

      # Call Ecto's underlying field function
      Ecto.Schema.__field__(__MODULE__, name, type, ecto_opts)
    end
  end

  @doc false
  def __split_options__(opts, type, field_name \\ :unknown) do
    # Check for warnings if enabled
    if Application.get_env(:events, :schema_warnings, true) do
      Events.Schema.Warnings.check_field_options(field_name, type, opts)
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
        # String
        :min_length,
        :max_length,
        :length,
        :format,
        :trim,
        :normalize,
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

    Keyword.split(opts, validation_keys)
  end
end
