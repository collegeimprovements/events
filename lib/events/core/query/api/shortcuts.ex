defmodule Events.Core.Query.Api.Shortcuts do
  @moduledoc false
  # Internal module for Query - execution shortcuts
  #
  # Provides convenient shortcuts for common query patterns:
  # - first/first! - Get first record
  # - one/one! - Get exactly one record
  # - all - Get all records
  # - count - Count records
  # - exists? - Check existence
  # - aggregate - Run aggregate functions

  alias Events.Core.Query.Token

  @doc """
  Get the first result or nil.
  """
  @spec first(Token.t(), keyword(), module()) :: term() | nil
  def first(%Token{} = token, opts, query_module) do
    token
    |> query_module.limit(1)
    |> query_module.execute!(Keyword.put(opts, :unsafe, true))
    |> Map.get(:data)
    |> List.first()
  end

  @doc """
  Get the first result, raising if no results found.
  """
  @spec first!(Token.t(), keyword(), module()) :: term()
  def first!(%Token{} = token, opts, query_module) do
    case first(token, opts, query_module) do
      nil -> raise Ecto.NoResultsError, queryable: query_module.build(token)
      result -> result
    end
  end

  @doc """
  Get exactly one result, raising if zero or more than one.
  """
  @spec one(Token.t(), keyword(), module()) :: term() | nil
  def one(%Token{} = token, opts, query_module) do
    result =
      token
      |> query_module.limit(2)
      |> query_module.execute!(Keyword.put(opts, :unsafe, true))
      |> Map.get(:data)

    case result do
      [] -> nil
      [single] -> single
      [_ | _] -> raise Ecto.MultipleResultsError, queryable: query_module.build(token), count: 2
    end
  end

  @doc """
  Get exactly one result, raising if zero or more than one.
  """
  @spec one!(Token.t(), keyword(), module()) :: term()
  def one!(%Token{} = token, opts, query_module) do
    case one(token, opts, query_module) do
      nil -> raise Ecto.NoResultsError, queryable: query_module.build(token)
      result -> result
    end
  end

  @doc """
  Get the count of records matching the query.
  """
  @spec count(Token.t(), keyword(), module()) :: non_neg_integer()
  def count(%Token{} = token, opts, query_module) do
    repo = get_repo(opts, query_module)
    timeout = opts[:timeout] || 15_000

    query =
      token
      |> query_module.remove_operations(:select)
      |> query_module.remove_operations(:order)
      |> query_module.remove_operations(:preload)
      |> query_module.remove_operations(:limit)
      |> query_module.remove_operations(:offset)
      |> query_module.remove_operations(:paginate)
      |> query_module.build()

    repo.aggregate(query, :count, timeout: timeout)
  end

  @doc """
  Check if any records match the query.

  More efficient than `count(token) > 0` as it uses EXISTS.
  """
  @spec exists?(Token.t(), keyword(), module()) :: boolean()
  def exists?(%Token{} = token, opts, query_module) do
    repo = get_repo(opts, query_module)
    timeout = opts[:timeout] || 15_000

    query = query_module.build(token)
    repo.exists?(query, timeout: timeout)
  end

  @doc """
  Perform an aggregate operation on the query.

  ## Supported Aggregates

  - `:count` - Count of records (or field)
  - `:sum` - Sum of field values
  - `:avg` - Average of field values
  - `:min` - Minimum field value
  - `:max` - Maximum field value
  """
  @spec aggregate(Token.t(), :count | :sum | :avg | :min | :max, atom(), keyword(), module()) ::
          term()
  def aggregate(%Token{} = token, aggregate_type, field, opts, query_module)
      when aggregate_type in [:count, :sum, :avg, :min, :max] do
    repo = get_repo(opts, query_module)
    timeout = opts[:timeout] || 15_000

    query =
      token
      |> query_module.remove_operations(:select)
      |> query_module.remove_operations(:order)
      |> query_module.remove_operations(:preload)
      |> query_module.remove_operations(:limit)
      |> query_module.remove_operations(:offset)
      |> query_module.remove_operations(:paginate)
      |> query_module.build()

    repo.aggregate(query, aggregate_type, field, timeout: timeout)
  end

  @doc """
  Get all records as a plain list (without Result wrapper).
  """
  @spec all(Token.t(), keyword(), module()) :: [term()]
  def all(%Token{} = token, opts, query_module) do
    token
    |> query_module.execute!(opts)
    |> Map.get(:data)
  end

  ## Private Helpers

  defp get_repo(opts, query_module) do
    opts[:repo] || query_module.default_repo() ||
      raise "No repo configured. Pass :repo option or configure default_repo: config :events, Events.Core.Query, default_repo: MyApp.Repo"
  end
end
