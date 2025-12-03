defmodule Events.Core.Crud do
  @moduledoc """
  Unified CRUD execution API.

  Provides a consistent interface for executing all CRUD operations.
  All write operations use Multi internally for future audit integration.

  ## Design Principles

  - **Unified execution** - `run/1` works with any Executable token
  - **Explicit** - Tokens are data, execution is a separate step
  - **Result tuples** - All operations return `{:ok, result}` or `{:error, reason}`
  - **Composable** - Build complex operations from simple parts

  ## Token Execution

      # Multi transactions
      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Crud.run()

      # Merge operations
      User
      |> Merge.new(data)
      |> Merge.match_on(:email)
      |> Crud.run()

      # Query execution
      User
      |> Query.new()
      |> Query.where(:active, true)
      |> Crud.run()

  ## Convenience Functions

  For simple operations, use the convenience functions:

      Crud.create(User, attrs)
      Crud.fetch(User, id)
      Crud.update(user, attrs)
      Crud.delete(user)
  """

  alias Events.Core.Crud.{Op, Multi, Merge, Validatable}

  # ─────────────────────────────────────────────────────────────
  # Unified Execution API
  # ─────────────────────────────────────────────────────────────

  @doc """
  Execute any Executable token.

  This is the primary entry point for executing CRUD operations.
  Works with Multi, Merge, and Query tokens.

  ## Examples

      # Execute a Multi
      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Crud.run()

      # Execute a Merge
      User
      |> Merge.new(data)
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update)
      |> Crud.run()
  """
  @spec run(struct(), keyword()) :: {:ok, any()} | {:error, any()}
  def run(token, opts \\ [])

  def run(%Multi{} = multi, opts) do
    transaction(multi, opts)
  end

  def run(%Merge{} = merge, opts) do
    execute_merge(merge, opts)
  end

  # For Query.Token - will be implemented when Query integration is added
  def run(token, opts) when is_struct(token) do
    # Check if the token implements Executable protocol
    if function_exported?(Events.Core.Crud.Executable, :execute, 2) do
      Events.Core.Crud.Executable.execute(token, opts)
    else
      {:error, {:not_executable, token}}
    end
  end

  @doc """
  Alias for `run/2` for pipe-friendliness.
  """
  @spec execute(struct(), keyword()) :: {:ok, any()} | {:error, any()}
  defdelegate execute(token, opts \\ []), to: __MODULE__, as: :run

  # ─────────────────────────────────────────────────────────────
  # Transaction Execution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Execute a Multi or function returning Multi as a transaction.

  All operations in the Multi are executed atomically.
  If any operation fails, all previous operations are rolled back.

  ## Options

  - `:repo` - Custom repo module (defaults to Events.Core.Repo)
  - `:timeout` - Transaction timeout in milliseconds
  - `:prefix` - Database schema prefix
  - `:log` - Log level for queries (false to disable)

  ## Returns

  - `{:ok, results}` - Map of operation names to results
  - `{:error, failed_operation, failed_value, changes_so_far}` - Transaction failed

  ## Examples

      # Direct Multi
      multi =
        Multi.new()
        |> Multi.create(:user, User, user_attrs)
        |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)

      {:ok, %{user: user, account: account}} = Crud.transaction(multi)

      # With custom timeout for long operations
      Crud.transaction(multi, timeout: 60_000)

      # With custom repo
      Crud.transaction(multi, repo: MyApp.ReadOnlyRepo)

      # Lazy Multi via function
      Crud.transaction(fn ->
        Multi.new()
        |> Multi.create(:user, User, attrs)
      end)
  """
  @spec transaction(Multi.t() | (-> Multi.t()), keyword()) ::
          {:ok, map()} | {:error, atom(), any(), map()}
  def transaction(multi_or_fun, opts \\ [])

  def transaction(%Multi{} = multi, opts) do
    with :ok <- validate_token(multi) do
      repo = Op.repo(opts)
      sql_opts = Op.sql_opts(opts)
      ecto_multi = Multi.to_ecto_multi(multi)
      repo.transaction(ecto_multi, sql_opts)
    end
  end

  def transaction(fun, opts) when is_function(fun, 0) do
    transaction(fun.(), opts)
  end

  # ─────────────────────────────────────────────────────────────
  # Merge Execution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Execute a Merge token.

  This executes the PostgreSQL MERGE operation and returns the affected rows.

  ## Options

  - `:timeout` - Query timeout
  - `:prefix` - Database schema prefix

  ## Returns

  - `{:ok, results}` - List of affected records (if returning is enabled)
  - `{:error, reason}` - Operation failed
  """
  @spec execute_merge(Merge.t(), keyword()) :: {:ok, [struct()]} | {:error, any()}
  def execute_merge(%Merge{} = merge, opts \\ []) do
    with :ok <- validate_token(merge) do
      repo = Op.repo(opts)
      sql_opts = Op.sql_opts(opts)
      {sql, params} = Merge.to_sql(merge)

      case repo.query(sql, params, sql_opts) do
        {:ok, %{rows: rows, columns: columns}} ->
          {:ok, rows_to_structs(merge.schema, columns, rows)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp rows_to_structs(schema, columns, rows) do
    fields = Enum.map(columns, &String.to_existing_atom/1)

    Enum.map(rows, fn row ->
      attrs = Enum.zip(fields, row) |> Map.new()
      struct(schema, attrs)
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Single Record Convenience Functions
  # ─────────────────────────────────────────────────────────────

  @doc """
  Create a new record.

  Uses Multi internally for audit integration.

  ## Options

  - `:changeset` - Changeset function name
  - `:preload` - Associations to preload after creation

  ## Examples

      {:ok, user} = Crud.create(User, %{email: "test@example.com"})
      {:ok, user} = Crud.create(User, attrs, changeset: :registration_changeset)
  """
  @spec create(module(), map(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def create(schema, attrs, opts \\ []) when is_atom(schema) and is_map(attrs) do
    Multi.new()
    |> Multi.create(:record, schema, attrs, opts)
    |> transaction(opts)
    |> unwrap_single(:record, schema, opts)
  end

  @doc """
  Update an existing record.

  Accepts either a struct or {schema, id} tuple.

  ## Examples

      {:ok, user} = Crud.update(user, %{name: "Updated"})
      {:ok, user} = Crud.update(User, user_id, %{name: "Updated"})
  """
  @spec update(struct(), map(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def update(%{__struct__: schema} = struct, attrs, opts \\ []) when is_map(attrs) do
    Multi.new()
    |> Multi.update(:record, struct, attrs, opts)
    |> transaction(opts)
    |> unwrap_single(:record, schema, opts)
  end

  @spec update(module(), binary(), map(), keyword()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t() | :not_found}
  def update(schema, id, attrs, opts) when is_atom(schema) and is_binary(id) and is_map(attrs) do
    Multi.new()
    |> Multi.update(:record, {schema, id}, attrs, opts)
    |> transaction(opts)
    |> unwrap_single(:record, schema, opts)
  end

  @doc """
  Delete a record.

  ## Examples

      {:ok, user} = Crud.delete(user)
      {:ok, user} = Crud.delete(User, user_id)
  """
  @spec delete(struct(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def delete(%{__struct__: schema} = struct, opts \\ []) do
    Multi.new()
    |> Multi.delete(:record, struct, opts)
    |> transaction(opts)
    |> unwrap_single(:record, schema, opts)
  end

  @spec delete(module(), binary(), keyword()) :: {:ok, struct()} | {:error, :not_found}
  def delete(schema, id, opts) when is_atom(schema) and is_binary(id) do
    Multi.new()
    |> Multi.delete(:record, {schema, id}, opts)
    |> transaction(opts)
    |> unwrap_single(:record, schema, opts)
  end

  # ─────────────────────────────────────────────────────────────
  # Read Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Fetch a record by ID, returning `{:ok, record}` or `{:error, :not_found}`.

  ## Options

  - `:preload` - Associations to preload

  ## Examples

      {:ok, user} = Crud.fetch(User, id)
      {:ok, user} = Crud.fetch(User, id, preload: [:account])

      # Using Query token
      {:ok, user} =
        User
        |> Query.new()
        |> Query.where(:email, email)
        |> Crud.fetch()
  """
  @spec fetch(module() | struct(), binary() | keyword(), keyword()) ::
          {:ok, struct()} | {:error, :not_found}
  def fetch(schema_or_token, id_or_opts \\ [], opts \\ [])

  def fetch(schema, id, opts) when is_atom(schema) and is_binary(id) do
    repo = Op.repo(opts)
    query_opts = Op.query_opts(opts)
    preloads = Op.preloads(opts)

    case repo.get(schema, id, query_opts) do
      nil ->
        {:error, :not_found}

      record ->
        record = maybe_preload(record, preloads, repo)
        {:ok, record}
    end
  end

  def fetch(query_token, opts, _) when is_struct(query_token) and is_list(opts) do
    run(query_token, Keyword.put(opts, :mode, :one))
  end

  @doc """
  Get a record by ID or using a Query token, returning the record or nil.

  ## Examples

      user = Crud.get(User, id)
      user = Crud.get(User, id, preload: [:account])

      # Using Query token
      user =
        User
        |> Query.new()
        |> Query.where(:email, email)
        |> Crud.get()
  """
  @spec get(module() | struct(), binary() | keyword(), keyword()) :: struct() | nil
  def get(schema_or_token, id_or_opts \\ [], opts \\ [])

  def get(schema, id, opts) when is_atom(schema) and is_binary(id) do
    repo = Op.repo(opts)
    query_opts = Op.query_opts(opts)
    preloads = Op.preloads(opts)

    case repo.get(schema, id, query_opts) do
      nil -> nil
      record -> maybe_preload(record, preloads, repo)
    end
  end

  def get(query_token, opts, _) when is_struct(query_token) and is_list(opts) do
    case fetch(query_token, opts) do
      {:ok, record} -> record
      {:error, :not_found} -> nil
    end
  end

  @doc """
  Check if a record exists.

  ## Options

  - `:repo` - Custom repo module
  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout

  ## Examples

      true = Crud.exists?(User, user_id)
      false = Crud.exists?(User, "nonexistent")
      Crud.exists?(User, id, repo: MyApp.ReadOnlyRepo)
  """
  @spec exists?(module(), binary(), keyword()) :: boolean()
  def exists?(schema, id, opts \\ []) when is_atom(schema) and is_binary(id) do
    repo = Op.repo(opts)
    query_opts = Op.query_opts(opts)
    repo.exists?(schema, [id: id] ++ query_opts)
  end

  @spec exists?(struct()) :: boolean()
  def exists?(query_token) when is_struct(query_token) do
    case run(query_token, mode: :exists) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  @doc """
  Fetch all records matching a Query token.

  ## Examples

      {:ok, users} =
        User
        |> Query.new()
        |> Query.where(:status, :active)
        |> Crud.fetch_all()
  """
  @spec fetch_all(struct(), keyword()) :: {:ok, [struct()]}
  def fetch_all(query_token, opts \\ []) when is_struct(query_token) do
    run(query_token, Keyword.put(opts, :mode, :all))
  end

  @doc """
  Count records matching a Query token.

  ## Examples

      count =
        User
        |> Query.new()
        |> Query.where(:status, :active)
        |> Crud.count()
  """
  @spec count(struct()) :: non_neg_integer()
  def count(query_token) when is_struct(query_token) do
    case run(query_token, mode: :count) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Bulk Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Create multiple records in a single transaction.

  ## Options

  - `:returning` - Fields to return
  - `:changeset` - Changeset function for validation

  ## Examples

      {:ok, users} = Crud.create_all(User, [
        %{email: "a@test.com"},
        %{email: "b@test.com"}
      ])
  """
  @spec create_all(module(), [map()], keyword()) :: {:ok, [struct()]} | {:error, any()}
  def create_all(schema, list_of_attrs, opts \\ [])
      when is_atom(schema) and is_list(list_of_attrs) do
    Multi.new()
    |> Multi.create_all(:records, schema, list_of_attrs, opts)
    |> transaction(opts)
    |> case do
      {:ok, %{records: {_count, records}}} -> {:ok, records || []}
      {:error, :records, reason, _} -> {:error, reason}
      error -> error
    end
  end

  @doc """
  Upsert multiple records in a single transaction.

  ## Options

  - `:conflict_target` - Column(s) for conflict detection
  - `:on_conflict` - Action on conflict
  - `:returning` - Fields to return

  ## Examples

      {:ok, users} = Crud.upsert_all(User, users_data,
        conflict_target: :email,
        on_conflict: {:replace, [:name]}
      )
  """
  @spec upsert_all(module(), [map()], keyword()) :: {:ok, [struct()]}
  def upsert_all(schema, list_of_attrs, opts)
      when is_atom(schema) and is_list(list_of_attrs) do
    Multi.new()
    |> Multi.upsert_all(:records, schema, list_of_attrs, opts)
    |> transaction(opts)
    |> case do
      {:ok, %{records: {_count, records}}} -> {:ok, records || []}
      {:error, :records, reason, _} -> {:error, reason}
      error -> error
    end
  end

  @doc """
  Update all records matching a query.

  ## Examples

      {:ok, count} =
        User
        |> Query.new()
        |> Query.where(:status, :inactive)
        |> Crud.update_all(set: [archived_at: DateTime.utc_now()])
  """
  @spec update_all(struct(), keyword(), keyword()) :: {:ok, non_neg_integer()}
  def update_all(query_token, updates, opts \\ []) when is_struct(query_token) do
    Multi.new()
    |> Multi.update_all(:update, query_to_ecto(query_token), updates, opts)
    |> transaction(opts)
    |> case do
      {:ok, %{update: {count, _}}} -> {:ok, count}
      {:error, :update, reason, _} -> {:error, reason}
      error -> error
    end
  end

  @doc """
  Delete all records matching a query.

  ## Examples

      {:ok, count} =
        Token
        |> Query.new()
        |> Query.where(:expired_at, :<, DateTime.utc_now())
        |> Crud.delete_all()
  """
  @spec delete_all(struct(), keyword()) :: {:ok, non_neg_integer()}
  def delete_all(query_token, opts \\ []) when is_struct(query_token) do
    Multi.new()
    |> Multi.delete_all(:delete, query_to_ecto(query_token), opts)
    |> transaction(opts)
    |> case do
      {:ok, %{delete: {count, _}}} -> {:ok, count}
      {:error, :delete, reason, _} -> {:error, reason}
      error -> error
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp validate_token(token) do
    case Validatable.validate(token) do
      :ok -> :ok
      {:error, errors} -> {:error, {:invalid_token, errors}}
    end
  end

  defp unwrap_single({:ok, %{record: record}}, _name, _schema, opts) do
    repo = Op.repo(opts)
    record = maybe_preload(record, Op.preloads(opts), repo)
    {:ok, record}
  end

  defp unwrap_single({:error, :record, %Ecto.Changeset{} = changeset, _}, _name, _schema, _opts) do
    {:error, changeset}
  end

  defp unwrap_single({:error, :record, :not_found, _}, _name, _schema, _opts) do
    {:error, :not_found}
  end

  defp unwrap_single({:error, failed_name, reason, _changes}, failed_name, _schema, _opts) do
    {:error, reason}
  end

  defp maybe_preload(record, [], _repo), do: record
  defp maybe_preload(record, preloads, repo), do: repo.preload(record, preloads)

  # Convert Query token to Ecto.Query
  # This will be properly implemented with Query integration
  defp query_to_ecto(query_token) when is_struct(query_token) do
    if function_exported?(query_token.__struct__, :to_query, 1) do
      query_token.__struct__.to_query(query_token)
    else
      raise ArgumentError, "Token #{inspect(query_token.__struct__)} does not implement to_query/1"
    end
  end
end
