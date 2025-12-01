defprotocol Events.Identifiable do
  @fallback_to_any true
  @moduledoc """
  Protocol for extracting identity from domain entities.

  Identifiable provides a standardized way to extract type and ID information
  from any domain entity, enabling consistent patterns across:

  - **Cache key generation** - Uniform, type-safe cache keys
  - **Event sourcing** - Aggregate root identification
  - **Deduplication** - Prevent duplicate processing in async operations
  - **Entity equality** - Compare entities by identity, not attributes
  - **Audit trails** - Track entity references consistently
  - **GraphQL** - Global object identification (Relay Node interface)

  ## Quick Start

      # Derive for your schema
      defmodule MyApp.User do
        @derive {Events.Identifiable, type: :user}
        use Events.Schema
        # ...
      end

      # Use it
      user = Repo.get!(User, "usr_123")
      Events.Identifiable.identity(user)
      #=> {:user, "usr_123"}

  ## Protocol Functions

  | Function | Returns | Description |
  |----------|---------|-------------|
  | `entity_type/1` | `atom()` | The entity type (`:user`, `:order`, etc.) |
  | `id/1` | `String.t() \| integer() \| nil` | The unique identifier |
  | `identity/1` | `{atom(), id}` | Compound identity tuple |

  ## Deriving for Schemas

  The easiest way to implement Identifiable is via `@derive`:

      defmodule MyApp.User do
        @derive {Events.Identifiable, type: :user}
        use Events.Schema
        # ...
      end

  ### Derive Options

  - `:type` - Entity type atom (default: derived from module name)
  - `:id_field` - Field to use as ID (default: `:id`)

      # Custom ID field
      @derive {Events.Identifiable, type: :invoice, id_field: :invoice_number}

      # Auto-derived type from module name (MyApp.User -> :user)
      @derive Events.Identifiable

  ## Manual Implementation

  For non-schema types or custom behavior:

      defimpl Events.Identifiable, for: MyApp.ExternalUser do
        def entity_type(_), do: :external_user
        def id(%{external_id: ext_id}), do: ext_id
        def identity(user), do: {:external_user, user.external_id}
      end

  ## Usage Patterns

  ### Cache Keys

      def cache_key(entity) do
        {type, id} = Identifiable.identity(entity)
        "\#{type}:\#{id}"
      end

  ### Entity Equality

      def same_entity?(a, b) do
        Identifiable.identity(a) == Identifiable.identity(b)
      end

  ### Audit Logging

      def audit(entity, action, actor) do
        {entity_type, entity_id} = Identifiable.identity(entity)
        {actor_type, actor_id} = Identifiable.identity(actor)

        %AuditLog{
          entity_type: entity_type,
          entity_id: entity_id,
          action: action,
          performed_by_type: actor_type,
          performed_by_id: actor_id
        }
      end

  ### GraphQL Global IDs

      def to_global_id(entity) do
        {type, id} = Identifiable.identity(entity)
        Base.encode64("\#{type}:\#{id}")
      end

  ## Integration with Other Protocols

  Identifiable works well with other Events protocols:

      # With Cacheable
      defimpl Events.Cacheable, for: MyApp.User do
        def cache_key(user), do: Events.Identifiable.identity(user)
        # ...
      end

      # With Loggable
      defimpl Events.Loggable, for: MyApp.User do
        def log_context(user) do
          {type, id} = Events.Identifiable.identity(user)
          %{entity_type: type, entity_id: id, ...}
        end
      end

  ## Default Implementations

  The protocol includes implementations for:

  - `Any` (fallback) - Returns `:unknown` type and attempts to extract `:id` field
  - `Events.Error` - Uses error type and generated error ID
  - `Ecto.Changeset` - Extracts from underlying data or changes
  - Maps with `:id` key - Basic map support

  ## Telemetry

  Helper functions in `Events.Identifiable.Helpers` emit telemetry:

      [:events, :identifiable, :lookup]
      - measurements: %{count: 1}
      - metadata: %{type: :user, id: "usr_123"}
  """

  @type id :: String.t() | integer() | nil
  @type identity :: {atom(), id()}

  @doc """
  Returns the entity type as an atom.

  The type should be a lowercase atom that uniquely identifies the kind
  of entity. Common conventions:

  - Singular nouns: `:user`, `:order`, `:product`
  - Domain-prefixed: `:billing_invoice`, `:auth_session`

  ## Examples

      Identifiable.entity_type(user)
      #=> :user

      Identifiable.entity_type(order)
      #=> :order

      Identifiable.entity_type(%{__struct__: MyApp.Invoice})
      #=> :invoice
  """
  @spec entity_type(t) :: atom()
  def entity_type(entity)

  @doc """
  Returns the unique identifier for the entity.

  The ID should uniquely identify the entity within its type. Returns
  `nil` for entities that haven't been persisted yet.

  ## Examples

      Identifiable.id(user)
      #=> "usr_a1b2c3d4"

      Identifiable.id(%User{id: nil})
      #=> nil

      Identifiable.id(invoice)
      #=> "INV-2024-001"
  """
  @spec id(t) :: id()
  def id(entity)

  @doc """
  Returns a compound identity tuple of `{type, id}`.

  This is the primary function for identity comparison and key generation.
  The tuple uniquely identifies an entity across all types in the system.

  ## Examples

      Identifiable.identity(user)
      #=> {:user, "usr_a1b2c3d4"}

      Identifiable.identity(order)
      #=> {:order, 12345}

      # Two entities with same identity are the same entity
      Identifiable.identity(user_v1) == Identifiable.identity(user_v2)
      #=> true
  """
  @spec identity(t) :: identity()
  def identity(entity)
end
