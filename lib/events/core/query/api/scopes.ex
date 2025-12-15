defmodule Events.Core.Query.Api.Scopes do
  @moduledoc false
  # Internal module for Query - common query scopes
  #
  # Provides reusable query patterns and scopes:
  # - exclude_deleted/only_deleted - Soft delete scopes
  # - created_between/updated_since - Date filtering
  # - String operations (starts_with, ends_with, contains, etc.)
  # - Null/blank helpers
  # - Status filtering

  alias Events.Core.Query.Token

  @doc "Filter to exclude soft-deleted records"
  @spec exclude_deleted(Token.t(), atom(), module()) :: Token.t()
  def exclude_deleted(token, field, query_module) do
    query_module.filter(token, field, :is_nil, true)
  end

  @doc "Filter to include only soft-deleted records"
  @spec only_deleted(Token.t(), atom(), module()) :: Token.t()
  def only_deleted(token, field, query_module) do
    query_module.filter(token, field, :not_nil, true)
  end

  @doc "Filter by subquery (IN or NOT IN)"
  @spec filter_subquery(Token.t(), atom(), :in | :not_in, Token.t() | Ecto.Query.t(), module()) ::
          Token.t()
  def filter_subquery(token, field, :in, subquery, query_module) do
    query_module.filter(token, field, :in_subquery, subquery)
  end

  def filter_subquery(token, field, :not_in, subquery, query_module) do
    query_module.filter(token, field, :not_in_subquery, subquery)
  end

  @doc "Filter for records created within a time range"
  @spec created_between(
          Token.t(),
          DateTime.t() | NaiveDateTime.t(),
          DateTime.t() | NaiveDateTime.t(),
          atom(),
          module()
        ) :: Token.t()
  def created_between(token, start_time, end_time, field, query_module) do
    query_module.filter(token, field, :between, {start_time, end_time})
  end

  @doc "Filter field between two values (inclusive)"
  @spec between(Token.t(), atom(), term(), term(), keyword(), module()) :: Token.t()
  def between(token, field, min, max, opts, query_module) do
    query_module.filter(token, field, :between, {min, max}, opts)
  end

  @doc "Filter field within any of multiple ranges"
  @spec between_any(Token.t(), atom(), [{term(), term()}], keyword(), module()) :: Token.t()
  def between_any(token, field, ranges, opts, query_module) when is_list(ranges) do
    query_module.filter(token, field, :between, ranges, opts)
  end

  @doc "Filter field to be greater than or equal to a value"
  @spec at_least(Token.t(), atom(), term(), keyword(), module()) :: Token.t()
  def at_least(token, field, value, opts, query_module) do
    query_module.filter(token, field, :gte, value, opts)
  end

  @doc "Filter field to be less than or equal to a value"
  @spec at_most(Token.t(), atom(), term(), keyword(), module()) :: Token.t()
  def at_most(token, field, value, opts, query_module) do
    query_module.filter(token, field, :lte, value, opts)
  end

  ## String Operations

  @doc "Filter where string field starts with a given prefix"
  @spec starts_with(Token.t(), atom(), String.t(), keyword(), module()) :: Token.t()
  def starts_with(token, field, value, opts, query_module) when is_binary(value) do
    pattern = value <> "%"
    string_filter(token, field, pattern, :like, opts, query_module)
  end

  @doc "Filter where string field does NOT start with a given prefix"
  @spec not_starts_with(Token.t(), atom(), String.t(), keyword(), module()) :: Token.t()
  def not_starts_with(token, field, value, opts, query_module) when is_binary(value) do
    pattern = value <> "%"
    string_filter(token, field, pattern, :not_like, opts, query_module)
  end

  @doc "Filter where string field ends with a given suffix"
  @spec ends_with(Token.t(), atom(), String.t(), keyword(), module()) :: Token.t()
  def ends_with(token, field, value, opts, query_module) when is_binary(value) do
    pattern = "%" <> value
    string_filter(token, field, pattern, :like, opts, query_module)
  end

  @doc "Filter where string field does NOT end with a given suffix"
  @spec not_ends_with(Token.t(), atom(), String.t(), keyword(), module()) :: Token.t()
  def not_ends_with(token, field, value, opts, query_module) when is_binary(value) do
    pattern = "%" <> value
    string_filter(token, field, pattern, :not_like, opts, query_module)
  end

  @doc "Filter where string field contains a given substring"
  @spec contains_string(Token.t(), atom(), String.t(), keyword(), module()) :: Token.t()
  def contains_string(token, field, value, opts, query_module) when is_binary(value) do
    pattern = "%" <> value <> "%"
    string_filter(token, field, pattern, :like, opts, query_module)
  end

  @doc "Filter where string field does NOT contain a given substring"
  @spec not_contains_string(Token.t(), atom(), String.t(), keyword(), module()) :: Token.t()
  def not_contains_string(token, field, value, opts, query_module) when is_binary(value) do
    pattern = "%" <> value <> "%"
    string_filter(token, field, pattern, :not_like, opts, query_module)
  end

  defp string_filter(token, field, pattern, base_op, opts, query_module) do
    op = if opts[:case_insensitive], do: case_insensitive_op(base_op), else: base_op
    query_module.filter(token, field, op, pattern, Keyword.delete(opts, :case_insensitive))
  end

  defp case_insensitive_op(:like), do: :ilike
  defp case_insensitive_op(:not_like), do: :not_ilike

  ## Null/Blank Helpers

  @doc "Filter where field is NULL"
  @spec where_nil(Token.t(), atom(), keyword(), module()) :: Token.t()
  def where_nil(token, field, opts, query_module) do
    query_module.filter(token, field, :is_nil, true, opts)
  end

  @doc "Filter where field is NOT NULL"
  @spec where_not_nil(Token.t(), atom(), keyword(), module()) :: Token.t()
  def where_not_nil(token, field, opts, query_module) do
    query_module.filter(token, field, :not_nil, true, opts)
  end

  @doc "Filter where field is blank (NULL or empty string)"
  @spec where_blank(Token.t(), atom(), keyword(), module()) :: Token.t()
  def where_blank(token, field, opts, query_module) do
    binding = opts[:binding]
    base_opts = if binding, do: [binding: binding], else: []

    query_module.where_any(token, [
      {field, :is_nil, true, base_opts},
      {field, :eq, "", base_opts}
    ])
  end

  @doc "Filter where field is present (NOT NULL and NOT empty string)"
  @spec where_present(Token.t(), atom(), keyword(), module()) :: Token.t()
  def where_present(token, field, opts, query_module) do
    token
    |> query_module.filter(field, :not_nil, true, opts)
    |> query_module.filter(field, :neq, "", opts)
  end

  ## Date/Time Helpers

  @doc "Filter for records updated after a given time"
  @spec updated_since(Token.t(), DateTime.t() | NaiveDateTime.t(), atom(), module()) :: Token.t()
  def updated_since(token, since, field, query_module) do
    query_module.filter(token, field, :gt, since)
  end

  @doc "Filter for records created today (UTC)"
  @spec created_today(Token.t(), atom(), module()) :: Token.t()
  def created_today(token, field, query_module) do
    today = Date.utc_today()
    start_time = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    end_time = DateTime.new!(today, ~T[23:59:59.999999], "Etc/UTC")
    created_between(token, start_time, end_time, field, query_module)
  end

  @doc "Filter for records updated in the last N hours"
  @spec updated_recently(Token.t(), pos_integer(), atom(), module()) :: Token.t()
  def updated_recently(token, hours, field, query_module) when is_integer(hours) and hours > 0 do
    since = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)
    updated_since(token, since, field, query_module)
  end

  ## Status Filtering

  @doc "Filter records with a specific status or list of statuses"
  @spec with_status(Token.t(), String.t() | [String.t()], atom(), module()) :: Token.t()
  def with_status(token, statuses, field, query_module) when is_list(statuses) do
    query_module.filter(token, field, :in, statuses)
  end

  def with_status(token, status, field, query_module) when is_binary(status) do
    query_module.filter(token, field, :eq, status)
  end
end
