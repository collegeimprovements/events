defimpl Events.Identifiable, for: Any do
  @moduledoc """
  Fallback Identifiable implementation for any value.

  This implementation provides:

  1. **Deriving support** for Ecto schemas and structs
  2. **Fallback behavior** for unknown types

  ## Deriving Identifiable

  The easiest way to implement Identifiable for your schemas:

      defmodule MyApp.User do
        @derive {Events.Identifiable, type: :user}
        use Events.Schema

        schema "users" do
          # ...
        end
      end

  ## Derive Options

  - `:type` - Entity type atom. If not provided, derived from module name:
    - `MyApp.Accounts.User` -> `:user`
    - `MyApp.Billing.Invoice` -> `:invoice`

  - `:id_field` - Field to use as ID (default: `:id`)

  ## Examples

      # Simple derivation (type auto-derived from module name)
      @derive Events.Identifiable

      # Explicit type
      @derive {Events.Identifiable, type: :user}

      # Custom ID field
      @derive {Events.Identifiable, type: :invoice, id_field: :invoice_number}

      # Full options
      @derive {Events.Identifiable, type: :order, id_field: :order_id}

  ## Fallback Behavior

  For types without an implementation, the protocol returns:

  - `entity_type/1` -> `:unknown`
  - `id/1` -> `nil` (or value of `:id` key if present in a map/struct)
  - `identity/1` -> `{:unknown, nil}`

  This is a safe default that allows the protocol to be called on any
  value without raising, while making it clear the type is unknown.

  ## Custom Implementation

  For more control, implement the protocol directly:

      defimpl Events.Identifiable, for: MyApp.ExternalUser do
        def entity_type(_), do: :external_user

        def id(%{external_id: id}), do: id
        def id(_), do: nil

        def identity(user), do: {:external_user, id(user)}
      end
  """

  # Default options for derived implementations
  @default_opts [
    id_field: :id
  ]

  @doc false
  defmacro __deriving__(module, _struct, opts) do
    opts = Keyword.merge(@default_opts, List.wrap(opts))

    id_field = Keyword.fetch!(opts, :id_field)

    # Derive type from module name if not provided
    # MyApp.Accounts.User -> :user
    # MyApp.Billing.Invoice -> :invoice
    type =
      Keyword.get_lazy(opts, :type, fn ->
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()
      end)

    quote do
      defimpl Events.Identifiable, for: unquote(module) do
        @impl true
        def entity_type(_), do: unquote(type)

        @impl true
        def id(entity), do: Map.get(entity, unquote(id_field))

        @impl true
        def identity(entity) do
          {unquote(type), Map.get(entity, unquote(id_field))}
        end
      end
    end
  end

  @doc """
  Returns `:unknown` for types without a specific implementation.

  This is a safe fallback that allows the protocol to work on any
  value without raising.
  """
  @impl true
  def entity_type(_), do: :unknown

  @doc """
  Attempts to extract an ID from the value.

  For structs and maps, tries to get the `:id` key.
  Returns `nil` for all other values.
  """
  @impl true
  def id(%{id: id}), do: id
  def id(_), do: nil

  @doc """
  Returns `{:unknown, id}` where id is extracted if possible.

  The `:unknown` type makes it clear this value doesn't have
  a proper Identifiable implementation.
  """
  @impl true
  def identity(entity) do
    {:unknown, id(entity)}
  end
end
