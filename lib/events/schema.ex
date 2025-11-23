defmodule Events.Schema do
  @moduledoc """
  Base schema module that provides enhanced Ecto schema functionality.

  This module wraps Ecto.Schema and automatically adds common fields to all schemas:
  - UUIDv7 primary key (`id`)
  - Type classification fields (`type`, `subtype`)
  - Flexible metadata storage (`metadata` JSONB)
  - Audit tracking fields (`created_by_urm_id`, `updated_by_urm_id`)
  - Timestamps (`inserted_at`, `updated_at`)
  - Enhanced field validation with automatic changeset generation

  ## Usage

  Instead of `use Ecto.Schema`, use `Events.Schema`:

      defmodule MyApp.Accounts.User do
        use Events.Schema

        schema "users" do
          field :name, :string, required: true, min_length: 2
          field :email, :string, required: true, format: :email
          field :age, :integer, positive: true, max: 150
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs, __cast_fields__())
          |> validate_required(__required_fields__())
          |> __apply_field_validations__()
        end
      end

  ## Enhanced Field Validation

  The `field` macro is enhanced with validation options:

      field :email, :string,
        required: true,            # default: false
        cast: true,               # default: true
        format: :email,
        max_length: 255,
        trim: true,
        normalize: :downcase

      field :slug, :string,
        normalize: {:slugify, uniquify: true}  # Medium.com style slugs

      field :age, :integer,
        positive: true,           # > 0
        min: 18, max: 120        # simple syntax

      field :status, Ecto.Enum,
        values: [:active, :inactive],
        default: :active

  ## Opting Out

  You can disable automatic field additions:

      # Disable audit fields (for foundation tables like User, Role)
      use Events.Schema, audit_fields: false

      # Disable timestamps
      use Events.Schema, timestamps: false

      # Disable metadata
      use Events.Schema, metadata: false

      # Disable type/subtype
      use Events.Schema, type_fields: false

      # Combine options
      use Events.Schema, timestamps: false, audit_fields: false

  ## Custom Options

      # Custom timestamp options (only inserted_at)
      use Events.Schema, timestamps: [updated_at: false]

      # Only type field (no subtype)
      use Events.Schema, type_fields: [only: :type]
  """

  defmacro __using__(opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import Ecto.Schema, except: [schema: 2, field: 2, field: 3]
      import Events.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @schema_opts unquote(opts)

      # Register module attribute for field validations
      Module.register_attribute(__MODULE__, :field_validations, accumulate: true)
    end
  end

  @doc """
  Defines a schema with automatic field additions and enhanced validation support.

  This macro wraps Ecto.Schema's `schema/2` and automatically adds:
  - Type fields (type, subtype)
  - Metadata field (JSONB)
  - Audit fields (created_by_urm_id, updated_by_urm_id)
  - Timestamps (inserted_at, updated_at)
  - Enhanced field macro with validation metadata
  - Auto-generated changeset helper functions

  Fields can be disabled via module options (see module documentation).

  ## Auto-Generated Functions

  After the schema block, the following helper functions are automatically generated:

    * `__cast_fields__/0` - Returns list of fields with `cast: true`
    * `__required_fields__/0` - Returns list of fields with `required: true`
    * `__field_validations__/0` - Returns all field validation metadata
    * `__apply_field_validations__/1` - Applies all field validations to a changeset

  """
  defmacro schema(source, do: block) do
    quote do
      # Wrap in Ecto's schema, but first ensure only our field is imported
      Ecto.Schema.schema unquote(source) do
        import Ecto.Schema, except: [field: 2, field: 3]
        import Events.Schema, only: [field: 2, field: 3]

        # Add type fields unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :type_fields) do
          case Keyword.get(@schema_opts, :type_fields) do
            [only: :type] ->
              Ecto.Schema.field(:type, :string)

            [only: :subtype] ->
              Ecto.Schema.field(:subtype, :string)

            _ ->
              Ecto.Schema.field(:type, :string)
              Ecto.Schema.field(:subtype, :string)
          end
        end

        # Add metadata field unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :metadata) do
          Ecto.Schema.field(:metadata, :map, default: %{})
        end

        # User's custom fields
        unquote(block)

        # Add audit fields unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :audit_fields) do
          case Keyword.get(@schema_opts, :audit_fields) do
            [only: :created_by_urm_id] ->
              Ecto.Schema.field(:created_by_urm_id, :binary_id)

            [only: :updated_by_urm_id] ->
              Ecto.Schema.field(:updated_by_urm_id, :binary_id)

            _ ->
              Ecto.Schema.field(:created_by_urm_id, :binary_id)
              Ecto.Schema.field(:updated_by_urm_id, :binary_id)
          end
        end

        # Add timestamps unless disabled
        if Events.Schema.__should_add_field__(@schema_opts, :timestamps) do
          timestamps_opt = Keyword.get(@schema_opts, :timestamps, true)

          cond do
            timestamps_opt == false ->
              :ok

            is_list(timestamps_opt) ->
              merged =
                [type: :utc_datetime_usec]
                |> Keyword.merge(timestamps_opt)

              timestamps(merged)

            true ->
              timestamps(type: :utc_datetime_usec)
          end
        end
      end

      # Generate helper functions after schema definition
      Events.Schema.__generate_helpers__(__MODULE__)
    end
  end

  @doc """
  Enhanced field macro with validation support.

  This is imported to override Ecto.Schema.field/3.
  """
  defmacro field(name, type \\ :string, opts \\ []) do
    # We need to directly expand the field macro here
    quote bind_quoted: [name: name, type: type, opts: opts] do
      # Split validation options from Ecto options (with warnings)
      {validation_opts, ecto_opts} =
        Events.Schema.Field.__split_options__(opts, type, name)

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
  defmacro __generate_helpers__(_module) do
    quote do
      @doc """
      Returns list of fields that should be cast in changesets (cast: true).
      """
      def __cast_fields__ do
        @field_validations
        |> Enum.filter(fn {_name, _type, opts} ->
          Keyword.get(opts, :cast, true)
        end)
        |> Enum.map(fn {name, _type, _opts} -> name end)
      end

      @doc """
      Returns list of fields that are required (required: true).
      """
      def __required_fields__ do
        @field_validations
        |> Enum.filter(fn {_name, _type, opts} ->
          Keyword.get(opts, :required, false)
        end)
        |> Enum.map(fn {name, _type, _opts} -> name end)
      end

      @doc """
      Returns all field validation metadata.
      """
      def __field_validations__ do
        @field_validations
      end

      @doc """
      Applies all field validations to a changeset.

      This function is automatically generated and applies all validation rules
      defined in field options.

      ## Example

          def changeset(schema, attrs) do
            schema
            |> cast(attrs, __cast_fields__())
            |> validate_required(__required_fields__())
            |> __apply_field_validations__()
            |> custom_validations()
          end
      """
      def __apply_field_validations__(changeset) do
        @field_validations
        |> Enum.reduce(changeset, fn {field_name, field_type, opts}, acc ->
          Events.Schema.Validation.apply_field_validation(acc, field_name, field_type, opts)
        end)
      end
    end
  end

  @doc false
  def __should_add_field__(opts, field_name) do
    case Keyword.get(opts, field_name, true) do
      false -> false
      [only: _] -> true
      _ -> true
    end
  end
end
