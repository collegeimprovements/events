defmodule OmQuery.Config do
  @moduledoc """
  Centralized configuration for OmQuery.

  This module provides a single source of truth for all OmQuery configuration,
  including repo resolution, timeouts, telemetry prefixes, and query limits.

  ## Configuration Options

      config :om_query,
        default_repo: MyApp.Repo,
        default_timeout: 15_000,
        telemetry_prefix: [:my_app, :query],
        max_operations: 100,
        max_joins: 10,
        max_filters: 50,
        warn_on_complexity: true,
        max_limit: 1000,
        default_limit: 20

  ## Usage

      # Get configured repo or raise
      repo = OmQuery.Config.repo!(opts)

      # Get with fallback
      timeout = OmQuery.Config.timeout(opts)

      # Check complexity limits
      OmQuery.Config.check_complexity(token)

      # Validate pagination
      OmQuery.Config.validate_pagination!(opts)
  """

  require Logger

  # ─────────────────────────────────────────────────────────────
  # Compile-time Configuration
  # ─────────────────────────────────────────────────────────────

  @default_repo Application.compile_env(:om_query, :default_repo, nil)
  @default_timeout Application.compile_env(:om_query, :default_timeout, 15_000)
  @telemetry_prefix Application.compile_env(:om_query, :telemetry_prefix, [:om_query])
  @max_operations Application.compile_env(:om_query, :max_operations, 100)
  @max_joins Application.compile_env(:om_query, :max_joins, 10)
  @max_filters Application.compile_env(:om_query, :max_filters, 50)
  @warn_on_complexity Application.compile_env(:om_query, :warn_on_complexity, true)
  @max_limit Application.compile_env(:om_query, :max_limit, 1000)
  @default_limit Application.compile_env(:om_query, :default_limit, 20)

  # ─────────────────────────────────────────────────────────────
  # Repo Resolution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the repo from options or configured default.

  Returns `nil` if no repo is configured.

  ## Examples

      OmQuery.Config.repo([repo: MyApp.Repo])
      #=> MyApp.Repo

      OmQuery.Config.repo([])
      #=> <configured default or nil>
  """
  @spec repo(keyword()) :: module() | nil
  def repo(opts \\ []) do
    Keyword.get(opts, :repo) || @default_repo
  end

  @doc """
  Get the repo from options or configured default, raising if not found.

  ## Examples

      OmQuery.Config.repo!([repo: MyApp.Repo])
      #=> MyApp.Repo

      OmQuery.Config.repo!([])
      #=> ** (ArgumentError) No repo configured...
  """
  @spec repo!(keyword()) :: module()
  def repo!(opts \\ []) do
    case repo(opts) do
      nil ->
        raise ArgumentError, """
        No repo configured for OmQuery.

        Either pass the :repo option:

            OmQuery.execute(token, repo: MyApp.Repo)

        Or configure a default repo in your config:

            config :om_query, :default_repo, MyApp.Repo
        """

      repo ->
        repo
    end
  end

  @doc """
  Get the configured default repo.

  ## Examples

      OmQuery.Config.default_repo()
      #=> MyApp.Repo
  """
  @spec default_repo() :: module() | nil
  def default_repo, do: @default_repo

  # ─────────────────────────────────────────────────────────────
  # Timeout Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get timeout from options or configured default.

  ## Examples

      OmQuery.Config.timeout([timeout: 30_000])
      #=> 30_000

      OmQuery.Config.timeout([])
      #=> 15_000
  """
  @spec timeout(keyword()) :: pos_integer()
  def timeout(opts \\ []) do
    Keyword.get(opts, :timeout) || @default_timeout
  end

  @doc """
  Get the configured default timeout.
  """
  @spec default_timeout() :: pos_integer()
  def default_timeout, do: @default_timeout

  # ─────────────────────────────────────────────────────────────
  # Telemetry Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the telemetry event prefix.

  ## Examples

      OmQuery.Config.telemetry_prefix()
      #=> [:om_query]
  """
  @spec telemetry_prefix() :: [atom()]
  def telemetry_prefix, do: @telemetry_prefix

  @doc """
  Build a telemetry event name with the configured prefix.

  ## Examples

      OmQuery.Config.telemetry_event(:execute)
      #=> [:om_query, :execute]

      OmQuery.Config.telemetry_event([:query, :start])
      #=> [:om_query, :query, :start]
  """
  @spec telemetry_event(atom() | [atom()]) :: [atom()]
  def telemetry_event(suffix) when is_atom(suffix), do: @telemetry_prefix ++ [suffix]
  def telemetry_event(suffix) when is_list(suffix), do: @telemetry_prefix ++ suffix

  # ─────────────────────────────────────────────────────────────
  # Query Complexity Limits
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the maximum allowed operations per query.
  """
  @spec max_operations() :: pos_integer()
  def max_operations, do: @max_operations

  @doc """
  Get the maximum allowed joins per query.
  """
  @spec max_joins() :: pos_integer()
  def max_joins, do: @max_joins

  @doc """
  Get the maximum allowed filters per query.
  """
  @spec max_filters() :: pos_integer()
  def max_filters, do: @max_filters

  @doc """
  Check if complexity warnings are enabled.
  """
  @spec warn_on_complexity?() :: boolean()
  def warn_on_complexity?, do: @warn_on_complexity

  @doc """
  Check query complexity and emit warnings if limits are exceeded.

  Returns `:ok` always (warnings only, no errors).

  ## Checks

  - Total operations count
  - Join count
  - Filter count

  ## Examples

      OmQuery.Config.check_complexity(token)
      #=> :ok  # May log warnings
  """
  @spec check_complexity(struct()) :: :ok
  def check_complexity(token) when is_struct(token) do
    if @warn_on_complexity do
      check_operation_count(token)
      check_join_count(token)
      check_filter_count(token)
    end

    :ok
  end

  defp check_operation_count(%{operations: operations}) when is_list(operations) do
    count = length(operations)

    if count > @max_operations do
      Logger.warning(
        "[OmQuery] Query has #{count} operations, exceeding recommended limit of #{@max_operations}. " <>
          "This may impact performance. Consider breaking into smaller queries."
      )
    end
  end

  defp check_operation_count(_), do: :ok

  defp check_join_count(%{operations: operations}) when is_list(operations) do
    join_count =
      operations
      |> Enum.count(fn
        {:join, _} -> true
        {:left_join, _} -> true
        {:right_join, _} -> true
        {:inner_join, _} -> true
        {:cross_join, _} -> true
        {:lateral_join, _} -> true
        _ -> false
      end)

    if join_count > @max_joins do
      Logger.warning(
        "[OmQuery] Query has #{join_count} joins, exceeding recommended limit of #{@max_joins}. " <>
          "This may cause performance issues. Consider denormalizing or using separate queries."
      )
    end
  end

  defp check_join_count(_), do: :ok

  defp check_filter_count(%{operations: operations}) when is_list(operations) do
    filter_count =
      operations
      |> Enum.count(fn
        {:filter, _} -> true
        {:where, _} -> true
        {:where_any, _} -> true
        {:where_all, _} -> true
        {:or_filter, _} -> true
        _ -> false
      end)

    if filter_count > @max_filters do
      Logger.warning(
        "[OmQuery] Query has #{filter_count} filters, exceeding recommended limit of #{@max_filters}. " <>
          "Consider using composite conditions or full-text search."
      )
    end
  end

  defp check_filter_count(_), do: :ok

  # ─────────────────────────────────────────────────────────────
  # SQL Options Extraction
  # ─────────────────────────────────────────────────────────────

  @doc """
  Extract options that should be passed to Ecto/SQL operations.

  ## Examples

      OmQuery.Config.sql_opts([timeout: 5000, prefix: "tenant_1", custom: true])
      #=> [timeout: 5000, prefix: "tenant_1"]
  """
  @spec sql_opts(keyword()) :: keyword()
  def sql_opts(opts) do
    opts
    |> Keyword.take([:timeout, :prefix, :log])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Extract options for repo operations (insert, update, etc).

  ## Examples

      OmQuery.Config.repo_opts([timeout: 5000, returning: true, custom: true])
      #=> [timeout: 5000, returning: true]
  """
  @spec repo_opts(keyword()) :: keyword()
  def repo_opts(opts) do
    opts
    |> Keyword.take([:timeout, :prefix, :log, :returning])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # ─────────────────────────────────────────────────────────────
  # Pagination Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the maximum allowed limit for pagination.
  """
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  @doc """
  Get the default limit for pagination.
  """
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  Validate pagination options.

  Returns `:ok` if valid, or `{:error, reason}` if invalid.

  ## Validations

  - `limit` must be a positive integer
  - `limit` must not exceed `max_limit`
  - `offset` must be a non-negative integer

  ## Examples

      OmQuery.Config.validate_pagination([limit: 20, offset: 0])
      #=> :ok

      OmQuery.Config.validate_pagination([limit: -1])
      #=> {:error, "limit must be a positive integer, got: -1"}

      OmQuery.Config.validate_pagination([limit: 10000])
      #=> {:error, "limit 10000 exceeds maximum allowed limit of 1000"}
  """
  @spec validate_pagination(keyword()) :: :ok | {:error, String.t()}
  def validate_pagination(opts) do
    with :ok <- validate_limit(opts[:limit]),
         :ok <- validate_offset(opts[:offset]) do
      :ok
    end
  end

  @doc """
  Validate pagination options, raising on error.

  Raises structured exceptions:
  - `OmQuery.LimitExceededError` when limit exceeds max_limit
  - `OmQuery.PaginationError` for other validation failures

  ## Examples

      OmQuery.Config.validate_pagination!([limit: 20])
      #=> :ok

      OmQuery.Config.validate_pagination!([limit: -1])
      #=> ** (OmQuery.PaginationError) Invalid offset pagination: limit must be a positive integer

      OmQuery.Config.validate_pagination!([limit: 10000])
      #=> ** (OmQuery.LimitExceededError) Limit of 10000 exceeds max_limit of 1000
  """
  @spec validate_pagination!(keyword()) :: :ok
  def validate_pagination!(opts) do
    case validate_pagination(opts) do
      :ok ->
        :ok

      {:error, :limit_exceeded, requested} ->
        raise OmQuery.LimitExceededError,
          requested: requested,
          max_allowed: @max_limit,
          suggestion: "Use cursor-based pagination or streaming for large datasets."

      {:error, reason} ->
        raise OmQuery.PaginationError,
          type: :offset,
          reason: reason,
          suggestion: "Ensure limit is a positive integer and offset is non-negative."
    end
  end

  defp validate_limit(nil), do: :ok

  defp validate_limit(limit) when is_integer(limit) and limit > 0 do
    if limit > @max_limit do
      {:error, :limit_exceeded, limit}
    else
      :ok
    end
  end

  defp validate_limit(limit) when is_integer(limit) do
    {:error, "limit must be a positive integer, got: #{limit}"}
  end

  defp validate_limit(limit) do
    {:error, "limit must be a positive integer, got: #{inspect(limit)}"}
  end

  defp validate_offset(nil), do: :ok

  defp validate_offset(offset) when is_integer(offset) and offset >= 0, do: :ok

  defp validate_offset(offset) when is_integer(offset) do
    {:error, "offset must be a non-negative integer, got: #{offset}"}
  end

  defp validate_offset(offset) do
    {:error, "offset must be a non-negative integer, got: #{inspect(offset)}"}
  end
end
