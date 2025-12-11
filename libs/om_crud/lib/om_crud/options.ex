defmodule OmCrud.Options do
  @moduledoc """
  Unified option handling for CRUD operations.

  This module provides a single source of truth for all CRUD options,
  including extraction, validation, and normalization.

  ## Option Categories

  Options are organized into categories based on operation type:

  - **Common** - Available to all operations: `:repo`, `:prefix`, `:timeout`, `:log`
  - **Write** - For insert/update/delete: `:returning`, `:stale_error_field`, `:stale_error_message`, `:allow_stale`
  - **Changeset** - For changesets: `:changeset`, `:create_changeset`, `:update_changeset`
  - **Update** - Update-specific: `:force`
  - **Bulk** - For bulk operations: `:placeholders`, `:conflict_target`, `:on_conflict`
  - **Read** - For queries: `:preload`

  ## Usage

      # Extract options for a specific operation type
      opts = Options.extract(all_opts, :insert)

      # Validate options before execution
      {:ok, opts} = Options.validate(opts, :insert_all)

      # Normalize conflict options
      opts = Options.normalize(opts)

  ## Operation Types

  - `:insert` - Single record insert
  - `:update` - Single record update
  - `:delete` - Single record delete
  - `:insert_all` - Bulk insert
  - `:update_all` - Bulk update
  - `:delete_all` - Bulk delete
  - `:upsert` - Insert with conflict handling
  - `:query` - Read operations
  - `:merge` - PostgreSQL MERGE
  """

  @type operation ::
          :insert
          | :update
          | :delete
          | :insert_all
          | :update_all
          | :delete_all
          | :upsert
          | :query
          | :merge

  # ─────────────────────────────────────────────────────────────
  # Option Definitions
  # ─────────────────────────────────────────────────────────────

  # Common options available to all operations
  @common_opts [:repo, :prefix, :timeout, :log]

  # Write operation options
  @write_opts [:returning, :stale_error_field, :stale_error_message, :allow_stale]

  # Changeset resolution options
  @changeset_opts [:changeset, :create_changeset, :update_changeset, :delete_changeset, :action]

  # Update-specific options
  @update_extra_opts [:force]

  # Bulk operation options
  @bulk_opts [:placeholders, :conflict_target, :on_conflict]

  # Read operation options
  @read_opts [:preload]

  # Options passed to Ecto.Repo operations (exclude CRUD-specific ones)
  @repo_passthrough_opts [
    :returning,
    :prefix,
    :timeout,
    :log,
    :on_conflict,
    :conflict_target,
    :stale_error_field,
    :stale_error_message,
    :allow_stale,
    :force,
    :placeholders
  ]

  # ─────────────────────────────────────────────────────────────
  # Option Sets by Operation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Returns the list of valid options for an operation type.

  ## Examples

      Options.valid_opts(:insert)
      #=> [:repo, :prefix, :timeout, :log, :returning, ...]

      Options.valid_opts(:query)
      #=> [:repo, :prefix, :timeout, :log, :preload]
  """
  @spec valid_opts(operation()) :: [atom()]
  def valid_opts(:insert), do: @common_opts ++ @write_opts ++ @changeset_opts ++ @bulk_opts
  def valid_opts(:update), do: @common_opts ++ @write_opts ++ @changeset_opts ++ @update_extra_opts
  def valid_opts(:delete), do: @common_opts ++ @write_opts
  def valid_opts(:insert_all), do: @common_opts ++ [:returning] ++ @bulk_opts
  def valid_opts(:update_all), do: @common_opts ++ [:returning]
  def valid_opts(:delete_all), do: @common_opts ++ [:returning]
  def valid_opts(:upsert), do: @common_opts ++ @write_opts ++ @bulk_opts
  def valid_opts(:query), do: @common_opts ++ @read_opts
  def valid_opts(:merge), do: @common_opts

  # ─────────────────────────────────────────────────────────────
  # Extraction
  # ─────────────────────────────────────────────────────────────

  @doc """
  Extract options relevant to an operation type.

  Filters the provided options to only include those valid for the operation,
  and removes nil values.

  ## Examples

      opts = [repo: MyRepo, timeout: 5000, preload: [:account], changeset: :custom]

      Options.extract(opts, :insert)
      #=> [repo: MyRepo, timeout: 5000, changeset: :custom]

      Options.extract(opts, :query)
      #=> [repo: MyRepo, timeout: 5000, preload: [:account]]
  """
  @spec extract(keyword(), operation()) :: keyword()
  def extract(opts, operation) when is_list(opts) and is_atom(operation) do
    valid = valid_opts(operation)

    opts
    |> Keyword.take(valid)
    |> reject_nil_values()
  end

  @doc """
  Extract options that should be passed to Ecto.Repo operations.

  This excludes CRUD-specific options like `:repo`, `:preload`, `:changeset`.

  ## Examples

      opts = [timeout: 5000, prefix: "tenant_1", preload: [:account], repo: MyRepo]

      Options.repo_opts(opts)
      #=> [timeout: 5000, prefix: "tenant_1"]
  """
  @spec repo_opts(keyword()) :: keyword()
  def repo_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take(@repo_passthrough_opts)
    |> reject_nil_values()
  end

  @doc """
  Extract SQL/transaction options (subset of repo_opts).

  Used for transaction-level configuration.

  ## Examples

      Options.sql_opts([timeout: 5000, prefix: "tenant_1", changeset: :custom])
      #=> [timeout: 5000, prefix: "tenant_1"]
  """
  @spec sql_opts(keyword()) :: keyword()
  def sql_opts(opts) when is_list(opts) do
    opts
    |> Keyword.take([:timeout, :prefix, :log])
    |> reject_nil_values()
  end

  # ─────────────────────────────────────────────────────────────
  # Normalization
  # ─────────────────────────────────────────────────────────────

  @doc """
  Normalize options, particularly conflict handling.

  - Converts single atom `:conflict_target` to list
  - Normalizes `:on_conflict` values

  ## Examples

      Options.normalize([conflict_target: :email, on_conflict: :replace_all])
      #=> [conflict_target: [:email], on_conflict: :replace_all]
  """
  @spec normalize(keyword()) :: keyword()
  def normalize(opts) when is_list(opts) do
    opts
    |> normalize_conflict_target()
    |> normalize_on_conflict()
  end

  defp normalize_conflict_target(opts) do
    case Keyword.get(opts, :conflict_target) do
      nil -> opts
      target when is_atom(target) -> Keyword.put(opts, :conflict_target, [target])
      targets when is_list(targets) -> opts
      {:constraint, _} = constraint -> Keyword.put(opts, :conflict_target, constraint)
    end
  end

  defp normalize_on_conflict(opts) do
    case Keyword.get(opts, :on_conflict) do
      nil -> opts
      :nothing -> opts
      :replace_all -> opts
      {:replace, fields} when is_list(fields) -> opts
      {:replace_all_except, fields} when is_list(fields) -> opts
      query when is_struct(query) -> opts
      # Default to :nothing for invalid values
      _ -> Keyword.put(opts, :on_conflict, :nothing)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Validation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Validate options for an operation type.

  Returns `{:ok, opts}` if valid, or `{:error, reasons}` with validation errors.

  ## Validations

  - `:conflict_target` is required for upsert operations
  - `:timeout` must be a positive integer
  - `:preload` must be a list

  ## Examples

      Options.validate([timeout: 5000], :insert)
      #=> {:ok, [timeout: 5000]}

      Options.validate([], :upsert)
      #=> {:error, ["conflict_target is required for upsert operations"]}
  """
  @spec validate(keyword(), operation()) :: {:ok, keyword()} | {:error, [String.t()]}
  def validate(opts, operation) when is_list(opts) and is_atom(operation) do
    errors =
      []
      |> validate_required_opts(opts, operation)
      |> validate_timeout(opts)
      |> validate_preload(opts)
      |> validate_conflict_target(opts, operation)
      |> validate_returning(opts)

    case errors do
      [] -> {:ok, opts}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp validate_required_opts(errors, opts, :upsert) do
    if Keyword.has_key?(opts, :conflict_target) do
      errors
    else
      ["conflict_target is required for upsert operations" | errors]
    end
  end

  defp validate_required_opts(errors, _opts, _operation), do: errors

  defp validate_timeout(errors, opts) do
    case Keyword.get(opts, :timeout) do
      nil -> errors
      timeout when is_integer(timeout) and timeout > 0 -> errors
      _ -> ["timeout must be a positive integer" | errors]
    end
  end

  defp validate_preload(errors, opts) do
    case Keyword.get(opts, :preload) do
      nil -> errors
      preload when is_list(preload) -> errors
      preload when is_atom(preload) -> errors
      _ -> ["preload must be a list of associations or an atom" | errors]
    end
  end

  defp validate_conflict_target(errors, opts, operation) when operation in [:insert_all, :upsert] do
    case Keyword.get(opts, :conflict_target) do
      nil -> errors
      target when is_atom(target) -> errors
      targets when is_list(targets) -> errors
      {:constraint, name} when is_atom(name) or is_binary(name) -> errors
      _ -> ["conflict_target must be an atom, list of atoms, or {:constraint, name}" | errors]
    end
  end

  defp validate_conflict_target(errors, _opts, _operation), do: errors

  defp validate_returning(errors, opts) do
    case Keyword.get(opts, :returning) do
      nil -> errors
      true -> errors
      false -> errors
      fields when is_list(fields) -> errors
      _ -> ["returning must be true, false, or a list of fields" | errors]
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Specific Option Accessors
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the repo module from options, defaulting to the configured default_repo.

  ## Examples

      Options.repo([repo: MyApp.Repo])
      #=> MyApp.Repo

      Options.repo([])
      #=> <configured default_repo>
  """
  @spec repo(keyword()) :: module()
  def repo(opts) when is_list(opts) do
    Keyword.get_lazy(opts, :repo, &OmCrud.Config.default_repo/0)
  end

  @doc """
  Get preload configuration from options.

  ## Examples

      Options.preloads([preload: [:account, :memberships]])
      #=> [:account, :memberships]

      Options.preloads([])
      #=> []
  """
  @spec preloads(keyword()) :: [atom()] | keyword()
  def preloads(opts) when is_list(opts) do
    Keyword.get(opts, :preload, [])
  end

  @doc """
  Get timeout from options.

  ## Examples

      Options.timeout([timeout: 30_000])
      #=> 30_000

      Options.timeout([])
      #=> nil
  """
  @spec timeout(keyword()) :: non_neg_integer() | nil
  def timeout(opts) when is_list(opts) do
    Keyword.get(opts, :timeout)
  end

  @doc """
  Get prefix from options.

  ## Examples

      Options.prefix([prefix: "tenant_123"])
      #=> "tenant_123"
  """
  @spec prefix(keyword()) :: String.t() | nil
  def prefix(opts) when is_list(opts) do
    Keyword.get(opts, :prefix)
  end

  # ─────────────────────────────────────────────────────────────
  # Operation-Specific Extractors (for backward compatibility)
  # ─────────────────────────────────────────────────────────────

  @doc """
  Extract options for insert operations.

  ## Examples

      Options.insert_opts([returning: true, preload: [:account]])
      #=> [returning: true]
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
    |> reject_nil_values()
  end

  @doc """
  Extract options for upsert operations.

  Requires `:conflict_target` and normalizes conflict handling.

  ## Examples

      Options.upsert_opts([conflict_target: :email, on_conflict: :replace_all])
      #=> [conflict_target: [:email], on_conflict: :replace_all]
  """
  @spec upsert_opts(keyword()) :: keyword()
  def upsert_opts(opts) do
    conflict_target = Keyword.fetch!(opts, :conflict_target)
    on_conflict = Keyword.get(opts, :on_conflict, :nothing)

    [
      conflict_target: normalize_conflict_target_value(conflict_target),
      on_conflict: on_conflict
    ]
    |> maybe_add_opt(:returning, opts)
    |> maybe_add_opt(:prefix, opts)
    |> maybe_add_opt(:timeout, opts)
    |> maybe_add_opt(:log, opts)
    |> maybe_add_opt(:stale_error_field, opts)
  end

  @doc """
  Extract options for update operations.

  ## Examples

      Options.update_opts([force: [:updated_at], timeout: 5000])
      #=> [force: [:updated_at], timeout: 5000]
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
    |> reject_nil_values()
  end

  @doc """
  Extract options for delete operations.

  ## Examples

      Options.delete_opts([returning: true])
      #=> [returning: true]
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
    |> reject_nil_values()
  end

  @doc """
  Extract options for query/read operations.

  ## Examples

      Options.query_opts([prefix: "tenant_1", preload: [:account]])
      #=> [prefix: "tenant_1"]
  """
  @spec query_opts(keyword()) :: keyword()
  def query_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log])
    |> reject_nil_values()
  end

  @doc """
  Extract options for insert_all operations.

  ## Examples

      Options.insert_all_opts([placeholders: %{now: DateTime.utc_now()}, returning: true])
      #=> [placeholders: %{now: ~U[...]}, returning: true]
  """
  @spec insert_all_opts(keyword()) :: keyword()
  def insert_all_opts(opts \\ []) do
    result =
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
      |> reject_nil_values()

    # Normalize conflict options if present
    case Keyword.get(opts, :conflict_target) do
      nil ->
        result

      target ->
        result
        |> Keyword.put(:conflict_target, normalize_conflict_target_value(target))
        |> Keyword.update(:on_conflict, :nothing, & &1)
    end
  end

  @doc """
  Extract options for update_all operations.

  ## Examples

      Options.update_all_opts([returning: [:id, :status]])
      #=> [returning: [:id, :status]]
  """
  @spec update_all_opts(keyword()) :: keyword()
  def update_all_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log, :returning])
    |> reject_nil_values()
  end

  @doc """
  Extract options for delete_all operations.

  ## Examples

      Options.delete_all_opts([returning: true])
      #=> [returning: true]
  """
  @spec delete_all_opts(keyword()) :: keyword()
  def delete_all_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log, :returning])
    |> reject_nil_values()
  end

  # ─────────────────────────────────────────────────────────────
  # Merge Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Extract options for Merge operations.

  These options are applied when executing the MERGE SQL.

  ## Examples

      Options.merge_opts([timeout: 60_000, prefix: "tenant_1"])
      #=> [timeout: 60_000, prefix: "tenant_1"]
  """
  @spec merge_opts(keyword()) :: keyword()
  def merge_opts(opts \\ []) do
    opts
    |> Keyword.take([:prefix, :timeout, :log])
    |> reject_nil_values()
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp reject_nil_values(opts) do
    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_conflict_target_value(target) when is_atom(target), do: [target]
  defp normalize_conflict_target_value(targets) when is_list(targets), do: targets
  defp normalize_conflict_target_value({:constraint, name}), do: {:constraint, name}

  defp maybe_add_opt(opts, key, source) do
    case Keyword.get(source, key) do
      nil -> opts
      value -> Keyword.put(opts, key, value)
    end
  end
end
