defmodule Events.Core.Query do
  @moduledoc """
  Events-specific query builder wrapper over OmQuery.

  This module provides a thin wrapper that delegates to `OmQuery` with
  Events-specific defaults (repo, telemetry prefix, etc.).

  ## Usage

      alias Events.Core.Query

      User
      |> Query.new()
      |> Query.filter(:status, :eq, "active")
      |> Query.paginate(:offset, limit: 20)
      |> Query.execute()

  ## Submodules

  - `OmQuery.DSL` - Macro-based DSL
  - `OmQuery.Fragment` - Reusable query fragments
  - `OmQuery.Helpers` - Date/time utilities
  - `OmQuery.Multi` - Ecto.Multi integration
  - `OmQuery.FacetedSearch` - E-commerce faceted search
  - `OmQuery.TestHelpers` - Test utilities
  - `OmQuery.SqlScope` - SQL scope builder for migrations

  See `OmQuery` for full documentation.
  """

  # Re-export all OmQuery functions with Events defaults

  # Query construction
  defdelegate new(source), to: OmQuery
  defdelegate filter(token, field, op, value, opts \\ []), to: OmQuery
  defdelegate filter_by(token, filters), to: OmQuery
  defdelegate where(token, field, op, value, opts \\ []), to: OmQuery
  defdelegate order(token, field, direction \\ :asc, opts \\ []), to: OmQuery
  defdelegate order_by(token, field, direction \\ :asc, opts \\ []), to: OmQuery
  defdelegate orders(token, orderings), to: OmQuery
  defdelegate order_bys(token, orderings), to: OmQuery, as: :orders
  defdelegate join(token, assoc, type \\ :inner, opts \\ []), to: OmQuery
  defdelegate joins(token, joins_list), to: OmQuery
  defdelegate select(token, fields), to: OmQuery
  defdelegate preload(token, preloads), to: OmQuery
  defdelegate paginate(token, type, opts \\ []), to: OmQuery
  defdelegate limit(token, limit), to: OmQuery
  defdelegate offset(token, offset), to: OmQuery
  defdelegate distinct(token, fields), to: OmQuery
  defdelegate group_by(token, fields), to: OmQuery
  defdelegate having(token, condition), to: OmQuery
  defdelegate lock(token, mode), to: OmQuery

  # Filter helpers
  defdelegate where_any(token, filters), to: OmQuery
  defdelegate where_all(token, filters), to: OmQuery
  defdelegate search(token, term, fields, opts \\ []), to: OmQuery
  defdelegate exclude_deleted(token, field \\ :deleted_at), to: OmQuery
  defdelegate only_deleted(token, field \\ :deleted_at), to: OmQuery
  defdelegate created_between(token, start_date, end_date, field \\ :inserted_at), to: OmQuery
  defdelegate updated_since(token, datetime, field \\ :updated_at), to: OmQuery
  defdelegate filter_subquery(token, field, op, subquery), to: OmQuery

  # Execution - with Events.Core.Repo default
  @doc """
  Execute the query with Events.Core.Repo.

  See `OmQuery.execute/2` for options.
  """
  def execute(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.execute(token, opts)
  end

  @doc """
  Execute the query with Events.Core.Repo, raising on error.

  See `OmQuery.execute!/2` for options.
  """
  def execute!(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.execute!(token, opts)
  end

  @doc """
  Stream results with Events.Core.Repo.

  See `OmQuery.stream/2` for options.
  """
  def stream(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.stream(token, opts)
  end

  defdelegate batch(tokens, opts \\ []), to: OmQuery

  @doc """
  Execute in transaction with Events.Core.Repo.

  See `OmQuery.transaction/2` for options.
  """
  def transaction(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.transaction(token, opts)
  end

  # Shortcuts - with Events.Core.Repo default
  def first(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.first(token, opts)
  end

  def first!(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.first!(token, opts)
  end

  def one(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.one(token, opts)
  end

  def one!(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.one!(token, opts)
  end

  def all(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.all(token, opts)
  end

  def count(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.count(token, opts)
  end

  def exists?(token, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.exists?(token, opts)
  end

  def aggregate(token, field, agg_type, opts \\ []) do
    opts = Keyword.put_new(opts, :repo, Events.Core.Repo)
    OmQuery.aggregate(token, field, agg_type, opts)
  end

  # Advanced
  defdelegate build(token), to: OmQuery
  defdelegate build!(token), to: OmQuery
  defdelegate debug(token, mode \\ :inspect, opts \\ []), to: OmQuery
  defdelegate with_cte(token, name, query, opts \\ []), to: OmQuery
  defdelegate from_subquery(token), to: OmQuery
  defdelegate raw_where(token, sql, bindings \\ []), to: OmQuery
  defdelegate window(token, name, definition), to: OmQuery
  defdelegate include(token, fragment), to: OmQuery
  defdelegate then_if(token, condition, fun), to: OmQuery

  # Cursor utilities
  defdelegate encode_cursor(values, opts \\ []), to: OmQuery
  defdelegate decode_cursor(cursor), to: OmQuery

  # Type aliases for convenience
  @type token :: OmQuery.Token.t()
  @type result :: OmQuery.Result.t()
end

# Type aliases - use OmQuery types directly
# OmQuery.Token and OmQuery.Result are the canonical types
