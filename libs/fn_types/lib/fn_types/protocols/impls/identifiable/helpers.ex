defmodule FnTypes.Protocols.Identifiable.Helpers do
  @moduledoc """
  Convenience functions for working with the Identifiable protocol.

  These helpers provide common patterns for identity-based operations:
  - Cache key generation
  - Entity equality comparison
  - Collection utilities
  - Telemetry integration
  - GraphQL global IDs

  ## Usage

      alias FnTypes.Protocols.Identifiable.Helpers

      # Generate cache key
      Helpers.cache_key(user)
      #=> "user:usr_123"

      # Compare entities
      Helpers.same_entity?(user_v1, user_v2)
      #=> true

      # Deduplicate by identity
      Helpers.unique_by_identity([user1, user2, user1_copy])
      #=> [user1, user2]

      # GraphQL global IDs
      Helpers.to_global_id(user)
      #=> "dXNlcjp1c3JfMTIz"

      Helpers.from_global_id("dXNlcjp1c3JfMTIz")
      #=> {:ok, {:user, "usr_123"}}
  """

  alias FnTypes.Protocols.Identifiable

  @telemetry_prefix Application.compile_env(:fn_types, :telemetry_prefix, [:fn_types])

  @type identity :: {atom(), Identifiable.id()}

  # =============================================================================
  # Core Helpers
  # =============================================================================

  @doc """
  Generates a cache key string from an entity's identity.

  The format is `"type:id"` which is suitable for most cache backends.

  ## Options

  - `:prefix` - Optional prefix to prepend (default: none)
  - `:separator` - Character to join parts (default: `":"`)

  ## Examples

      Helpers.cache_key(user)
      #=> "user:usr_123"

      Helpers.cache_key(order, prefix: "v1")
      #=> "v1:order:ord_456"

      Helpers.cache_key(product, separator: "/")
      #=> "product/prod_789"
  """
  @spec cache_key(term(), keyword()) :: String.t()
  def cache_key(entity, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)
    separator = Keyword.get(opts, :separator, ":")

    {type, id} = Identifiable.identity(entity)

    parts =
      [prefix, type, id]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    Enum.join(parts, separator)
  end

  @doc """
  Generates a cache key tuple suitable for ETS/Cachex.

  Returns `{type, id}` which can be used directly as a cache key.

  ## Examples

      Helpers.cache_key_tuple(user)
      #=> {:user, "usr_123"}
  """
  @spec cache_key_tuple(term()) :: identity()
  def cache_key_tuple(entity) do
    Identifiable.identity(entity)
  end

  @doc """
  Checks if two entities have the same identity.

  Two entities are considered the same if they have the same type and ID,
  regardless of their attribute values.

  ## Examples

      # Same user at different points in time
      Helpers.same_entity?(user_v1, user_v2)
      #=> true

      # Different users
      Helpers.same_entity?(alice, bob)
      #=> false

      # Different types
      Helpers.same_entity?(user, order)
      #=> false
  """
  @spec same_entity?(term(), term()) :: boolean()
  def same_entity?(entity_a, entity_b) do
    Identifiable.identity(entity_a) == Identifiable.identity(entity_b)
  end

  @doc """
  Checks if an entity has been persisted (has a non-nil ID).

  ## Examples

      Helpers.persisted?(existing_user)
      #=> true

      Helpers.persisted?(%User{})
      #=> false
  """
  @spec persisted?(term()) :: boolean()
  def persisted?(entity) do
    Identifiable.id(entity) != nil
  end

  # =============================================================================
  # Collection Utilities
  # =============================================================================

  @doc """
  Removes duplicate entities based on identity.

  Keeps the first occurrence of each unique identity.

  ## Examples

      users = [alice, bob, alice_updated]
      Helpers.unique_by_identity(users)
      #=> [alice, bob]  # alice_updated removed (same identity as alice)
  """
  @spec unique_by_identity([term()]) :: [term()]
  def unique_by_identity(entities) do
    entities
    |> Enum.uniq_by(&Identifiable.identity/1)
  end

  @doc """
  Groups entities by their type.

  ## Examples

      entities = [user1, order1, user2, order2]
      Helpers.group_by_type(entities)
      #=> %{user: [user1, user2], order: [order1, order2]}
  """
  @spec group_by_type([term()]) :: %{atom() => [term()]}
  def group_by_type(entities) do
    Enum.group_by(entities, &Identifiable.entity_type/1)
  end

  @doc """
  Partitions entities into persisted and unpersisted groups.

  ## Examples

      {persisted, new} = Helpers.partition_persisted(users)
  """
  @spec partition_persisted([term()]) :: {[term()], [term()]}
  def partition_persisted(entities) do
    Enum.split_with(entities, &persisted?/1)
  end

  @doc """
  Extracts all IDs from a list of entities.

  Filters out nil IDs (unpersisted entities).

  ## Examples

      Helpers.extract_ids([user1, user2, new_user])
      #=> ["usr_123", "usr_456"]
  """
  @spec extract_ids([term()]) :: [Identifiable.id()]
  def extract_ids(entities) do
    entities
    |> Enum.map(&Identifiable.id/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Creates a lookup map from identity to entity.

  Useful for efficient lookups after fetching entities.

  ## Examples

      users = Repo.all(User)
      lookup = Helpers.identity_map(users)

      # Later
      user = lookup[{:user, "usr_123"}]
  """
  @spec identity_map([term()]) :: %{identity() => term()}
  def identity_map(entities) do
    Map.new(entities, fn entity ->
      {Identifiable.identity(entity), entity}
    end)
  end

  @doc """
  Finds an entity in a list by its identity.

  ## Examples

      Helpers.find_by_identity(users, {:user, "usr_123"})
      #=> %User{id: "usr_123", ...}

      Helpers.find_by_identity(users, {:user, "nonexistent"})
      #=> nil
  """
  @spec find_by_identity([term()], identity()) :: term() | nil
  def find_by_identity(entities, identity) do
    Enum.find(entities, fn entity ->
      Identifiable.identity(entity) == identity
    end)
  end

  # =============================================================================
  # GraphQL Global IDs (Relay Spec)
  # =============================================================================

  @doc """
  Encodes an entity's identity as a GraphQL global ID.

  The global ID is a Base64-encoded string of `"type:id"`, compatible
  with the Relay GraphQL specification for Node interface.

  ## Examples

      Helpers.to_global_id(user)
      #=> "dXNlcjp1c3JfMTIz"

      Helpers.to_global_id(order)
      #=> "b3JkZXI6MTIzNDU="
  """
  @spec to_global_id(term()) :: String.t()
  def to_global_id(entity) do
    {type, id} = Identifiable.identity(entity)
    Base.encode64("#{type}:#{id}")
  end

  @doc """
  Decodes a GraphQL global ID back to an identity tuple.

  Returns `{:ok, {type, id}}` or `{:error, reason}`.

  ## Examples

      Helpers.from_global_id("dXNlcjp1c3JfMTIz")
      #=> {:ok, {:user, "usr_123"}}

      Helpers.from_global_id("invalid")
      #=> {:error, :invalid_global_id}
  """
  @spec from_global_id(String.t()) :: {:ok, identity()} | {:error, :invalid_global_id}
  def from_global_id(global_id) when is_binary(global_id) do
    case Base.decode64(global_id) do
      {:ok, decoded} ->
        case String.split(decoded, ":", parts: 2) do
          [type_str, id] ->
            type = String.to_existing_atom(type_str)
            {:ok, {type, id}}

          _ ->
            {:error, :invalid_global_id}
        end

      :error ->
        {:error, :invalid_global_id}
    end
  rescue
    ArgumentError -> {:error, :invalid_global_id}
  end

  @doc """
  Decodes a GraphQL global ID, raising on error.

  ## Examples

      Helpers.from_global_id!("dXNlcjp1c3JfMTIz")
      #=> {:user, "usr_123"}
  """
  @spec from_global_id!(String.t()) :: identity()
  def from_global_id!(global_id) do
    case from_global_id(global_id) do
      {:ok, identity} -> identity
      {:error, reason} -> raise ArgumentError, "Invalid global ID: #{reason}"
    end
  end

  # =============================================================================
  # Idempotency Keys
  # =============================================================================

  @doc """
  Generates an idempotency key for an operation on an entity.

  Useful for ensuring operations are only performed once.

  ## Options

  - `:namespace` - Optional namespace prefix

  ## Examples

      Helpers.idempotency_key(order, :process_payment)
      #=> "order:ord_123:process_payment"

      Helpers.idempotency_key(user, :send_welcome_email, namespace: "v2")
      #=> "v2:user:usr_456:send_welcome_email"
  """
  @spec idempotency_key(term(), atom(), keyword()) :: String.t()
  def idempotency_key(entity, operation, opts \\ []) when is_atom(operation) do
    namespace = Keyword.get(opts, :namespace)
    {type, id} = Identifiable.identity(entity)

    parts =
      [namespace, type, id, operation]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    Enum.join(parts, ":")
  end

  # =============================================================================
  # Telemetry
  # =============================================================================

  @doc """
  Emits a telemetry event for identity lookup.

  Event: `[:events, :identifiable, :lookup]`

  ## Measurements

  - `:count` - Always 1 (for aggregation)

  ## Metadata

  - `:type` - Entity type
  - `:id` - Entity ID
  - `:has_id` - Whether entity has an ID
  """
  @spec emit_telemetry(term()) :: :ok
  def emit_telemetry(entity) do
    {type, id} = Identifiable.identity(entity)

    measurements = %{count: 1}

    metadata = %{
      type: type,
      id: id,
      has_id: not is_nil(id)
    }

    FnTypes.Telemetry.execute(@telemetry_prefix ++ [:identifiable, :lookup], measurements, metadata)
  end

  @doc """
  Returns a summary map of the entity's identity.

  Useful for logging and debugging.

  ## Examples

      Helpers.identity_info(user)
      #=> %{
      #=>   type: :user,
      #=>   id: "usr_123",
      #=>   persisted: true,
      #=>   cache_key: "user:usr_123",
      #=>   global_id: "dXNlcjp1c3JfMTIz"
      #=> }
  """
  @spec identity_info(term()) :: map()
  def identity_info(entity) do
    {type, id} = Identifiable.identity(entity)

    %{
      type: type,
      id: id,
      persisted: not is_nil(id),
      cache_key: cache_key(entity),
      global_id: if(id, do: to_global_id(entity), else: nil)
    }
  end

  # =============================================================================
  # Formatting
  # =============================================================================

  @doc """
  Formats an entity's identity as a human-readable string.

  ## Examples

      Helpers.format_identity(user)
      #=> "user:usr_123"

      Helpers.format_identity(%User{})
      #=> "user:<new>"
  """
  @spec format_identity(term()) :: String.t()
  def format_identity(entity) do
    {type, id} = Identifiable.identity(entity)
    id_str = if id, do: to_string(id), else: "<new>"
    "#{type}:#{id_str}"
  end

  @doc """
  Formats multiple identities as a list string.

  ## Examples

      Helpers.format_identities([user1, user2, order1])
      #=> "user:usr_1, user:usr_2, order:ord_1"
  """
  @spec format_identities([term()]) :: String.t()
  def format_identities(entities) do
    entities
    |> Enum.map(&format_identity/1)
    |> Enum.join(", ")
  end
end
