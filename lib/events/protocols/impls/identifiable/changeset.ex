defimpl Events.Protocols.Identifiable, for: Ecto.Changeset do
  @moduledoc """
  Identifiable implementation for Ecto.Changeset.

  Extracts identity from the changeset's underlying data, allowing
  changesets to be used interchangeably with their associated entities
  for identity-related operations.

  ## Identity Extraction

  The implementation extracts identity by:

  1. Getting the schema module from the changeset data
  2. Extracting the ID from either:
     - The changeset data (for existing records)
     - The changeset changes (for new records with explicit ID)

  ## Examples

      # Existing user changeset
      user = Repo.get!(User, "usr_123")
      changeset = User.changeset(user, %{name: "New Name"})

      Identifiable.entity_type(changeset)
      #=> :user

      Identifiable.id(changeset)
      #=> "usr_123"

      Identifiable.identity(changeset)
      #=> {:user, "usr_123"}

  ## New Records

  For new records (not yet persisted), the ID will be `nil` unless
  explicitly set in the changeset:

      new_user = %User{}
      changeset = User.changeset(new_user, %{email: "test@example.com"})

      Identifiable.id(changeset)
      #=> nil

      # With explicit ID
      changeset_with_id = User.changeset(new_user, %{id: "usr_456", email: "test@example.com"})
      Identifiable.id(changeset_with_id)
      #=> "usr_456"

  ## Type Derivation

  The entity type is derived from the schema module name:

  - `Events.Accounts.User` -> `:user`
  - `Events.Billing.Invoice` -> `:invoice`

  If the underlying schema implements Identifiable, we delegate to it
  for consistent type naming.

  ## Use Cases

  ### Logging Operations

      def log_change(changeset, operation) do
        {type, id} = Identifiable.identity(changeset)
        Logger.info("[\#{operation}] \#{type}:\#{id || "new"}")
      end

  ### Audit Trail

      def audit_changeset(changeset, actor) do
        {entity_type, entity_id} = Identifiable.identity(changeset)

        %AuditLog{
          entity_type: entity_type,
          entity_id: entity_id || "pending",
          changes: changeset.changes,
          actor_id: actor.id
        }
      end
  """

  @doc """
  Returns the entity type derived from the changeset's schema module.

  If the underlying data struct implements Identifiable, delegates to
  that implementation for consistent type naming.

  ## Examples

      Identifiable.entity_type(user_changeset)
      #=> :user

      Identifiable.entity_type(order_changeset)
      #=> :order
  """
  @impl true
  def entity_type(%Ecto.Changeset{data: %{__struct__: module} = data}) do
    # Check if the underlying struct has Identifiable implemented
    # If so, delegate to it for consistent type naming
    if identifiable_impl_for(module) do
      Events.Protocols.Identifiable.entity_type(data)
    else
      derive_type_from_module(module)
    end
  end

  def entity_type(%Ecto.Changeset{}), do: :unknown

  @doc """
  Returns the ID from the changeset's data or changes.

  Checks the data first (for existing records), then falls back
  to checking the changes (for new records with explicit ID).

  ## Examples

      Identifiable.id(existing_user_changeset)
      #=> "usr_123"

      Identifiable.id(new_user_changeset)
      #=> nil
  """
  @impl true
  def id(%Ecto.Changeset{data: data, changes: changes}) do
    # Prefer ID from data (existing record), fall back to changes (new with explicit ID)
    case Map.get(data, :id) do
      nil -> Map.get(changes, :id)
      existing_id -> existing_id
    end
  end

  @doc """
  Returns the compound identity `{type, id}` for the changeset.

  ## Examples

      Identifiable.identity(user_changeset)
      #=> {:user, "usr_123"}

      Identifiable.identity(new_order_changeset)
      #=> {:order, nil}
  """
  @impl true
  def identity(%Ecto.Changeset{} = changeset) do
    {entity_type(changeset), id(changeset)}
  end

  # Private helpers

  defp derive_type_from_module(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp identifiable_impl_for(module) do
    # Check if there's a specific implementation (not the Any fallback)
    impl = Events.Protocols.Identifiable.impl_for(struct(module, %{}))
    impl && impl != Events.Protocols.Identifiable.Any
  rescue
    # If we can't construct the struct, fall back to type derivation
    _ -> false
  end
end
