defmodule OmCrud.SoftDelete do
  @moduledoc """
  Soft delete support for CRUD operations.

  Provides functions for soft-deleting records by setting a `deleted_at` timestamp
  instead of permanently removing them from the database.

  ## Schema Requirements

  Schemas must have a `deleted_at` field (configurable):

      schema "users" do
        field :deleted_at, :utc_datetime_usec
        # ...
      end

  ## Usage

      alias OmCrud.SoftDelete

      # Soft delete a record
      {:ok, user} = SoftDelete.delete(user)

      # Restore a soft-deleted record
      {:ok, user} = SoftDelete.restore(user)

      # Check if soft deleted
      SoftDelete.deleted?(user)
      #=> true

      # Permanently delete
      {:ok, user} = OmCrud.delete(user)

  ## Query Integration

  Use with OmQuery to filter out soft-deleted records:

      User
      |> OmQuery.new()
      |> SoftDelete.exclude_deleted()
      |> OmCrud.fetch_all()

  ## Configuration

  Configure the deleted_at field name globally:

      config :om_crud, OmCrud.SoftDelete,
        field: :deleted_at,
        timestamp: &DateTime.utc_now/0

  Or per-schema:

      defmodule MyApp.User do
        use OmSchema

        @soft_delete_field :archived_at

        schema "users" do
          field :archived_at, :utc_datetime_usec
        end
      end
  """

  alias OmCrud.{Error, Multi, Options}

  @default_field :deleted_at

  @type soft_delete_opts :: [
          field: atom(),
          timestamp: (-> DateTime.t()),
          repo: module(),
          changeset: atom()
        ]

  # ─────────────────────────────────────────────────────────────
  # Soft Delete Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Soft delete a record by setting the deleted_at timestamp.

  ## Options

  - `:field` - The deleted_at field name (default: :deleted_at or schema attribute)
  - `:timestamp` - Function to generate timestamp (default: DateTime.utc_now/0)
  - `:changeset` - Changeset function to use (default: uses cast)
  - `:repo` - Repo to use

  ## Examples

      {:ok, user} = SoftDelete.delete(user)
      {:ok, user} = SoftDelete.delete(user, field: :archived_at)
  """
  @spec delete(struct(), soft_delete_opts()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def delete(%{__struct__: schema} = struct, opts \\ []) do
    field = get_field(schema, opts)
    timestamp_fn = Keyword.get(opts, :timestamp, &default_timestamp/0)
    repo = Options.repo(opts)

    changeset =
      struct
      |> Ecto.Changeset.change(%{field => timestamp_fn.()})

    case repo.update(changeset) do
      {:ok, updated} -> {:ok, updated}
      {:error, changeset} -> {:error, Error.from_changeset(changeset, operation: :soft_delete)}
    end
  end

  @doc """
  Soft delete a record by schema and ID.

  ## Examples

      {:ok, user} = SoftDelete.delete(User, user_id)
  """
  @spec delete(module(), binary(), soft_delete_opts()) ::
          {:ok, struct()} | {:error, Error.t()}
  def delete(schema, id, opts) when is_atom(schema) and is_binary(id) do
    repo = Options.repo(opts)

    case repo.get(schema, id) do
      nil -> {:error, Error.not_found(schema, id, operation: :soft_delete)}
      struct -> delete(struct, opts)
    end
  end

  @doc """
  Restore a soft-deleted record by clearing the deleted_at timestamp.

  ## Examples

      {:ok, user} = SoftDelete.restore(user)
      {:ok, user} = SoftDelete.restore(user, field: :archived_at)
  """
  @spec restore(struct(), soft_delete_opts()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def restore(%{__struct__: schema} = struct, opts \\ []) do
    field = get_field(schema, opts)
    repo = Options.repo(opts)

    changeset =
      struct
      |> Ecto.Changeset.change(%{field => nil})

    case repo.update(changeset) do
      {:ok, updated} -> {:ok, updated}
      {:error, changeset} -> {:error, Error.from_changeset(changeset, operation: :restore)}
    end
  end

  @doc """
  Restore a soft-deleted record by schema and ID.

  ## Examples

      {:ok, user} = SoftDelete.restore(User, user_id)
  """
  @spec restore(module(), binary(), soft_delete_opts()) ::
          {:ok, struct()} | {:error, Error.t()}
  def restore(schema, id, opts) when is_atom(schema) and is_binary(id) do
    repo = Options.repo(opts)

    case repo.get(schema, id) do
      nil -> {:error, Error.not_found(schema, id, operation: :restore)}
      struct -> restore(struct, opts)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Multi Integration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add a soft delete operation to a Multi.

  ## Examples

      Multi.new()
      |> SoftDelete.multi_delete(:user, user)
      |> OmCrud.run()
  """
  @spec multi_delete(Multi.t(), atom(), struct() | {module(), binary()}, soft_delete_opts()) ::
          Multi.t()
  def multi_delete(multi, name, struct_or_ref, opts \\ [])

  def multi_delete(%Multi{} = multi, name, %{__struct__: schema} = struct, opts) do
    field = get_field(schema, opts)
    timestamp_fn = Keyword.get(opts, :timestamp, &default_timestamp/0)

    Multi.update(multi, name, struct, %{field => timestamp_fn.()}, opts)
  end

  def multi_delete(%Multi{} = multi, name, {schema, id}, opts)
      when is_atom(schema) and is_binary(id) do
    field = get_field(schema, opts)
    timestamp_fn = Keyword.get(opts, :timestamp, &default_timestamp/0)

    Multi.update(multi, name, {schema, id}, %{field => timestamp_fn.()}, opts)
  end

  @doc """
  Add a restore operation to a Multi.

  ## Examples

      Multi.new()
      |> SoftDelete.multi_restore(:user, user)
      |> OmCrud.run()
  """
  @spec multi_restore(Multi.t(), atom(), struct() | {module(), binary()}, soft_delete_opts()) ::
          Multi.t()
  def multi_restore(multi, name, struct_or_ref, opts \\ [])

  def multi_restore(%Multi{} = multi, name, %{__struct__: schema} = struct, opts) do
    field = get_field(schema, opts)
    Multi.update(multi, name, struct, %{field => nil}, opts)
  end

  def multi_restore(%Multi{} = multi, name, {schema, id}, opts)
      when is_atom(schema) and is_binary(id) do
    field = get_field(schema, opts)
    Multi.update(multi, name, {schema, id}, %{field => nil}, opts)
  end

  # ─────────────────────────────────────────────────────────────
  # Query Helpers
  # ─────────────────────────────────────────────────────────────

  @doc """
  Filter a query to exclude soft-deleted records.

  Works with both Ecto.Query and OmQuery tokens.

  ## Examples

      # With Ecto.Query
      query = from u in User, where: u.status == :active
      query = SoftDelete.exclude_deleted(query)

      # With OmQuery
      User
      |> OmQuery.new()
      |> SoftDelete.exclude_deleted()
      |> OmCrud.fetch_all()
  """
  @spec exclude_deleted(Ecto.Query.t() | struct(), keyword()) :: Ecto.Query.t() | struct()
  def exclude_deleted(query_or_token, opts \\ [])

  def exclude_deleted(%Ecto.Query{} = query, opts) do
    field = Keyword.get(opts, :field, @default_field)

    import Ecto.Query
    where(query, [q], is_nil(field(q, ^field)))
  end

  def exclude_deleted(%{__struct__: module} = token, opts) do
    if function_exported?(module, :where, 3) do
      field = Keyword.get(opts, :field, @default_field)
      module.where(token, field, nil)
    else
      token
    end
  end

  @doc """
  Filter a query to only include soft-deleted records.

  ## Examples

      # Find all soft-deleted users
      User
      |> OmQuery.new()
      |> SoftDelete.only_deleted()
      |> OmCrud.fetch_all()
  """
  @spec only_deleted(Ecto.Query.t() | struct(), keyword()) :: Ecto.Query.t() | struct()
  def only_deleted(query_or_token, opts \\ [])

  def only_deleted(%Ecto.Query{} = query, opts) do
    field = Keyword.get(opts, :field, @default_field)

    import Ecto.Query
    where(query, [q], not is_nil(field(q, ^field)))
  end

  def only_deleted(%{__struct__: module} = token, opts) do
    if function_exported?(module, :where_not_nil, 2) do
      field = Keyword.get(opts, :field, @default_field)
      module.where_not_nil(token, field)
    else
      token
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Predicates
  # ─────────────────────────────────────────────────────────────

  @doc """
  Check if a record has been soft deleted.

  ## Examples

      SoftDelete.deleted?(user)
      #=> true

      SoftDelete.deleted?(user, field: :archived_at)
      #=> false
  """
  @spec deleted?(struct(), keyword()) :: boolean()
  def deleted?(%{__struct__: schema} = struct, opts \\ []) do
    field = get_field(schema, opts)
    Map.get(struct, field) != nil
  end

  @doc """
  Get the deletion timestamp from a record.

  ## Examples

      SoftDelete.deleted_at(user)
      #=> ~U[2024-01-15 10:30:00Z]

      SoftDelete.deleted_at(active_user)
      #=> nil
  """
  @spec deleted_at(struct(), keyword()) :: DateTime.t() | nil
  def deleted_at(%{__struct__: schema} = struct, opts \\ []) do
    field = get_field(schema, opts)
    Map.get(struct, field)
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp get_field(schema, opts) do
    # Priority: opts > schema callback > config > default
    cond do
      field = Keyword.get(opts, :field) ->
        field

      # Check if schema defines a soft_delete_field/0 callback
      Code.ensure_loaded?(schema) and function_exported?(schema, :soft_delete_field, 0) ->
        schema.soft_delete_field()

      true ->
        Application.get_env(:om_crud, __MODULE__)[:field] || @default_field
    end
  end

  defp default_timestamp do
    config = Application.get_env(:om_crud, __MODULE__, [])
    timestamp_fn = Keyword.get(config, :timestamp, &DateTime.utc_now/0)
    timestamp_fn.()
  end
end
