defmodule Events.Core.Schema do
  @moduledoc """
  Events-specific schema wrapper over OmSchema.

  This module provides a thin wrapper that delegates to `OmSchema` with
  Events-specific defaults (UUIDv7 primary keys, field groups, etc.).

  ## Usage

      defmodule MyApp.Accounts.User do
        use Events.Core.Schema

        schema "users" do
          field :name, :string, required: true, min_length: 2
          field :email, :string, required: true, format: :email

          type_fields()
          status_fields(values: [:active, :inactive], default: :active)
          audit_fields()
          timestamps()
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs, __cast_fields__())
          |> validate_required(__required_fields__())
          |> __apply_field_validations__()
        end
      end

  ## Field Groups

  - `type_fields/0,1` - Adds :type and :subtype fields
  - `status_fields/1` - Adds :status enum field
  - `audit_fields/0,1` - Adds :created_by_urm_id and :updated_by_urm_id
  - `timestamps/0,1` - Adds :inserted_at and :updated_at
  - `metadata_field/0,1` - Adds :metadata map field
  - `soft_delete_field/0,1` - Adds :deleted_at field
  - `standard_fields/0,1,2` - Convenience for common field groups

  ## Enhanced Field Options

      field :email, :string,
        required: true,
        format: :email,
        max_length: 255,
        mappers: [:trim, :downcase]

  ## Presets

      field :email, :string, preset: email()
      field :username, :string, preset: username(min_length: 3)
      field :password, :string, preset: password()
      field :slug, :string, preset: slug()

  ## Submodules

  - `OmSchema.Presets` - Field presets (email, username, password, etc.)
  - `OmSchema.DatabaseValidator` - Database schema validation
  - `OmSchema.Help` - Interactive help

  See `OmSchema` for full documentation.
  """

  # Delegate everything to OmSchema
  defmacro __using__(_opts) do
    quote do
      use OmSchema
    end
  end

  # Database validation - delegate to OmSchema.DatabaseValidator
  defdelegate validate(schema_module, opts \\ []), to: OmSchema.DatabaseValidator
  defdelegate validate_all(opts \\ []), to: OmSchema.DatabaseValidator
  defdelegate validate_on_startup(), to: OmSchema.DatabaseValidator

  # Help
  defdelegate help(), to: OmSchema.Help, as: :show
  defdelegate help(topic), to: OmSchema.Help, as: :show
end
