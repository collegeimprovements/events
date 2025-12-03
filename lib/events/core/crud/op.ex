defmodule Events.Core.Crud.Op do
  @moduledoc """
  Pure operation builders for CRUD operations.

  This module provides pure functions that build changesets and options
  without any side effects or database calls. It serves as the foundation
  for all CRUD operations.

  ## Changeset Resolution

  Changesets are resolved with the following priority:
  1. Explicit `:changeset` option
  2. Action-specific option (`:create_changeset`, `:update_changeset`)
  3. Schema's `@crud_changeset` attribute
  4. Schema's `changeset_for/2` callback
  5. Default `:changeset` function

  ## Usage

      # Build a changeset with resolved function
      changeset = Op.changeset(User, %{email: "test@example.com"})

      # Build with explicit changeset function
      changeset = Op.changeset(User, attrs, changeset: :registration_changeset)

      # Build insert options for upsert
      opts = Op.upsert_opts(conflict_target: :email, on_conflict: :replace_all)
  """

  @type changeset_opt ::
          {:changeset, atom()} | {:create_changeset, atom()} | {:update_changeset, atom()}
  @type action :: :create | :update | :delete

  # ─────────────────────────────────────────────────────────────
  # Changeset Builders
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build a changeset for a schema or struct with attributes.

  When given a schema module, builds a changeset for a new struct.
  When given an existing struct, builds a changeset for updating it.

  ## Options

  - `:changeset` - Explicit changeset function name
  - `:action` - The action type (`:create`, `:update`), affects function resolution

  ## Examples

      # From schema module (create)
      Op.changeset(User, %{email: "test@example.com"})
      Op.changeset(User, %{name: "Test"}, changeset: :profile_changeset)

      # From existing struct (update)
      Op.changeset(user, %{name: "Updated"})
      Op.changeset(user, %{role: :admin}, changeset: :admin_changeset)
  """
  @spec changeset(module() | struct(), map(), keyword()) :: Ecto.Changeset.t()
  def changeset(schema_or_struct, attrs, opts \\ [])

  def changeset(schema, attrs, opts) when is_atom(schema) do
    action = Keyword.get(opts, :action, :create)
    changeset_fn = resolve_changeset(schema, action, opts)
    struct = struct(schema)

    apply(schema, changeset_fn, [struct, attrs])
  end

  def changeset(%{__struct__: schema} = struct, attrs, opts) when is_map(attrs) do
    action = Keyword.get(opts, :action, :update)
    changeset_fn = resolve_changeset(schema, action, opts)

    apply(schema, changeset_fn, [struct, attrs])
  end

  @doc """
  Resolve the changeset function to use for an operation.

  Resolution priority:
  1. Explicit `:changeset` option
  2. Action-specific option (`:create_changeset`, `:update_changeset`)
  3. Schema's `@crud_changeset` attribute
  4. Schema's `changeset_for/2` callback
  5. Default `:changeset` function

  ## Examples

      Op.resolve_changeset(User, :create, [])
      #=> :changeset

      Op.resolve_changeset(User, :create, changeset: :registration_changeset)
      #=> :registration_changeset
  """
  @spec resolve_changeset(module(), action(), keyword()) :: atom()
  def resolve_changeset(schema, action, opts) do
    cond do
      # Explicit :changeset option
      changeset_fn = Keyword.get(opts, :changeset) ->
        changeset_fn

      # Action-specific option
      changeset_fn = Keyword.get(opts, action_changeset_key(action)) ->
        changeset_fn

      # Schema attribute @crud_changeset
      changeset_fn = get_schema_crud_changeset(schema) ->
        changeset_fn

      # Schema callback changeset_for/2
      function_exported?(schema, :changeset_for, 2) ->
        apply(schema, :changeset_for, [action, opts])

      # Default
      true ->
        :changeset
    end
  end

  defp action_changeset_key(:create), do: :create_changeset
  defp action_changeset_key(:update), do: :update_changeset
  defp action_changeset_key(:delete), do: :delete_changeset
  defp action_changeset_key(_), do: :changeset

  defp get_schema_crud_changeset(schema) do
    if function_exported?(schema, :__info__, 1) do
      schema.__info__(:attributes)
      |> Keyword.get(:crud_changeset)
      |> List.wrap()
      |> List.first()
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Insert Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build options for Repo.insert operations.

  Extracts and validates insert-specific options from the provided opts.

  ## Options

  - `:returning` - Fields to return, or `true` for all
  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable
  - `:on_conflict` - Conflict handling (for upsert)
  - `:conflict_target` - Conflict target columns
  - `:stale_error_field` - Field for stale error messages
  - `:stale_error_message` - Custom stale error message
  - `:allow_stale` - Don't error on stale operations (default: false)

  ## Examples

      Op.insert_opts(returning: true)
      Op.insert_opts(prefix: "tenant_123", timeout: 30_000)
  """
  @spec insert_opts(keyword()) :: keyword()
  def insert_opts(opts \\ []) do
    opts
    |> Keyword.take([
      :returning,
      :prefix,
      :timeout,
      :log,
      :on_conflict,
      :conflict_target,
      :stale_error_field,
      :stale_error_message,
      :allow_stale
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Build options for upsert (insert with conflict handling) operations.

  ## Options

  - `:conflict_target` - Column(s) to detect conflicts on (required)
  - `:on_conflict` - Action on conflict:
    - `:nothing` - Do nothing
    - `:replace_all` - Replace all fields
    - `{:replace, fields}` - Replace specific fields
    - `{:replace_all_except, fields}` - Replace all except specific fields
  - `:returning` - Fields to return
  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable
  - `:stale_error_field` - Field for stale error messages

  ## Examples

      Op.upsert_opts(conflict_target: :email, on_conflict: :replace_all)
      Op.upsert_opts(
        conflict_target: [:org_id, :email],
        on_conflict: {:replace, [:name, :updated_at]},
        timeout: 60_000
      )
  """
  @spec upsert_opts(keyword()) :: keyword()
  def upsert_opts(opts) do
    conflict_target = Keyword.fetch!(opts, :conflict_target)
    on_conflict = Keyword.get(opts, :on_conflict, :nothing)

    base_opts = [
      conflict_target: normalize_conflict_target(conflict_target),
      on_conflict: normalize_on_conflict(on_conflict)
    ]

    base_opts
    |> maybe_add_returning(opts)
    |> maybe_add_prefix(opts)
    |> maybe_add_timeout(opts)
    |> maybe_add_log(opts)
    |> maybe_add_stale_error_field(opts)
  end

  defp normalize_conflict_target(target) when is_atom(target), do: [target]
  defp normalize_conflict_target(targets) when is_list(targets), do: targets
  defp normalize_conflict_target({:constraint, name}), do: {:constraint, name}

  defp normalize_on_conflict(:nothing), do: :nothing
  defp normalize_on_conflict(:replace_all), do: :replace_all
  defp normalize_on_conflict({:replace, fields}) when is_list(fields), do: {:replace, fields}

  defp normalize_on_conflict({:replace_all_except, fields}) when is_list(fields) do
    {:replace_all_except, fields}
  end

  defp normalize_on_conflict(query) when is_struct(query), do: query

  defp maybe_add_returning(opts, source) do
    case Keyword.get(source, :returning) do
      nil -> opts
      value -> Keyword.put(opts, :returning, value)
    end
  end

  defp maybe_add_prefix(opts, source) do
    case Keyword.get(source, :prefix) do
      nil -> opts
      value -> Keyword.put(opts, :prefix, value)
    end
  end

  defp maybe_add_timeout(opts, source) do
    case Keyword.get(source, :timeout) do
      nil -> opts
      value -> Keyword.put(opts, :timeout, value)
    end
  end

  defp maybe_add_log(opts, source) do
    case Keyword.get(source, :log) do
      nil -> opts
      value -> Keyword.put(opts, :log, value)
    end
  end

  defp maybe_add_stale_error_field(opts, source) do
    case Keyword.get(source, :stale_error_field) do
      nil -> opts
      value -> Keyword.put(opts, :stale_error_field, value)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Update Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build options for Repo.update operations.

  ## Options

  - `:returning` - Fields to return
  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable
  - `:force` - Fields to mark as changed even if value is same
  - `:stale_error_field` - Field for stale error messages
  - `:stale_error_message` - Custom stale error message
  - `:allow_stale` - Don't error on stale operations (default: false)

  ## Examples

      Op.update_opts(returning: true)
      Op.update_opts(timeout: 30_000, force: [:updated_at])
  """
  @spec update_opts(keyword()) :: keyword()
  def update_opts(opts \\ []) do
    opts
    |> Keyword.take([
      :returning,
      :prefix,
      :timeout,
      :log,
      :force,
      :stale_error_field,
      :stale_error_message,
      :allow_stale
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ─────────────────────────────────────────────────────────────
  # Delete Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build options for Repo.delete operations.

  ## Options

  - `:returning` - Fields to return after deletion
  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable
  - `:stale_error_field` - Field for stale error messages
  - `:stale_error_message` - Custom stale error message
  - `:allow_stale` - Don't error on stale operations (default: false)

  ## Examples

      Op.delete_opts(prefix: "tenant_123")
      Op.delete_opts(timeout: 30_000, returning: true)
  """
  @spec delete_opts(keyword()) :: keyword()
  def delete_opts(opts \\ []) do
    opts
    |> Keyword.take([
      :returning,
      :prefix,
      :timeout,
      :log,
      :stale_error_field,
      :stale_error_message,
      :allow_stale
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ─────────────────────────────────────────────────────────────
  # Query Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build options for Repo.all/one operations.

  ## Options

  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable

  ## Examples

      Op.query_opts(prefix: "tenant_123", timeout: 15_000)
      Op.query_opts(log: false)  # Disable query logging
  """
  @spec query_opts(keyword()) :: keyword()
  def query_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ─────────────────────────────────────────────────────────────
  # Bulk Operation Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build options for Repo.insert_all operations.

  ## Options

  - `:returning` - Fields to return, or `true` for all
  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds (useful for large batches)
  - `:log` - Logger level or `false` to disable
  - `:on_conflict` - Conflict handling
  - `:conflict_target` - Conflict target columns
  - `:placeholders` - Map of reusable values to reduce data transmission

  ## Placeholders

  Placeholders reduce data transfer when inserting many entries with repeated values.
  Pass a map via `:placeholders` and reference values with `{:placeholder, key}`:

      placeholders = %{now: DateTime.utc_now()}
      entries = [
        %{name: "A", inserted_at: {:placeholder, :now}},
        %{name: "B", inserted_at: {:placeholder, :now}}
      ]
      Op.insert_all_opts(placeholders: placeholders)

  ## Examples

      Op.insert_all_opts(returning: true)
      Op.insert_all_opts(
        conflict_target: :email,
        on_conflict: {:replace, [:name]},
        returning: [:id, :email],
        timeout: 120_000  # 2 minutes for large batch
      )
  """
  @spec insert_all_opts(keyword()) :: keyword()
  def insert_all_opts(opts \\ []) do
    opts
    |> Keyword.take([
      :returning,
      :prefix,
      :timeout,
      :log,
      :on_conflict,
      :conflict_target,
      :placeholders
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> maybe_normalize_conflict(opts)
  end

  defp maybe_normalize_conflict(result, opts) do
    case Keyword.get(opts, :conflict_target) do
      nil ->
        result

      target ->
        result
        |> Keyword.put(:conflict_target, normalize_conflict_target(target))
        |> Keyword.update(:on_conflict, :nothing, &normalize_on_conflict/1)
    end
  end

  @doc """
  Build options for Repo.update_all operations.

  ## Options

  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable
  - `:returning` - Fields to return

  ## Examples

      Op.update_all_opts(returning: [:id, :status])
      Op.update_all_opts(timeout: 60_000, returning: true)
  """
  @spec update_all_opts(keyword()) :: keyword()
  def update_all_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log, :returning])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Build options for Repo.delete_all operations.

  ## Options

  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout in milliseconds
  - `:log` - Logger level or `false` to disable
  - `:returning` - Fields to return

  ## Examples

      Op.delete_all_opts(returning: true)
      Op.delete_all_opts(timeout: 60_000, log: false)
  """
  @spec delete_all_opts(keyword()) :: keyword()
  def delete_all_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log, :returning])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ─────────────────────────────────────────────────────────────
  # Preload Helpers
  # ─────────────────────────────────────────────────────────────

  @doc """
  Extract preload configuration from options.

  Returns the preload spec or an empty list if not specified.

  ## Examples

      Op.preloads([preload: [:account, :memberships]])
      #=> [:account, :memberships]

      Op.preloads([])
      #=> []
  """
  @spec preloads(keyword()) :: [atom()] | keyword()
  def preloads(opts) do
    Keyword.get(opts, :preload, [])
  end

  # ─────────────────────────────────────────────────────────────
  # Repo Resolution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Resolve the repo to use for operations.

  Allows passing a custom `:repo` option to use a different repo
  than the default. Useful for applications with multiple repos.

  ## Examples

      Op.repo([])
      #=> Events.Core.Repo

      Op.repo(repo: MyApp.ReadOnlyRepo)
      #=> MyApp.ReadOnlyRepo
  """
  @spec repo(keyword()) :: module()
  def repo(opts) do
    Keyword.get(opts, :repo, Events.Core.Repo)
  end

  @doc """
  Extract SQL/Repo options from the full options list.

  Returns options that should be passed to Repo operations,
  excluding CRUD-specific options like :changeset, :preload, :repo.

  ## Examples

      Op.sql_opts(timeout: 30_000, prefix: "tenant_1", changeset: :custom)
      #=> [timeout: 30_000, prefix: "tenant_1"]
  """
  @spec sql_opts(keyword()) :: keyword()
  def sql_opts(opts) do
    opts
    |> Keyword.take([:timeout, :prefix, :log])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end
end
