defmodule Events.Schema do
  @moduledoc """
  Base schema module that provides enhanced Ecto schema functionality.

  This module wraps Ecto.Schema and provides:
  - UUIDv7 primary key (`id`)
  - Explicit field group macros (`type_fields`, `status_fields`, `audit_fields`, `timestamps`)
  - Enhanced field validation with automatic changeset generation

  ## Usage

  Instead of `use Ecto.Schema`, use `Events.Schema`:

      defmodule MyApp.Accounts.User do
        use Events.Schema

        schema "users" do
          field :name, :string, required: true, min_length: 2
          field :email, :string, required: true, format: :email
          field :age, :integer, positive: true, max: 150

          # Explicit field groups - configurable
          type_fields()
          status_fields(values: [:active, :suspended], default: :active)
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

  ## Field Group Macros

  All field groups are explicit and configurable:

      # Type fields - adds :type and :subtype
      type_fields()                              # Both fields
      type_fields(only: [:type])                 # Only :type
      type_fields(type: [required: true])        # With options

      # Status field - adds :status enum
      status_fields(values: [:active, :inactive], default: :active)
      status_fields(values: [:active, :inactive], required: true)

      # Audit fields - adds :created_by_urm_id and :updated_by_urm_id
      audit_fields()                             # Both fields
      audit_fields(only: [:created_by_urm_id])   # Only created_by

      # Timestamps - adds :inserted_at and :updated_at
      timestamps()                               # Both timestamps
      timestamps(only: [:updated_at])            # Only updated_at
      timestamps(only: [:inserted_at])           # Only inserted_at

      # Metadata field - adds :metadata map
      metadata_field()
      metadata_field(default: %{some: "default"})

  ## Enhanced Field Validation

  The `field` macro is enhanced with validation options:

      field :email, :string,
        required: true,            # default: false
        cast: true,               # default: true
        format: :email,
        max_length: 255,
        mappers: [:trim, :downcase]  # Applied left to right

  ## Behavioral Options

      # Immutable - can be set on creation but not modified afterwards
      field :account_id, :binary_id, required: true, immutable: true

      # Sensitive - auto-redacts in inspect/logs, excludes from JSON
      field :api_key, :string, sensitive: true

  ## Documentation Options

      field :email, :string,
        doc: "Primary contact email for the user",
        example: "user@example.com"

      # These are available via introspection:
      MySchema.field_docs()
      # => %{email: %{doc: "Primary contact...", example: "user@example.com"}}

  ## Mappers (Recommended for Transformations)

  Use `mappers:` to transform field values. Mappers are applied left to right:

      field :email, :string, mappers: [:trim, :downcase]
      field :name, :string, mappers: [:trim, :titlecase]
      field :username, :string, mappers: [:trim, :downcase, :slugify]

  Available mappers: `:trim`, `:downcase`, `:upcase`, `:capitalize`,
  `:titlecase`, `:squish`, `:slugify`, `:digits_only`, `:alphanumeric_only`

  ## Auto-Trim

  **All string fields are automatically trimmed by default!**

  To disable auto-trim (e.g., for passwords):

      field :password, :string, trim: false

      field :slug, :string,
        normalize: {:slugify, uniquify: true}  # Medium.com style slugs

      field :age, :integer,
        positive: true,           # > 0
        min: 18, max: 120        # simple syntax

      field :status, Ecto.Enum,
        values: [:active, :inactive],
        default: :active
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset, except: [constraints: 1]

      import Ecto.Schema,
        except: [
          schema: 2,
          field: 2,
          field: 3,
          timestamps: 0,
          timestamps: 1,
          belongs_to: 2,
          belongs_to: 3,
          has_many: 2,
          has_many: 3
        ]

      import Events.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      # Register module attribute for field validations
      Module.register_attribute(__MODULE__, :field_validations, accumulate: true)

      # Register constraint attributes
      Module.register_attribute(__MODULE__, :constraint_unique, accumulate: true)
      Module.register_attribute(__MODULE__, :constraint_foreign_key, accumulate: true)
      Module.register_attribute(__MODULE__, :constraint_check, accumulate: true)
      Module.register_attribute(__MODULE__, :constraint_index, accumulate: true)
      Module.register_attribute(__MODULE__, :constraint_exclude, accumulate: true)

      # Register has_many FK expectations
      Module.register_attribute(__MODULE__, :has_many_fk_expectations, accumulate: true)

      # Register belongs_to fields for FK constraint tracking
      Module.register_attribute(__MODULE__, :belongs_to_fields, accumulate: true)
    end
  end

  @doc """
  Defines a schema with enhanced validation support and explicit field group macros.

  This macro wraps Ecto.Schema's `schema/2` and provides:
  - Enhanced field macro with validation metadata
  - Explicit field group macros (type_fields, status_fields, audit_fields, timestamps)
  - Auto-generated changeset helper functions

  ## Auto-Generated Functions

  After the schema block, the following helper functions are automatically generated:

    * `__cast_fields__/0` - Returns list of fields with `cast: true`
    * `__required_fields__/0` - Returns list of fields with `required: true`
    * `__field_validations__/0` - Returns all field validation metadata
    * `__apply_field_validations__/1` - Applies all field validations to a changeset

  """
  defmacro schema(source, do: block) do
    quote do
      # Store table name for constraint generation
      @__schema_table_name__ unquote(source)

      # Wrap in Ecto's schema with our enhanced macros
      Ecto.Schema.schema unquote(source) do
        import Ecto.Schema,
          except: [
            field: 2,
            field: 3,
            timestamps: 0,
            timestamps: 1,
            belongs_to: 2,
            belongs_to: 3,
            has_many: 2,
            has_many: 3
          ]

        import Events.Schema,
          only: [
            field: 2,
            field: 3,
            belongs_to: 2,
            belongs_to: 3,
            has_many: 2,
            has_many: 3,
            type_fields: 0,
            type_fields: 1,
            status_fields: 1,
            audit_fields: 0,
            audit_fields: 1,
            timestamps: 0,
            timestamps: 1,
            metadata_field: 0,
            metadata_field: 1,
            assets_field: 0,
            assets_field: 1,
            soft_delete_field: 0,
            soft_delete_field: 1,
            standard_fields: 0,
            standard_fields: 1,
            standard_fields: 2,
            constraints: 1
          ]

        # User's custom fields and explicit field group macros
        unquote(block)
      end

      # Generate helper functions after schema definition
      Events.Schema.__generate_helpers__(__MODULE__)
    end
  end

  @doc """
  Enhanced field macro with validation support.

  This is imported to override Ecto.Schema.field/3.

  ## Examples

      # Explicit preset
      field :email, :string, preset: email()
      field :username, :string, preset: username(min_length: 3)

      # Direct options
      field :age, :integer, required: true, min: 18, max: 120

      # Mixed (preset options can be overridden)
      field :email, :string, preset: email(), max_length: 100
  """
  defmacro field(name, type \\ :string, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      opts = Events.Schema.merge_preset_opts(opts)
      {validation_opts, ecto_opts} = Events.Schema.Field.__split_options__(opts, type, name)
      validation_opts = Events.Schema.normalize_validation_opts(validation_opts)

      Module.put_attribute(__MODULE__, :field_validations, {name, type, validation_opts})
      Ecto.Schema.__field__(__MODULE__, name, type, ecto_opts)
    end
  end

  # =============================================================================
  # Association Macros with Constraint Support
  # =============================================================================

  @doc """
  Enhanced belongs_to that captures foreign key constraint metadata.

  In addition to standard Ecto belongs_to options, supports:

    * `:constraint` - FK constraint options (list or false to skip)
      * `:name` - Custom constraint name (default: `{table}_{field}_fkey`)
      * `:on_delete` - `:nothing`, `:cascade`, `:restrict`, `:nilify_all`, `:delete_all`
      * `:on_update` - Same options as on_delete
      * `:deferrable` - `:initially_immediate` or `:initially_deferred`
    * `:on_delete` - Shorthand for `constraint: [on_delete: value]`

  ## Examples

      # Basic - default FK constraint (on_delete: :nothing)
      belongs_to :account, Account

      # With cascade delete
      belongs_to :account, Account, on_delete: :cascade

      # Full constraint options
      belongs_to :account, Account,
        constraint: [
          on_delete: :cascade,
          deferrable: :initially_deferred
        ]

      # Skip FK validation (for polymorphic associations)
      belongs_to :commentable, Commentable, constraint: false
  """
  defmacro belongs_to(name, queryable, opts \\ []) do
    quote bind_quoted: [name: name, queryable: queryable, opts: opts] do
      # Extract constraint options
      {constraint_opt, ecto_opts} = Keyword.pop(opts, :constraint)
      {on_delete_opt, ecto_opts} = Keyword.pop(ecto_opts, :on_delete)

      # Build constraint config
      constraint_config =
        cond do
          constraint_opt == false ->
            false

          is_list(constraint_opt) ->
            # Merge on_delete shorthand if both provided
            if on_delete_opt && !Keyword.has_key?(constraint_opt, :on_delete) do
              Keyword.put(constraint_opt, :on_delete, on_delete_opt)
            else
              constraint_opt
            end

          on_delete_opt ->
            [on_delete: on_delete_opt]

          true ->
            nil
        end

      # Store constraint config for later processing
      fk_field = Keyword.get(ecto_opts, :foreign_key, :"#{name}_id")
      Module.put_attribute(__MODULE__, :"#{name}_constraint", constraint_config)

      Module.put_attribute(
        __MODULE__,
        :belongs_to_fields,
        {name, fk_field, queryable, constraint_config}
      )

      # Call Ecto's belongs_to
      Ecto.Schema.__belongs_to__(__MODULE__, name, queryable, ecto_opts)
    end
  end

  @doc """
  Enhanced has_many that tracks FK validation expectations.

  In addition to standard Ecto has_many options, supports:

    * `:expect_on_delete` - Expected on_delete behavior of the FK on the related table
    * `:validate_fk` - Set to `false` to skip FK validation (default: true)

  By default, has_many associations are validated to ensure the related table
  has a corresponding FK constraint pointing back to this table.

  ## Examples

      # Basic - validates FK exists on memberships table
      has_many :memberships, Membership

      # Expect specific on_delete behavior
      has_many :memberships, Membership, expect_on_delete: :cascade

      # Skip FK validation (through associations, polymorphic)
      has_many :accounts, through: [:memberships, :account]
      has_many :comments, Comment, validate_fk: false
  """
  defmacro has_many(name, queryable, opts \\ []) do
    quote bind_quoted: [name: name, queryable: queryable, opts: opts] do
      # Extract FK expectation options
      {expect_on_delete, ecto_opts} = Keyword.pop(opts, :expect_on_delete)
      {validate_fk, ecto_opts} = Keyword.pop(ecto_opts, :validate_fk, true)

      # Don't validate through associations
      # Through associations can be specified as:
      #   has_many :foo, through: [:bar, :baz]   (queryable is keyword list)
      #   has_many :foo, Bar, through: [...]     (through in opts - rare)
      is_through =
        Keyword.has_key?(ecto_opts, :through) ||
          (is_list(queryable) && Keyword.has_key?(queryable, :through))

      if validate_fk && !is_through && is_atom(queryable) do
        fk_expectation = %{
          assoc_name: name,
          related: queryable,
          expect_on_delete: expect_on_delete
        }

        Module.put_attribute(__MODULE__, :has_many_fk_expectations, fk_expectation)
      end

      # Call Ecto's has_many
      Ecto.Schema.__has_many__(__MODULE__, name, queryable, ecto_opts)
    end
  end

  @doc """
  Wrapper macro for the constraints block.

  Delegates to `Events.Schema.Constraints.constraints/1`.

  ## Example

      schema "users" do
        field :email, :string
        belongs_to :account, Account

        constraints do
          unique [:account_id, :email], name: :users_account_email_idx
          check :valid_email, expr: "email LIKE '%@%'"
        end
      end
  """
  defmacro constraints(do: block) do
    quote do
      import Events.Schema.Constraints,
        only: [unique: 2, foreign_key: 2, check: 1, check: 2, index: 1, index: 2, exclude: 2]

      unquote(block)
    end
  end

  # =============================================================================
  # Field Group Macros
  # =============================================================================

  @doc """
  Adds type classification fields to the schema.

  ## Options

    * `:only` - List of fields to include (default: `[:type, :subtype]`)
    * `:type` - Options for the :type field (passed to field macro)
    * `:subtype` - Options for the :subtype field (passed to field macro)

  ## Examples

      # Add both type and subtype fields
      type_fields()

      # Only add type field
      type_fields(only: [:type])

      # Add type with required validation
      type_fields(type: [required: true])

      # Add both with custom options
      type_fields(type: [required: true], subtype: [cast: false])
  """
  defmacro type_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      only = Keyword.get(opts, :only, [:type, :subtype])

      for field <- [:type, :subtype], field in only do
        field_opts = Keyword.get(opts, field, [])
        Events.Schema.__define_field__(__MODULE__, field, :string, field_opts)
      end
    end
  end

  @doc """
  Adds a status enum field to the schema.

  ## Required Options

    * `:values` - List of enum values (required)

  ## Optional Options

    * `:default` - Default value for the status field
    * `:required` - Whether the field is required (default: false)
    * `:cast` - Whether to cast the field (default: true)
    * Any other field validation options

  ## Examples

      # Basic status field
      status_fields(values: [:active, :inactive], default: :active)

      # Required status field
      status_fields(values: [:active, :suspended, :deleted], default: :active, required: true)

      # Status field that won't be cast (set programmatically)
      status_fields(values: [:pending, :approved], default: :pending, cast: false)
  """
  defmacro status_fields(opts) do
    quote bind_quoted: [opts: opts] do
      values = Keyword.fetch!(opts, :values)
      {default, rest_opts} = Keyword.pop(opts, :default)
      validation_opts = Keyword.drop(rest_opts, [:values])

      ecto_opts =
        [values: values]
        |> Events.Schema.maybe_put(:default, default)

      field_opts = Keyword.merge(ecto_opts, validation_opts)
      Events.Schema.__define_enum_field__(__MODULE__, :status, values, field_opts)
    end
  end

  @doc """
  Adds audit tracking fields to the schema.

  Audit fields track which user role mapping (URM) created or updated a record.

  ## Options

    * `:only` - List of fields to include (default: `[:created_by_urm_id, :updated_by_urm_id]`)
    * `:created_by_urm_id` - Options for the created_by field
    * `:updated_by_urm_id` - Options for the updated_by field

  ## Examples

      # Add both audit fields
      audit_fields()

      # Only track creation
      audit_fields(only: [:created_by_urm_id])

      # With custom options
      audit_fields(created_by_urm_id: [required: true])
  """
  defmacro audit_fields(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      only = Keyword.get(opts, :only, [:created_by_urm_id, :updated_by_urm_id])

      for field <- [:created_by_urm_id, :updated_by_urm_id], field in only do
        field_opts = Keyword.get(opts, field, [])
        Events.Schema.__define_field__(__MODULE__, field, :binary_id, field_opts)
      end
    end
  end

  @doc """
  Adds timestamp fields to the schema.

  ## Options

    * `:only` - List of timestamps to include (default: `[:inserted_at, :updated_at]`)
    * `:type` - Timestamp type (default: `:utc_datetime_usec`)

  ## Examples

      # Add both timestamps
      timestamps()

      # Only updated_at
      timestamps(only: [:updated_at])

      # Only inserted_at
      timestamps(only: [:inserted_at])

      # With custom type
      timestamps(type: :naive_datetime)
  """
  defmacro timestamps(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      only = Keyword.get(opts, :only, [:inserted_at, :updated_at])
      type = Keyword.get(opts, :type, :utc_datetime_usec)

      ecto_opts = [type: type]

      cond do
        only == [:inserted_at] ->
          Ecto.Schema.timestamps(Keyword.put(ecto_opts, :updated_at, false))

        only == [:updated_at] ->
          Ecto.Schema.timestamps(Keyword.put(ecto_opts, :inserted_at, false))

        true ->
          Ecto.Schema.timestamps(ecto_opts)
      end
    end
  end

  @doc """
  Adds a metadata JSONB field to the schema.

  ## Options

    * `:default` - Default value (default: `%{}`)
    * Any other field validation options

  ## Examples

      # Basic metadata field
      metadata_field()

      # With custom default
      metadata_field(default: %{version: 1})
  """
  defmacro metadata_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      default = Keyword.get(opts, :default, %{})
      field_opts = Keyword.put(opts, :default, default)
      Events.Schema.__define_field__(__MODULE__, :metadata, :map, field_opts)
    end
  end

  @doc """
  Adds assets JSONB field to the schema.

  Assets store images, files, and other media references.

  ## Examples

      assets_field()
      assets_field(default: %{logo: nil})
  """
  defmacro assets_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      default = Keyword.get(opts, :default, %{})
      field_opts = Keyword.put(opts, :default, default)
      Events.Schema.__define_field__(__MODULE__, :assets, :map, field_opts)
    end
  end

  @doc """
  Adds soft delete fields to the schema.

  Soft delete allows marking records as deleted without physically removing them
  from the database. This is useful for audit trails, recovery, and data integrity.

  ## Fields Added

    * `:deleted_at` - Timestamp when the record was soft deleted (nil if not deleted)
    * `:deleted_by_urm_id` - Optional: who deleted it (only if `track_urm: true`)

  ## Options

    * `:track_urm` - Add `deleted_by_urm_id` field (default: `false`)
    * `:deleted_at` - Options for the deleted_at field
    * `:deleted_by_urm_id` - Options for the deleted_by_urm_id field

  ## Examples

      # Basic soft delete
      soft_delete_field()

      # With deletion tracking
      soft_delete_field(track_urm: true)

  ## Generated Helpers

  When you use `soft_delete_field()`, the following helpers are available:

      # Check if record is deleted
      User.deleted?(user)  # => true/false

      # Soft delete a record
      user
      |> User.soft_delete_changeset()
      |> Repo.update()

      # With who deleted it
      user
      |> User.soft_delete_changeset(deleted_by_urm_id: urm_id)
      |> Repo.update()

      # Restore a soft-deleted record
      user
      |> User.restore_changeset()
      |> Repo.update()

      # Query helpers
      User.not_deleted(query)    # Exclude deleted records
      User.only_deleted(query)   # Only deleted records
      User.with_deleted(query)   # All records (no filter)
  """
  defmacro soft_delete_field(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      # Handle deprecated option name
      opts =
        if Keyword.has_key?(opts, :track_deleted_by) do
          IO.warn(
            "track_deleted_by is deprecated, use track_urm instead",
            Macro.Env.stacktrace(__ENV__)
          )

          Keyword.put(opts, :track_urm, Keyword.get(opts, :track_deleted_by))
        else
          opts
        end

      track_urm = Keyword.get(opts, :track_urm, false)

      # Add deleted_at field
      deleted_at_opts = Keyword.get(opts, :deleted_at, [])
      Events.Schema.__define_field__(__MODULE__, :deleted_at, :utc_datetime_usec, deleted_at_opts)

      # Optionally add deleted_by_urm_id
      if track_urm do
        deleted_by_opts = Keyword.get(opts, :deleted_by_urm_id, [])
        Events.Schema.__define_field__(__MODULE__, :deleted_by_urm_id, :binary_id, deleted_by_opts)
      end

      # Store soft delete config for helper generation
      Module.put_attribute(__MODULE__, :soft_delete_enabled, true)
      Module.put_attribute(__MODULE__, :soft_delete_track_by, track_urm)
    end
  end

  @doc """
  Unified macro to add multiple standard field groups at once.

  This provides a clean, declarative way to specify which standard fields
  a schema should have.

  ## Usage

      # Add all standard fields with defaults
      standard_fields()

      # Select specific fields
      standard_fields([:type, :status, :timestamps])

      # With options for specific groups
      standard_fields([:type, :status, :metadata, :audit, :timestamps],
        status: [values: [:active, :inactive], default: :active]
      )

      # Exclude specific fields
      standard_fields(except: [:audit])

  ## Available Field Groups

    * `:type` - Adds type and subtype fields
    * `:status` - Adds status enum (requires `status: [values: [...]]`)
    * `:metadata` - Adds metadata JSONB field
    * `:assets` - Adds assets JSONB field
    * `:audit` - Adds created_by_urm_id and updated_by_urm_id
    * `:timestamps` - Adds inserted_at and updated_at

  ## Examples

      # Typical entity
      standard_fields(
        status: [values: [:active, :archived], default: :active]
      )

      # Foundation entity (no audit fields)
      standard_fields([:type, :status, :metadata, :timestamps],
        status: [values: [:active, :suspended], default: :active]
      )

      # Minimal (just timestamps)
      standard_fields([:timestamps])
  """
  defmacro standard_fields(groups_or_opts \\ [], opts \\ [])

  defmacro standard_fields(groups, opts) when is_list(groups) and is_list(opts) do
    quote bind_quoted: [groups: groups, opts: opts] do
      {except, opts} = Keyword.pop(opts, :except, [])
      all_groups = [:type, :status, :metadata, :assets, :audit, :timestamps]

      groups = Events.Schema.resolve_groups(groups, except, all_groups)

      for group <- groups do
        group_opts = Keyword.get(opts, group, [])
        Events.Schema.apply_field_group(__MODULE__, group, group_opts)
      end
    end
  end

  # Handle case where only opts are provided
  defmacro standard_fields(opts, []) when is_list(opts) and opts != [] do
    quote do
      Events.Schema.standard_fields([], unquote(opts))
    end
  end

  # =============================================================================
  # Option Helpers
  # =============================================================================

  @doc false
  def merge_preset_opts(opts) do
    case Keyword.pop(opts, :preset) do
      {nil, opts} -> opts
      {preset_opts, opts} -> Keyword.merge(preset_opts, opts)
    end
  end

  @doc false
  def normalize_validation_opts(opts) do
    opts
    |> Keyword.put_new(:cast, true)
    |> Keyword.put_new(:required, false)
    |> put_null_default()
  end

  defp put_null_default(opts) do
    case Keyword.has_key?(opts, :null) do
      true -> opts
      false -> Keyword.put(opts, :null, !Keyword.get(opts, :required, false))
    end
  end

  @doc false
  def maybe_put(keyword, _key, nil), do: keyword
  def maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  @doc false
  def resolve_groups([], except, all_groups) when except != [], do: all_groups -- except
  def resolve_groups([], _except, all_groups), do: all_groups
  def resolve_groups(groups, except, _all_groups), do: groups -- except

  @doc false
  def apply_field_group(module, :type, opts), do: __define_type_fields__(module, opts)
  def apply_field_group(module, :status, opts), do: __define_status_fields__(module, opts)

  def apply_field_group(module, :metadata, opts),
    do: __define_field__(module, :metadata, :map, Keyword.put_new(opts, :default, %{}))

  def apply_field_group(module, :assets, opts),
    do: __define_field__(module, :assets, :map, Keyword.put_new(opts, :default, %{}))

  def apply_field_group(module, :audit, opts), do: __define_audit_fields__(module, opts)
  def apply_field_group(module, :timestamps, opts), do: __define_timestamps__(module, opts)

  defp __define_type_fields__(module, opts) do
    only = Keyword.get(opts, :only, [:type, :subtype])

    for field <- [:type, :subtype], field in only do
      field_opts = Keyword.get(opts, field, [])
      __define_field__(module, field, :string, field_opts)
    end
  end

  defp __define_status_fields__(module, opts) do
    case Keyword.get(opts, :values) do
      nil ->
        :ok

      values ->
        {default, rest_opts} = Keyword.pop(opts, :default)
        validation_opts = Keyword.drop(rest_opts, [:values])

        ecto_opts =
          [values: values]
          |> maybe_put(:default, default)

        field_opts = Keyword.merge(ecto_opts, validation_opts)
        __define_enum_field__(module, :status, values, field_opts)
    end
  end

  defp __define_audit_fields__(module, opts) do
    only = Keyword.get(opts, :only, [:created_by_urm_id, :updated_by_urm_id])

    for field <- [:created_by_urm_id, :updated_by_urm_id], field in only do
      field_opts = Keyword.get(opts, field, [])
      __define_field__(module, field, :binary_id, field_opts)
    end
  end

  defp __define_timestamps__(module, opts) do
    type = Keyword.get(opts, :type, :utc_datetime_usec)
    only = Keyword.get(opts, :only, [:inserted_at, :updated_at])

    for field <- [:inserted_at, :updated_at], field in only do
      # Timestamps need autogenerate: {Ecto.Schema, :__timestamps__, [type]}
      field_opts = [
        cast: false,
        autogenerate: {Ecto.Schema, :__timestamps__, [type]}
      ]

      Module.put_attribute(module, :ecto_autogenerate, {[field], field_opts[:autogenerate]})

      __define_field__(module, field, type, field_opts)
    end
  end

  # =============================================================================
  # Deletion Impact Preview
  # =============================================================================

  @doc """
  Returns a preview of what will be affected by deleting a record.

  Useful for:
  - Showing users what will be deleted/orphaned
  - Audit logging before deletion
  - Deciding whether to proceed with deletion

  ## Examples

      # Basic - immediate associations only (depth: 1)
      Events.Schema.deletion_impact(account)
      # %{memberships: 5, roles: 3}

      # With depth - traverse association chain
      Events.Schema.deletion_impact(account, depth: 2)
      # %{
      #   memberships: 5,
      #   roles: 3,
      #   "roles.user_role_mappings": 12
      # }

      # In your schema module, you can add a wrapper:
      def deletion_impact(record, opts \\\\ []) do
        Events.Schema.deletion_impact(record, opts)
      end

  ## Options

    * `:depth` - How deep to traverse associations (default: 1)
    * `:repo` - Ecto repo to use (default: Events.Repo)

  ## Notes

  - Only counts has_many and has_one associations (not belongs_to)
  - Each level of depth adds DB queries, use judiciously
  - Returns flat map with dotted keys for nested associations
  """
  def deletion_impact(record, opts \\ []) do
    depth = Keyword.get(opts, :depth, 1)
    repo = Keyword.get(opts, :repo, Events.Repo)
    schema = record.__struct__

    count_associations(schema, record, repo, depth, [])
    |> Map.new()
  end

  defp count_associations(_schema, _record, _repo, 0, _path), do: []

  defp count_associations(schema, record, repo, depth, path) do
    schema.__schema__(:associations)
    |> Enum.flat_map(&count_association(schema, record, repo, depth, path, &1))
  end

  defp count_association(schema, record, repo, depth, path, assoc_name) do
    case schema.__schema__(:association, assoc_name) do
      %{cardinality: cardinality, related: related_schema, relationship: :child}
      when cardinality in [:many, :one] ->
        assoc_query = Ecto.assoc(record, assoc_name)
        count = repo.aggregate(assoc_query, :count)
        current_path = path ++ [assoc_name]

        build_impact_entries(count, current_path, related_schema, assoc_query, repo, depth)

      _other ->
        []
    end
  end

  defp build_impact_entries(0, _path, _schema, _query, _repo, _depth), do: []

  defp build_impact_entries(count, path, related_schema, assoc_query, repo, depth) do
    key = path |> Enum.map(&to_string/1) |> Enum.join(".")
    children = maybe_traverse_children(related_schema, assoc_query, repo, depth, path)

    [{key, count} | children]
  end

  defp maybe_traverse_children(_schema, _query, _repo, depth, _path) when depth <= 1, do: []

  defp maybe_traverse_children(related_schema, assoc_query, repo, depth, path) do
    import Ecto.Query, only: [limit: 2]

    case repo.one(limit(assoc_query, 1)) do
      nil -> []
      sample -> count_associations(related_schema, sample, repo, depth - 1, path)
    end
  end

  @doc """
  Formats deletion impact as a human-readable string.

  ## Examples

      impact = Events.Schema.deletion_impact(account, depth: 2)
      Events.Schema.format_deletion_impact(impact)
      # "5 memberships, 3 roles, 12 roles.user_role_mappings"
  """
  def format_deletion_impact(impact) when map_size(impact) == 0, do: "no associated records"

  def format_deletion_impact(impact) do
    impact
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map(fn {key, count} -> "#{count} #{key}" end)
    |> Enum.join(", ")
  end

  # =============================================================================
  # Internal Helpers
  # =============================================================================

  @doc false
  def __define_field__(module, name, type, opts) do
    {validation_opts, ecto_opts} = Events.Schema.Field.__split_options__(opts, type, name)
    validation_opts = normalize_validation_opts(validation_opts)

    Module.put_attribute(module, :field_validations, {name, type, validation_opts})
    Ecto.Schema.__field__(module, name, type, ecto_opts)
  end

  @doc false
  def __define_enum_field__(module, name, values, opts) do
    {validation_opts, ecto_opts} = Events.Schema.Field.__split_options__(opts, Ecto.Enum, name)
    validation_opts = normalize_validation_opts(validation_opts)
    ecto_opts = Keyword.put(ecto_opts, :values, values)

    Module.put_attribute(module, :field_validations, {name, Ecto.Enum, validation_opts})
    Ecto.Schema.__field__(module, name, Ecto.Enum, ecto_opts)
  end

  @doc false
  defmacro __generate_helpers__(_module) do
    quote do
      # =====================================================================
      # Field Introspection (compile-time computed)
      # =====================================================================

      @cast_fields_computed for(
                              {name, _type, opts} <- @field_validations,
                              Keyword.get(opts, :cast, true),
                              do: name
                            )
      @required_fields_computed for(
                                  {name, _type, opts} <- @field_validations,
                                  Keyword.get(opts, :required, false),
                                  do: name
                                )
      @immutable_fields_computed for(
                                   {name, _type, opts} <- @field_validations,
                                   Keyword.get(opts, :immutable, false),
                                   do: name
                                 )
      @sensitive_fields_computed for(
                                   {name, _type, opts} <- @field_validations,
                                   Keyword.get(opts, :sensitive, false),
                                   do: name
                                 )

      @field_docs_computed @field_validations
                           |> Enum.filter(fn {_name, _type, opts} ->
                             Keyword.has_key?(opts, :doc) || Keyword.has_key?(opts, :example)
                           end)
                           |> Map.new(fn {name, _type, opts} ->
                             {name,
                              %{doc: Keyword.get(opts, :doc), example: Keyword.get(opts, :example)}}
                           end)

      @conditional_required_computed for(
                                       {name, _type, opts} <- @field_validations,
                                       condition = Keyword.get(opts, :required_when),
                                       do: {name, condition}
                                     )

      @doc "Returns fields with `cast: true` (default for most fields)."
      def cast_fields, do: @cast_fields_computed

      @doc "Returns fields with `required: true`."
      def required_fields, do: @required_fields_computed

      @doc "Returns fields with `immutable: true`."
      def immutable_fields, do: @immutable_fields_computed

      @doc "Returns fields with `sensitive: true`."
      def sensitive_fields, do: @sensitive_fields_computed

      @doc """
      Returns field documentation as a map of field -> %{doc: string, example: term}.

      Only includes fields that have `doc:` or `example:` defined.
      """
      def field_docs, do: @field_docs_computed

      @doc """
      Returns fields with `required_when` conditions.

      Returns a list of `{field_name, condition}` tuples.
      """
      def conditional_required_fields, do: @conditional_required_computed

      @doc "Returns all field validation metadata."
      def field_validations, do: @field_validations

      # =====================================================================
      # Action-Specific Changeset Options
      # =====================================================================

      # If @changeset_actions not defined, default to empty map
      unless Module.has_attribute?(__MODULE__, :changeset_actions) do
        @changeset_actions %{}
      end

      # =====================================================================
      # Changeset Helpers
      # =====================================================================

      @doc """
      Applies all field validations (format, mappers, length, etc.) to a changeset.
      """
      def apply_validations(changeset) do
        @field_validations
        |> Enum.reduce(changeset, fn {field_name, field_type, opts}, acc ->
          Events.Schema.Validation.apply_field_validation(acc, field_name, field_type, opts)
        end)
      end

      # =====================================================================
      # Base Changeset
      # =====================================================================

      @doc """
      Creates a changeset with field definitions applied.

      Applies:
      - Casts fields with `cast: true`
      - Validates required fields with `required: true`
      - Applies field validations (format, mappers, length, etc.)

      ## Action-Specific Options

      Define `@changeset_actions` to configure per-action behavior:

          @changeset_actions %{
            create: [also_required: [:password]],
            update: [skip_required: [:password], skip_cast: [:email]],
            profile: [only_cast: [:name, :avatar], only_required: []]
          }

          def changeset(user, attrs, action \\\\ :default) do
            base_changeset(user, attrs, action: action)
          end

      ## Examples

          # Default: uses field definitions as-is
          base_changeset(struct, attrs)

          # With action (looks up @changeset_actions)
          base_changeset(struct, attrs, action: :create)

          # Action + additional options (merged)
          base_changeset(struct, attrs, action: :create, validate: false)

          # Direct options (no action lookup)
          base_changeset(struct, attrs, also_cast: [:account_id])

      ## Options

        * `action: atom` - Look up options from `@changeset_actions[action]`
        * `also_cast: [fields]` - Add extra fields to cast
        * `only_cast: [fields]` - Override: only cast these fields
        * `skip_cast: [fields]` - Exclude fields from cast
        * `also_required: [fields]` - Add extra required fields
        * `only_required: [fields]` - Override: only these are required
        * `skip_required: [fields]` - Exclude from required
        * `skip_field_validations: true` - Skip field validations (format, mappers, length)
        * `check_immutable: true` - Validate immutable fields on updates (default: false)
        * `check_conditional_required: true` - Validate conditional required fields (default: false)
      """
      def base_changeset(struct, attrs, opts \\ [])

      def base_changeset(struct, attrs, opts) do
        opts = resolve_action_opts(opts)
        cast_list = resolve_fields(cast_fields(), opts, :cast)
        required_list = resolve_fields(required_fields(), opts, :required)

        struct
        |> cast(attrs, cast_list)
        |> validate_required(required_list)
        |> maybe_apply_field_validations(Keyword.get(opts, :skip_field_validations, false))
        |> maybe_check_immutable(Keyword.get(opts, :check_immutable, false))
        |> maybe_check_conditional_required(Keyword.get(opts, :check_conditional_required, false))
      end

      defp resolve_action_opts(opts) do
        case Keyword.pop(opts, :action) do
          {nil, opts} ->
            opts

          {action, opts} ->
            action_opts = @changeset_actions[action] || @changeset_actions[:default] || []
            Keyword.merge(action_opts, opts)
        end
      end

      defp maybe_apply_field_validations(changeset, true), do: changeset
      defp maybe_apply_field_validations(changeset, false), do: apply_validations(changeset)

      defp maybe_check_immutable(changeset, false), do: changeset
      defp maybe_check_immutable(changeset, true), do: validate_immutable(changeset)

      defp maybe_check_conditional_required(changeset, false), do: changeset

      defp maybe_check_conditional_required(changeset, true),
        do: validate_conditional_required(changeset)

      defp resolve_fields(defaults, opts, kind) do
        only_key = :"only_#{kind}"
        skip_key = :"skip_#{kind}"
        also_key = :"also_#{kind}"

        cond do
          fields = Keyword.get(opts, only_key) -> fields
          skip = Keyword.get(opts, skip_key) -> defaults -- skip
          extra = Keyword.get(opts, also_key) -> Enum.uniq(defaults ++ extra)
          true -> defaults
        end
      end

      # =====================================================================
      # Constraint Helpers
      # =====================================================================

      @doc """
      Applies multiple unique constraints to a changeset.

      ## Examples

          |> unique_constraints([
               {:email, []},
               {:username, message: "is taken"},
               {[:account_id, :slug], name: :users_account_slug_index, message: "slug exists"}
             ])

      ## Format

      Always use tuple format: `{field_or_fields, opts}`

        * `{:field, []}` - single field, no options
        * `{:field, message: "..."}` - single field with options
        * `{[:field1, :field2], []}` - composite, no options
        * `{[:field1, :field2], name: :idx}` - composite with options

      ## Supported options

        * `:name` - constraint name in database
        * `:message` - custom error message
        * `:error_key` - field to attach error to (for composite)
      """
      def unique_constraints(changeset, constraints) when is_list(constraints) do
        Enum.reduce(constraints, changeset, fn
          {field, opts}, acc when is_atom(field) and is_list(opts) ->
            unique_constraint(acc, field, opts)

          {fields, opts}, acc when is_list(fields) and is_list(opts) ->
            unique_constraint(acc, fields, opts)
        end)
      end

      @doc """
      Applies multiple foreign key constraints to a changeset.

      ## Examples

          |> foreign_key_constraints([
               {:account_id, []},
               {:user_id, message: "user not found"},
               {:role_id, name: :custom_fk_name, message: "invalid role"}
             ])

      ## Format

      Always use tuple format: `{field, opts}`

        * `{:field, []}` - no options
        * `{:field, message: "..."}` - with options

      ## Supported options

        * `:name` - constraint name in database
        * `:message` - custom error message
      """
      def foreign_key_constraints(changeset, constraints) when is_list(constraints) do
        Enum.reduce(constraints, changeset, fn
          {field, opts}, acc when is_atom(field) and is_list(opts) ->
            foreign_key_constraint(acc, field, opts)
        end)
      end

      @doc """
      Applies multiple check constraints to a changeset.

      ## Examples

          |> check_constraints([
               {:age, name: :users_age_positive, message: "must be positive"},
               {:balance, name: :accounts_balance_non_negative}
             ])

      ## Format

      Always use tuple format: `{field, opts}`

        * `{:field, name: :constraint_name}` - name is required for check constraints

      ## Supported options

        * `:name` - constraint name in database (required)
        * `:message` - custom error message
      """
      def check_constraints(changeset, constraints) when is_list(constraints) do
        Enum.reduce(constraints, changeset, fn
          {field, opts}, acc when is_atom(field) and is_list(opts) ->
            check_constraint(acc, field, opts)
        end)
      end

      @doc """
      Applies multiple no_assoc constraints to a changeset.

      Prevents deletion when associated records exist.

      ## Examples

          def delete_changeset(account) do
            account
            |> change()
            |> no_assoc_constraints([
                 {:memberships, []},
                 {:roles, message: "has associated roles"}
               ])
          end

      ## Format

      Always use tuple format: `{assoc, opts}`

        * `{:assoc, []}` - no options
        * `{:assoc, message: "..."}` - with custom message

      ## Supported options

        * `:name` - constraint name in database
        * `:message` - custom error message
      """
      def no_assoc_constraints(changeset, constraints) when is_list(constraints) do
        Enum.reduce(constraints, changeset, fn
          {assoc, opts}, acc when is_atom(assoc) and is_list(opts) ->
            no_assoc_constraint(acc, assoc, opts)
        end)
      end

      # =====================================================================
      # Immutable Field Validation
      # =====================================================================

      @doc """
      Validates that immutable fields have not been changed on an existing record.

      Immutable fields can be set during creation but cannot be modified afterwards.
      This validation only applies to updates (when the record has an existing id).

      ## Examples

          def changeset(record, attrs) do
            record
            |> base_changeset(attrs)
            |> validate_immutable()
          end

          # Or specify fields explicitly
          |> validate_immutable([:account_id, :created_at])

          # With custom message
          |> validate_immutable(message: "cannot be changed after creation")

      ## Options

        * `:fields` - List of fields to check (default: `immutable_fields()`)
        * `:message` - Custom error message (default: "cannot be changed")
      """
      def validate_immutable(changeset, opts \\ [])

      def validate_immutable(changeset, fields) when is_list(fields) and is_atom(hd(fields)) do
        validate_immutable(changeset, fields: fields)
      end

      def validate_immutable(changeset, opts) do
        # Only validate on updates (existing records)
        if is_nil(changeset.data.id) do
          changeset
        else
          fields = Keyword.get(opts, :fields, immutable_fields())
          message = Keyword.get(opts, :message, "cannot be changed")

          Enum.reduce(fields, changeset, fn field, acc ->
            if get_change(acc, field) != nil do
              add_error(acc, field, message)
            else
              acc
            end
          end)
        end
      end

      # =====================================================================
      # Conditional Required Validation
      # =====================================================================

      @doc """
      Validates fields that are conditionally required based on other field values.

      Uses the `required_when` field option to determine when fields are required.

      ## DSL Syntax

      ### Simple equality (keyword list, implicit AND)

          field :phone, :string, required_when: [contact_method: :phone]
          field :address, :map, required_when: [type: :physical, needs_shipping: true]

      ### Comparison operators {field, operator, value}

          field :reason, :string, required_when: {:discount_percent, :gt, 0}
          field :notes, :string, required_when: {:status, :in, [:rejected, :on_hold]}

      ### Unary operators {field, operator}

          field :company, :string, required_when: {:is_business, :truthy}
          field :backup, :string, required_when: {:primary, :blank}

      ### Boolean combinators with :and / :or

          field :phone, :string, required_when: [[notify_sms: true], :or, [notify_call: true]]
          field :address, :map, required_when: [[type: :physical], :and, {:needs_shipping, :truthy}]

      ### Chaining (same operator only)

          field :approval, :binary_id, required_when: [
            [status: :pending], :and, {:amount, :gte, 10000}, :and, [category: :expense]
          ]

      ### Nested grouping (lists as parentheses)

          field :customs, :map, required_when: [
            [[status: :active], :and, {:amount, :gt, 100}],
            :or,
            [[type: :vip], :and, {:priority, :gte, 5}]
          ]

      ### Negation

          field :reason, :string, required_when: {:not, [status: :approved]}

      ## Examples

          def changeset(record, attrs) do
            record
            |> base_changeset(attrs)
            |> validate_conditional_required()
          end

          # With custom fields (override)
          |> validate_conditional_required(fields: [
            {:phone, [contact_method: :phone]},
            {:address, [[type: :physical], :and, {:needs_shipping, :truthy}]}
          ])
      """
      def validate_conditional_required(changeset, opts \\ []) do
        fields = Keyword.get(opts, :fields, conditional_required_fields())
        Events.Schema.ConditionalRequired.validate(changeset, fields)
      end

      # =====================================================================
      # Field Transition Validation
      # =====================================================================

      @doc """
      Validates that a field change follows allowed transitions.

      Works for any field: status, order_status, role, type, state, etc.

      ## Setup

      Define allowed transitions as a module attribute:

          @status_transitions %{
            active: [:suspended, :deleted],
            suspended: [:active, :deleted],
            deleted: []    # terminal - no transitions allowed
          }

          @order_status_transitions %{
            pending: [:processing, :cancelled],
            processing: [:shipped, :cancelled],
            shipped: [:delivered, :returned],
            delivered: [],   # terminal
            cancelled: [],   # terminal
            returned: :any   # can transition to any state
          }

      ## Usage

          def changeset(user, attrs) do
            user
            |> base_changeset(attrs)
            |> validate_transition(:status, @status_transitions)
          end

          def changeset(order, attrs) do
            order
            |> base_changeset(attrs)
            |> validate_transition(:order_status, @order_status_transitions)
          end

      ## Transition values

        * `[:state1, :state2]` - can only transition to these states
        * `[]` - terminal state, no transitions allowed
        * `:any` - can transition to any state

      ## Options

        * `:message` - custom error message (supports `%{from}` and `%{to}` placeholders)

      ## Examples

          |> validate_transition(:status, @status_transitions)
          |> validate_transition(:role, @role_transitions, message: "invalid role change")
      """
      def validate_transition(changeset, field, transitions, opts \\ []) do
        new_value = get_change(changeset, field)
        current_value = Map.get(changeset.data, field)

        do_validate_transition(changeset, field, current_value, new_value, transitions, opts)
      end

      defp do_validate_transition(changeset, _field, _current, nil, _transitions, _opts),
        do: changeset

      defp do_validate_transition(changeset, _field, nil, _new, _transitions, _opts), do: changeset
      defp do_validate_transition(changeset, _field, same, same, _transitions, _opts), do: changeset

      defp do_validate_transition(changeset, field, current, new, transitions, opts) do
        allowed = Map.get(transitions, current, [])

        case transition_allowed?(allowed, new) do
          true -> changeset
          false -> add_transition_error(changeset, field, current, new, opts)
        end
      end

      defp transition_allowed?(:any, _new), do: true
      defp transition_allowed?(allowed, new) when is_list(allowed), do: new in allowed

      defp add_transition_error(changeset, field, current, new, opts) do
        message = Keyword.get(opts, :message, "cannot transition from %{from} to %{to}")

        formatted_message =
          message
          |> String.replace("%{from}", to_string(current))
          |> String.replace("%{to}", to_string(new))

        add_error(changeset, field, formatted_message)
      end

      # =====================================================================
      # Slug Generation
      # =====================================================================

      @doc """
      Generates a slug from a source field if slug is not already set.

      ## Examples

          def changeset(account, attrs) do
            account
            |> base_changeset(attrs)
            |> maybe_put_slug(from: :name)
            |> unique_constraints([{:slug, []}])
          end

      ## Options

        * `:from` - source field to generate slug from (required)
        * `:to` - target slug field (default: `:slug`)
        * `:uniquify` - append random suffix for uniqueness (default: `false`)

      ## Examples

          # Basic - generate :slug from :name
          |> maybe_put_slug(from: :name)

          # Custom target field
          |> maybe_put_slug(from: :title, to: :url_slug)

          # With uniqueness suffix (e.g., "my-post-a1b2c3")
          |> maybe_put_slug(from: :name, uniquify: true)
      """
      def maybe_put_slug(changeset, opts) do
        from_field = Keyword.fetch!(opts, :from)
        to_field = Keyword.get(opts, :to, :slug)
        uniquify = Keyword.get(opts, :uniquify, false)

        slug_change = get_change(changeset, to_field)
        existing_slug = Map.get(changeset.data, to_field)
        source_value = get_change(changeset, from_field) || Map.get(changeset.data, from_field)

        do_maybe_put_slug(changeset, to_field, slug_change, existing_slug, source_value, uniquify)
      end

      defp do_maybe_put_slug(changeset, _to_field, slug_change, _existing, _source, _uniquify)
           when not is_nil(slug_change),
           do: changeset

      defp do_maybe_put_slug(changeset, _to_field, _change, existing, _source, _uniquify)
           when not is_nil(existing),
           do: changeset

      defp do_maybe_put_slug(changeset, _to_field, _change, _existing, nil, _uniquify),
        do: changeset

      defp do_maybe_put_slug(changeset, _to_field, _change, _existing, source, _uniquify)
           when not is_binary(source),
           do: changeset

      defp do_maybe_put_slug(changeset, to_field, _change, _existing, source, uniquify) do
        case String.trim(source) do
          "" -> changeset
          trimmed -> put_change(changeset, to_field, generate_slug(trimmed, uniquify))
        end
      end

      defp generate_slug(value, uniquify) do
        slug =
          value
          |> String.downcase()
          |> String.replace(~r/[^\w\s-]/u, "")
          |> String.replace(~r/[\s_]+/, "-")
          |> String.replace(~r/-+/, "-")
          |> String.trim("-")

        append_uniqueness_suffix(slug, uniquify)
      end

      defp append_uniqueness_suffix(slug, false), do: slug

      defp append_uniqueness_suffix(slug, true) do
        suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
        "#{slug}-#{suffix}"
      end

      # =====================================================================
      # Soft Delete Helpers
      # =====================================================================

      # Only generate soft delete helpers if soft_delete_field() was used
      if Module.get_attribute(__MODULE__, :soft_delete_enabled) do
        @soft_delete_track_by_computed Module.get_attribute(
                                         __MODULE__,
                                         :soft_delete_track_by,
                                         false
                                       )

        @doc """
        Returns true if the record has been soft deleted.

        ## Examples

            User.deleted?(user)  # => true/false
        """
        def deleted?(%{deleted_at: nil}), do: false
        def deleted?(%{deleted_at: _}), do: true

        @doc """
        Creates a changeset to soft delete a record.

        Sets `deleted_at` to the current timestamp. If `track_deleted_by` was enabled,
        you can also pass `deleted_by_urm_id`.

        ## Examples

            user
            |> User.soft_delete_changeset()
            |> Repo.update()

            # With who deleted it
            user
            |> User.soft_delete_changeset(deleted_by_urm_id: urm_id)
            |> Repo.update()
        """
        def soft_delete_changeset(struct, opts \\ []) do
          now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
          deleted_by = Keyword.get(opts, :deleted_by_urm_id)

          changes =
            %{deleted_at: now}
            |> Events.Schema.maybe_put(:deleted_by_urm_id, deleted_by)

          Ecto.Changeset.change(struct, changes)
        end

        @doc """
        Creates a changeset to restore a soft-deleted record.

        Sets `deleted_at` (and `deleted_by_urm_id` if tracked) back to nil.

        ## Examples

            user
            |> User.restore_changeset()
            |> Repo.update()
        """
        if @soft_delete_track_by_computed do
          def restore_changeset(struct) do
            Ecto.Changeset.change(struct, %{deleted_at: nil, deleted_by_urm_id: nil})
          end
        else
          def restore_changeset(struct) do
            Ecto.Changeset.change(struct, %{deleted_at: nil})
          end
        end

        @doc """
        Filters query to exclude soft-deleted records.

        This is the most common filter - returns only "active" records.

        ## Examples

            User
            |> User.not_deleted()
            |> Repo.all()

            # Or with an existing query
            from(u in User, where: u.status == :active)
            |> User.not_deleted()
            |> Repo.all()
        """
        def not_deleted(query \\ __MODULE__) do
          import Ecto.Query, only: [from: 2]
          from(q in query, where: is_nil(q.deleted_at))
        end

        @doc """
        Filters query to only include soft-deleted records.

        Useful for admin interfaces or recovery features.

        ## Examples

            User
            |> User.only_deleted()
            |> Repo.all()
        """
        def only_deleted(query \\ __MODULE__) do
          import Ecto.Query, only: [from: 2]
          from(q in query, where: not is_nil(q.deleted_at))
        end

        @doc """
        Returns query without any deleted_at filter.

        Use when you need to see all records regardless of deletion status.

        ## Examples

            User
            |> User.with_deleted()
            |> Repo.all()
        """
        def with_deleted(query \\ __MODULE__), do: query
      end

      # =====================================================================
      # Constraint Introspection
      # =====================================================================

      # Collect field-level unique constraints
      @field_unique_constraints @field_validations
                                |> Enum.filter(fn {_name, _type, opts} ->
                                  Keyword.has_key?(opts, :unique)
                                end)
                                |> Enum.map(fn {name, _type, opts} ->
                                  Events.Schema.Constraints.normalize_unique_option(
                                    opts[:unique],
                                    @__schema_table_name__,
                                    name
                                  )
                                end)

      # Collect field-level check constraints
      @field_check_constraints @field_validations
                               |> Enum.filter(fn {_name, _type, opts} ->
                                 Keyword.has_key?(opts, :check)
                               end)
                               |> Enum.map(fn {name, _type, opts} ->
                                 Events.Schema.Constraints.normalize_check_option(
                                   opts[:check],
                                   @__schema_table_name__,
                                   name
                                 )
                               end)

      # Collect block-level constraints
      @unique_constraints_computed Module.get_attribute(__MODULE__, :constraint_unique) || []
      @foreign_key_constraints_computed Module.get_attribute(__MODULE__, :constraint_foreign_key) ||
                                          []
      @check_constraints_computed Module.get_attribute(__MODULE__, :constraint_check) || []
      @indexes_computed Module.get_attribute(__MODULE__, :constraint_index) || []
      @exclude_constraints_computed Module.get_attribute(__MODULE__, :constraint_exclude) || []
      @has_many_fk_expectations_computed Module.get_attribute(__MODULE__, :has_many_fk_expectations) ||
                                           []

      # Combine all unique constraints
      @all_unique_constraints @unique_constraints_computed ++ @field_unique_constraints

      # Combine all check constraints
      @all_check_constraints @check_constraints_computed ++ @field_check_constraints

      # Collect FK constraints from belongs_to fields (computed at compile time)
      @belongs_to_fk_constraints (Module.get_attribute(__MODULE__, :belongs_to_fields) || [])
                                 |> Enum.map(fn {_name, fk_field, queryable, constraint_config} ->
                                   # Get the related table name - queryable should be a module
                                   related_table =
                                     if is_atom(queryable) &&
                                          function_exported?(queryable, :__schema__, 1) do
                                       queryable.__schema__(:source)
                                     else
                                       # Fallback: derive from association name
                                       fk_field
                                       |> Atom.to_string()
                                       |> String.replace_trailing("_id", "s")
                                     end

                                   Events.Schema.Constraints.normalize_belongs_to_constraint(
                                     constraint_config,
                                     @__schema_table_name__,
                                     fk_field,
                                     related_table
                                   )
                                 end)
                                 |> Enum.reject(&is_nil/1)

      @all_foreign_key_constraints @foreign_key_constraints_computed ++ @belongs_to_fk_constraints

      @doc """
      Returns all declared constraint metadata.

      Includes unique constraints, foreign keys, check constraints, and exclusion constraints.
      """
      def __constraints__ do
        %{
          unique: @all_unique_constraints,
          foreign_key: @all_foreign_key_constraints,
          check: @all_check_constraints,
          exclude: @exclude_constraints_computed,
          primary_key: %{fields: [:id], name: :"#{@__schema_table_name__}_pkey"}
        }
      end

      @doc """
      Returns all declared index metadata.
      """
      def __indexes__ do
        # Include unique constraints as indexes
        unique_as_indexes =
          Enum.map(@all_unique_constraints, fn uc ->
            %{
              name: uc.name,
              fields: uc.fields,
              unique: true,
              where: uc.where
            }
          end)

        unique_as_indexes ++ @indexes_computed
      end

      @doc """
      Returns has_many FK validation expectations.
      """
      def __has_many_expectations__, do: @has_many_fk_expectations_computed

      # Public wrapper functions
      @doc "Returns all constraint metadata."
      def constraints, do: __constraints__()

      @doc "Returns all index metadata."
      def indexes, do: __indexes__()

      @doc "Returns foreign key constraint details."
      def foreign_keys, do: __constraints__().foreign_key

      @doc "Returns unique constraint details."
      def unique_constraints, do: __constraints__().unique

      @doc "Returns check constraint details."
      def check_constraints, do: __constraints__().check

      @doc "Returns has_many FK expectations for validation."
      def has_many_expectations, do: __has_many_expectations__()

      # =====================================================================
      # Backward Compatibility (deprecated)
      # =====================================================================

      @doc false
      @deprecated "Use cast_fields/0 instead"
      def __cast_fields__, do: cast_fields()

      @doc false
      @deprecated "Use required_fields/0 instead"
      def __required_fields__, do: required_fields()

      @doc false
      @deprecated "Use field_validations/0 instead"
      def __field_validations__, do: field_validations()

      @doc false
      @deprecated "Use apply_validations/1 instead"
      def __apply_field_validations__(changeset), do: apply_validations(changeset)

      @doc false
      @deprecated "Use base_changeset/2,3 instead"
      def __base_changeset__(struct, attrs, opts \\ []), do: base_changeset(struct, attrs, opts)
    end
  end
end
