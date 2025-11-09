defmodule Events.Repo.SoftDelete do
  @moduledoc """
  Soft delete utilities and helpers for managing record lifecycle.

  This module provides convenient functions for soft deleting, restoring,
  and querying soft-deleted records. It works in conjunction with the
  `deleted_fields/1` migration macro and the CRUD DSL.

  ## Schema Setup

  To enable soft delete support, add `deleted_fields/1` to your migration:

      create table(:products) do
        add :name, :citext, null: false
        add :price, :decimal, null: false

        deleted_fields()  # Adds deleted_at and deleted_by_urm_id
        timestamps()
      end

  ## Usage in Schemas

  Include the soft delete helpers in your schema module:

      defmodule MyApp.Product do
        use Ecto.Schema
        import Events.Repo.SoftDelete

        schema "products" do
          field :name, :string
          field :price, :decimal

          field :deleted_at, :utc_datetime_usec
          field :deleted_by_urm_id, :binary_id

          timestamps()
        end

        # Add default scope to exclude deleted records
        def base_query do
          not_deleted(__MODULE__)
        end
      end

  ## Query Functions

      # Get only active (non-deleted) records
      Product.base_query() |> Repo.all()

      # Include soft-deleted records
      Product |> SoftDelete.with_deleted() |> Repo.all()

      # Get only soft-deleted records
      Product |> SoftDelete.only_deleted() |> Repo.all()

  ## Lifecycle Functions

      # Soft delete a record
      {:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: user_id)

      # Restore a deleted record
      {:ok, restored} = SoftDelete.restore(product)

      # Permanently delete (hard delete)
      {:ok, deleted} = SoftDelete.hard_delete(product)
  """

  import Ecto.Query
  alias Events.Repo
  alias Events.Repo.Crud

  @type queryable :: Ecto.Query.t() | module()
  @type schema_struct :: Ecto.Schema.t()
  @type user_id :: binary()

  ## Query Scopes

  @doc """
  Filters query to exclude soft-deleted records.

  This is typically used as a default scope in your schema.

  ## Examples

      def base_query do
        not_deleted(__MODULE__)
      end

      Product |> SoftDelete.not_deleted() |> Repo.all()
  """
  @spec not_deleted(queryable()) :: Ecto.Query.t()
  def not_deleted(query) do
    from q in query, where: is_nil(q.deleted_at)
  end

  @doc """
  Filters query to include only soft-deleted records.

  ## Examples

      Product |> SoftDelete.only_deleted() |> Repo.all()
  """
  @spec only_deleted(queryable()) :: Ecto.Query.t()
  def only_deleted(query) do
    from q in query, where: not is_nil(q.deleted_at)
  end

  @doc """
  Returns query that includes both active and soft-deleted records.

  Use this when you need to see all records regardless of deletion status.

  ## Examples

      Product |> SoftDelete.with_deleted() |> Repo.all()
  """
  @spec with_deleted(queryable()) :: Ecto.Query.t()
  def with_deleted(query) do
    # Just return the query as-is, without filtering
    from(q in query)
  end

  @doc """
  Checks if a record has been soft-deleted.

  ## Examples

      if SoftDelete.deleted?(product) do
        IO.puts("Product was deleted")
      end
  """
  @spec deleted?(schema_struct()) :: boolean()
  def deleted?(%{deleted_at: deleted_at}) do
    not is_nil(deleted_at)
  end

  def deleted?(_), do: false

  @doc """
  Checks if a record is active (not soft-deleted).

  ## Examples

      if SoftDelete.active?(product) do
        IO.puts("Product is active")
      end
  """
  @spec active?(schema_struct()) :: boolean()
  def active?(struct) do
    not deleted?(struct)
  end

  ## Lifecycle Functions

  @doc """
  Soft deletes a record by setting `deleted_at` and optionally `deleted_by_urm_id`.

  ## Options

  - `:deleted_by` - User ID who performed the deletion

  ## Examples

      {:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: user_id)
  """
  @spec soft_delete(schema_struct(), keyword()) :: {:ok, schema_struct()} | {:error, Ecto.Changeset.t()}
  def soft_delete(%schema{} = struct, opts \\ []) do
    now = DateTime.utc_now()

    changes = %{deleted_at: now}

    changes =
      if deleted_by = Keyword.get(opts, :deleted_by) do
        Map.put(changes, :deleted_by_urm_id, deleted_by)
      else
        changes
      end

    struct
    |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
    |> Repo.update()
  end

  @doc """
  Soft deletes multiple records matching a query.

  ## Options

  - `:deleted_by` - User ID who performed the deletion

  ## Examples

      {:ok, %{count: 5}} = SoftDelete.soft_delete_all(
        Product |> where([p], p.status == "draft"),
        deleted_by: user_id
      )
  """
  @spec soft_delete_all(queryable(), keyword()) :: {:ok, map()} | {:error, any()}
  def soft_delete_all(query, opts \\ []) do
    now = DateTime.utc_now()

    updates = [deleted_at: now]

    updates =
      if deleted_by = Keyword.get(opts, :deleted_by) do
        [{:deleted_by_urm_id, deleted_by} | updates]
      else
        updates
      end

    query = from(q in query, update: [set: ^updates])

    case Repo.update_all(query, []) do
      {count, _} -> {:ok, %{count: count}}
      error -> {:error, error}
    end
  end

  @doc """
  Restores a soft-deleted record by clearing `deleted_at` and `deleted_by_urm_id`.

  ## Examples

      {:ok, restored} = SoftDelete.restore(product)
  """
  @spec restore(schema_struct()) :: {:ok, schema_struct()} | {:error, Ecto.Changeset.t()}
  def restore(%schema{} = struct) do
    changes = %{deleted_at: nil, deleted_by_urm_id: nil}

    struct
    |> Ecto.Changeset.cast(changes, [:deleted_at, :deleted_by_urm_id])
    |> Repo.update()
  end

  @doc """
  Restores multiple soft-deleted records matching a query.

  ## Examples

      {:ok, %{count: 3}} = SoftDelete.restore_all(
        Product |> where([p], p.type == "widget")
      )
  """
  @spec restore_all(queryable()) :: {:ok, map()} | {:error, any()}
  def restore_all(query) do
    updates = [deleted_at: nil, deleted_by_urm_id: nil]
    query = from(q in query, update: [set: ^updates])

    case Repo.update_all(query, []) do
      {count, _} -> {:ok, %{count: count}}
      error -> {:error, error}
    end
  end

  @doc """
  Permanently deletes a record from the database.

  Use with caution! This operation cannot be undone.

  ## Examples

      {:ok, deleted} = SoftDelete.hard_delete(product)
  """
  @spec hard_delete(schema_struct()) :: {:ok, schema_struct()} | {:error, Ecto.Changeset.t()}
  def hard_delete(%schema{} = struct) do
    Repo.delete(struct)
  end

  @doc """
  Permanently deletes multiple records matching a query.

  Use with caution! This operation cannot be undone.

  ## Examples

      {:ok, %{count: 10}} = SoftDelete.hard_delete_all(
        Product |> where([p], p.deleted_at < ago(90, "day"))
      )
  """
  @spec hard_delete_all(queryable()) :: {:ok, map()} | {:error, any()}
  def hard_delete_all(query) do
    case Repo.delete_all(query) do
      {count, _} -> {:ok, %{count: count}}
      error -> {:error, error}
    end
  end

  @doc """
  Permanently deletes soft-deleted records older than the specified duration.

  This is useful for cleanup jobs that purge old soft-deleted records.

  ## Examples

      # Delete records soft-deleted more than 90 days ago
      {:ok, %{count: count}} = SoftDelete.purge_deleted(Product, days: 90)

      # Delete records soft-deleted more than 1 year ago
      {:ok, %{count: count}} = SoftDelete.purge_deleted(Product, years: 1)
  """
  @spec purge_deleted(module(), keyword()) :: {:ok, map()} | {:error, any()}
  def purge_deleted(schema, opts \\ []) do
    cutoff = calculate_cutoff(opts)

    query =
      from q in schema,
        where: not is_nil(q.deleted_at),
        where: q.deleted_at < ^cutoff

    hard_delete_all(query)
  end

  ## Ecto.Multi Integration

  @doc """
  Adds a soft delete operation to an Ecto.Multi.

  ## Examples

      Multi.new()
      |> SoftDelete.multi_soft_delete(:delete_product, product, deleted_by: user_id)
      |> Repo.transaction()
  """
  @spec multi_soft_delete(Ecto.Multi.t(), atom(), schema_struct(), keyword()) :: Ecto.Multi.t()
  def multi_soft_delete(%Ecto.Multi{} = multi, name, struct, opts \\ []) do
    Ecto.Multi.run(multi, name, fn _repo, _changes ->
      soft_delete(struct, opts)
    end)
  end

  @doc """
  Adds a restore operation to an Ecto.Multi.

  ## Examples

      Multi.new()
      |> SoftDelete.multi_restore(:restore_product, product)
      |> Repo.transaction()
  """
  @spec multi_restore(Ecto.Multi.t(), atom(), schema_struct()) :: Ecto.Multi.t()
  def multi_restore(%Ecto.Multi{} = multi, name, struct) do
    Ecto.Multi.run(multi, name, fn _repo, _changes ->
      restore(struct)
    end)
  end

  ## Private Helpers

  defp calculate_cutoff(opts) do
    now = DateTime.utc_now()

    cond do
      days = Keyword.get(opts, :days) ->
        DateTime.add(now, -days * 24 * 60 * 60, :second)

      hours = Keyword.get(opts, :hours) ->
        DateTime.add(now, -hours * 60 * 60, :second)

      minutes = Keyword.get(opts, :minutes) ->
        DateTime.add(now, -minutes * 60, :second)

      weeks = Keyword.get(opts, :weeks) ->
        DateTime.add(now, -weeks * 7 * 24 * 60 * 60, :second)

      months = Keyword.get(opts, :months) ->
        DateTime.add(now, -months * 30 * 24 * 60 * 60, :second)

      years = Keyword.get(opts, :years) ->
        DateTime.add(now, -years * 365 * 24 * 60 * 60, :second)

      true ->
        # Default to 90 days
        DateTime.add(now, -90 * 24 * 60 * 60, :second)
    end
  end

  @doc """
  Returns statistics about soft-deleted records for a schema.

  ## Examples

      stats = SoftDelete.deletion_stats(Product)
      # => %{
      #   total: 100,
      #   active: 85,
      #   deleted: 15,
      #   deletion_rate: 0.15
      # }
  """
  @spec deletion_stats(module()) :: map()
  def deletion_stats(schema) do
    total = Repo.aggregate(schema, :count)
    deleted = Repo.aggregate(only_deleted(schema), :count)
    active = total - deleted

    %{
      total: total,
      active: active,
      deleted: deleted,
      deletion_rate: if(total > 0, do: deleted / total, else: 0.0)
    }
  end

  @doc """
  Returns the most recently deleted records for a schema.

  ## Options

  - `:limit` - Number of records to return (default: 10)

  ## Examples

      recent = SoftDelete.recently_deleted(Product, limit: 20)
  """
  @spec recently_deleted(module(), keyword()) :: [Ecto.Schema.t()]
  def recently_deleted(schema, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    schema
    |> only_deleted()
    |> order_by([q], desc: q.deleted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
