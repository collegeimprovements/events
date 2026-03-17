defmodule OmIdempotency.Query do
  @moduledoc """
  Query helpers for idempotency records using OmQuery.

  Provides high-level query functions for common operations.
  """

  import Ecto.Query, only: [from: 2]

  alias OmIdempotency.Record

  @doc """
  Lists idempotency records by state.

  ## Options

  - `:limit` - Maximum number of records (default: 100)
  - `:offset` - Number of records to skip (default: 0)
  - `:order_by` - Order direction (default: [desc: :inserted_at])
  - `:scope` - Filter by scope
  - `:repo` - Ecto repo module

  ## Examples

      Query.list_by_state(:completed, limit: 50)
      Query.list_by_state(:processing, scope: "stripe")
  """
  @spec list_by_state(Record.state(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def list_by_state(state, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, desc: :inserted_at)
    scope = Keyword.get(opts, :scope)

    Record
    |> OmQuery.where(:state, :eq, state)
    |> maybe_filter_by_scope(scope)
    |> OmQuery.order_by(order_by)
    |> OmQuery.limit(limit)
    |> OmQuery.offset(offset)
    |> execute_query(opts)
  end

  @doc """
  Lists stale processing records that have exceeded their lock timeout.

  ## Examples

      Query.list_stale_processing()
  """
  @spec list_stale_processing(keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def list_stale_processing(opts \\ []) do
    now = DateTime.utc_now()

    Record
    |> OmQuery.where(:state, :eq, :processing)
    |> OmQuery.where(:locked_until, :lt, now)
    |> OmQuery.order_by(:locked_until, :asc)
    |> execute_query(opts)
  end

  @doc """
  Lists expired records ready for cleanup.

  ## Examples

      Query.list_expired()
  """
  @spec list_expired(keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def list_expired(opts \\ []) do
    now = DateTime.utc_now()

    Record
    |> OmQuery.where(:expires_at, :lt, now)
    |> OmQuery.order_by(:expires_at, :asc)
    |> execute_query(opts)
  end

  @doc """
  Gets statistics grouped by state.

  Returns a map of state => count.

  ## Examples

      Query.stats()
      #=> {:ok, %{pending: 10, processing: 5, completed: 1000, failed: 3}}
  """
  @spec stats(keyword()) :: {:ok, map()} | {:error, term()}
  def stats(opts \\ []) do
    repo = get_repo(opts)

    query = from r in Record,
      group_by: r.state,
      select: {r.state, count(r.id)}

    {:ok, query |> repo.all() |> Map.new()}
  rescue
    e -> {:error, e}
  end

  @doc """
  Gets statistics grouped by scope.

  Returns a map of scope => %{state => count}.

  ## Examples

      Query.stats_by_scope()
      #=> {:ok, %{
        "stripe" => %{completed: 500, failed: 2},
        "sendgrid" => %{completed: 300, processing: 1}
      }}
  """
  @spec stats_by_scope(keyword()) :: {:ok, map()} | {:error, term()}
  def stats_by_scope(opts \\ []) do
    repo = get_repo(opts)

    query = from r in Record,
      group_by: [r.scope, r.state],
      select: {r.scope, r.state, count(r.id)}

    results = repo.all(query)

    grouped =
      results
      |> Enum.group_by(fn {scope, _state, _count} -> scope end)
      |> Map.new(fn {scope, entries} ->
        state_counts =
          entries
          |> Enum.map(fn {_scope, state, count} -> {state, count} end)
          |> Map.new()

        {scope, state_counts}
      end)

    {:ok, grouped}
  rescue
    e -> {:error, e}
  end

  @doc """
  Lists records that are older than the given age.

  ## Examples

      # Records older than 7 days
      Query.list_older_than(:timer.hours(24 * 7))
  """
  @spec list_older_than(pos_integer(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def list_older_than(age_ms, opts \\ []) do
    cutoff = DateTime.add(DateTime.utc_now(), -age_ms, :millisecond)

    Record
    |> OmQuery.where(:inserted_at, :lt, cutoff)
    |> OmQuery.order_by(:inserted_at, :asc)
    |> execute_query(opts)
  end

  @doc """
  Searches for records by key pattern.

  Uses ILIKE for pattern matching.

  ## Examples

      Query.search_by_key("order_%")
      Query.search_by_key("%charge%", scope: "stripe")
  """
  @spec search_by_key(String.t(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def search_by_key(pattern, opts \\ []) do
    scope = Keyword.get(opts, :scope)
    limit = Keyword.get(opts, :limit, 100)

    Record
    |> OmQuery.where(:key, :ilike, pattern)
    |> maybe_filter_by_scope(scope)
    |> OmQuery.order_by(:inserted_at, :desc)
    |> OmQuery.limit(limit)
    |> execute_query(opts)
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp maybe_filter_by_scope(query, nil), do: query
  defp maybe_filter_by_scope(query, scope), do: OmQuery.where(query, :scope, :eq, scope)

  defp execute_query(token, opts) do
    repo = get_repo(opts)
    {:ok, OmQuery.all(token, repo: repo)}
  rescue
    e -> {:error, e}
  end

  defp get_repo(opts) do
    Keyword.get_lazy(opts, :repo, fn ->
      Application.get_env(:om_idempotency, :repo) ||
        raise "No repo configured for OmIdempotency"
    end)
  end
end
