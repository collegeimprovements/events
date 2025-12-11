defmodule OmSchema.Behaviours.Validator do
  @moduledoc """
  Behavior for field type validators.

  Implement this behavior to create custom validators for field types.
  All validators must implement the `validate/3` callback and `field_types/0`.

  ## Example

      defmodule MyApp.CustomValidator do
        @behaviour OmSchema.Behaviours.Validator

        @impl true
        def field_types, do: [:my_custom_type]

        @impl true
        def supported_options, do: [:custom_option, :another_option]

        @impl true
        def validate(changeset, field_name, opts) do
          # Your validation logic here
          changeset
        end
      end

  Then register it:

      OmSchema.ValidatorRegistry.register(:my_custom_type, MyApp.CustomValidator)
  """

  @type changeset :: Ecto.Changeset.t()
  @type field_name :: atom()
  @type opts :: keyword()

  @doc """
  Returns the list of field types this validator handles.

  ## Example

      def field_types, do: [:string, :citext]
  """
  @callback field_types() :: [atom()]

  @doc """
  Returns the list of options this validator supports.

  Used for documentation and validation of options.

  ## Example

      def supported_options, do: [:min_length, :max_length, :format, :trim]
  """
  @callback supported_options() :: [atom()]

  @doc """
  Validates a field in the changeset according to the provided options.

  ## Arguments

  - `changeset` - The Ecto changeset to validate
  - `field_name` - The name of the field being validated
  - `opts` - Keyword list of validation options

  ## Returns

  The changeset, potentially with errors added.

  ## Example

      def validate(changeset, field_name, opts) do
        changeset
        |> maybe_validate_min_length(field_name, opts[:min_length])
        |> maybe_validate_format(field_name, opts[:format])
      end
  """
  @callback validate(changeset, field_name, opts) :: changeset

  @optional_callbacks [supported_options: 0]

  @doc """
  Helper to check if a module implements the Validator behavior.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    behaviours = module.__info__(:attributes)[:behaviour] || []
    __MODULE__ in behaviours
  end
end
