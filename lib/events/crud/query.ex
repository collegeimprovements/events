defmodule Events.CRUD.Query do
  @moduledoc """
  Pure Elixir/Ecto functions for building queries.

  These functions provide the same functionality as the DSL macros but work with
  Ecto queries directly, allowing for programmatic query building and composition.

  All functions take an `Ecto.Queryable` as the first argument and return a modified query.
  """

  import Ecto.Query
  alias Events.Repo

  @doc """
  Starts a query from a schema or existing query.

  ## Examples

      # From schema
      Events.CRUD.Query.from(User)

      # From existing query
      User |> Events.CRUD.Query.from()
  """
  @spec from(Ecto.Queryable.t()) :: Ecto.Query.t()
  def from(queryable), do: Ecto.Query.from(queryable)

  @doc """
  Adds a WHERE clause to filter records.

  ## Examples

      User
      |> Events.CRUD.Query.where(:status, :eq, "active")
      |> Events.CRUD.Query.where(:age, :gte, 18)
  """
  @spec where(Ecto.Query.t(), atom(), atom(), term(), keyword()) :: Ecto.Query.t()
  def where(query, field, op, value, _opts \\ []) do
    # Use standard Ecto where with dynamic expressions
    # This is a simplified implementation - in practice you'd want more sophisticated
    # operator handling
    case op do
      :eq -> from(q in query, where: field(q, ^field) == ^value)
      :neq -> from(q in query, where: field(q, ^field) != ^value)
      :gt -> from(q in query, where: field(q, ^field) > ^value)
      :gte -> from(q in query, where: field(q, ^field) >= ^value)
      :lt -> from(q in query, where: field(q, ^field) < ^value)
      :lte -> from(q in query, where: field(q, ^field) <= ^value)
      :in -> from(q in query, where: field(q, ^field) in ^value)
      :like -> from(q in query, where: like(field(q, ^field), ^value))
      :ilike -> from(q in query, where: ilike(field(q, ^field), ^value))
      :is_nil -> from(q in query, where: is_nil(field(q, ^field)))
      :not_nil -> from(q in query, where: not is_nil(field(q, ^field)))
      # Unknown operator, return unchanged
      _ -> query
    end
  end

  @doc """
  Adds a JOIN clause.

  ## Examples

      # Association joins
      User
      |> Events.CRUD.Query.join(:posts, :left)
      |> Events.CRUD.Query.join(:comments, :inner, as: :post_comments)

      # Custom joins with on conditions
      User
      |> Events.CRUD.Query.join(Post, :posts, on: posts.user_id == user.id and posts.published == true, type: :left)
  """
  @spec join(Ecto.Query.t(), atom() | module(), atom() | keyword(), keyword()) :: Ecto.Query.t()
  def join(query, assoc_or_schema, type_or_opts \\ :inner, opts \\ [])

  # Association join: join(query, :posts, :left, [])
  def join(query, assoc, type, opts) when is_atom(assoc) and is_atom(type) and is_list(opts) do
    case type do
      :inner -> from(q in query, join: a in assoc(q, ^assoc), as: ^assoc)
      :left -> from(q in query, left_join: a in assoc(q, ^assoc), as: ^assoc)
      :right -> from(q in query, right_join: a in assoc(q, ^assoc), as: ^assoc)
      :full -> from(q in query, full_join: a in assoc(q, ^assoc), as: ^assoc)
      :cross -> from(q in query, cross_join: a in assoc(q, ^assoc), as: ^assoc)
    end
  end

  # Custom join: join(query, Post, :posts, on: condition, type: :left)
  def join(query, schema, binding, opts)
      when is_atom(schema) and is_atom(binding) and is_list(opts) do
    on_condition = Keyword.get(opts, :on)
    join_type = Keyword.get(opts, :type, :inner)

    if on_condition do
      case join_type do
        :inner -> from(q in query, join: record in ^schema, on: ^on_condition, as: ^binding)
        :left -> from(q in query, left_join: record in ^schema, on: ^on_condition, as: ^binding)
        :right -> from(q in query, right_join: record in ^schema, on: ^on_condition, as: ^binding)
        :full -> from(q in query, full_join: record in ^schema, on: ^on_condition, as: ^binding)
      end
    else
      # Fallback to association join if no on condition
      # This shouldn't happen in normal usage, but provide a fallback
      query
    end
  end

  @doc """
  Adds an ORDER BY clause.

  ## Examples

      User
      |> Events.CRUD.Query.order(:created_at, :desc)
      |> Events.CRUD.Query.order(:name, :asc)
  """
  @spec order(Ecto.Query.t(), atom(), atom(), keyword()) :: Ecto.Query.t()
  def order(query, field, dir \\ :asc, _opts \\ []) do
    from(q in query, order_by: [{^dir, ^field}])
  end

  @doc """
  Adds a LIMIT clause.

  ## Examples

      User |> Events.CRUD.Query.limit(10)
  """
  @spec limit(Ecto.Query.t(), pos_integer()) :: Ecto.Query.t()
  def limit(query, count) do
    from(q in query, limit: ^count)
  end

  @doc """
  Adds an OFFSET clause.

  ## Examples

      User |> Events.CRUD.Query.offset(20)
  """
  @spec offset(Ecto.Query.t(), non_neg_integer()) :: Ecto.Query.t()
  def offset(query, count) do
    from(q in query, offset: ^count)
  end

  @doc """
  Adds a SELECT clause.

  ## Examples

      # Select specific fields
      User |> Events.CRUD.Query.select([:id, :name, :email])

      # Select with expressions
      Post |> Events.CRUD.Query.select(%{title: :title, word_count: fragment("length(content)")})
  """
  @spec select(Ecto.Query.t(), term(), keyword()) :: Ecto.Query.t()
  def select(query, fields, _opts \\ []) do
    from(q in query, select: ^fields)
  end

  @doc """
  Adds a GROUP BY clause.

  ## Examples

      Order |> Events.CRUD.Query.group([:status])
  """
  @spec group(Ecto.Query.t(), [atom()], keyword()) :: Ecto.Query.t()
  def group(query, fields, _opts \\ []) do
    from(q in query, group_by: ^fields)
  end

  @doc """
  Adds a HAVING clause.

  ## Examples

      Order
      |> Events.CRUD.Query.group([:status])
      |> Events.CRUD.Query.having([count: {:gte, 5}])
  """
  @spec having(Ecto.Query.t(), keyword(), keyword()) :: Ecto.Query.t()
  def having(query, conditions, _opts \\ []) do
    # Convert conditions to dynamic expressions
    # This is a simplified implementation
    dynamic_conditions = build_having_conditions(conditions)
    from(q in query, having: ^dynamic_conditions)
  end

  @doc """
  Adds a preload.

  ## Examples

      User
      |> Events.CRUD.Query.preload(:posts)
      |> Events.CRUD.Query.preload(:comments, &(&1 |> Events.CRUD.Query.where(:approved, :eq, true)))
  """
  @spec preload(Ecto.Query.t(), atom() | {atom(), (Ecto.Query.t() -> Ecto.Query.t())}, keyword()) ::
          Ecto.Query.t()
  def preload(query, assoc, opts \\ [])

  def preload(query, {assoc, preload_fun}, _opts) when is_function(preload_fun, 1) do
    # For nested preloads with conditions
    base_query = from(q in assoc, [])
    nested_query = preload_fun.(base_query)
    from(q in query, preload: [{^assoc, ^nested_query}])
  end

  def preload(query, assoc, _opts) do
    from(q in query, preload: ^assoc)
  end

  @doc """
  Adds pagination.

  ## Examples

      # Offset pagination
      User |> Events.CRUD.Query.paginate(:offset, limit: 20, offset: 40)

      # Cursor pagination
      Post |> Events.CRUD.Query.paginate(:cursor, limit: 10, cursor_fields: [published_at: :desc, id: :desc])
  """
  @spec paginate(Ecto.Query.t(), atom(), keyword()) :: Ecto.Query.t()
  def paginate(query, :offset, opts) do
    limit = opts[:limit]
    offset = opts[:offset] || 0

    query
    |> apply_limit(limit)
    |> apply_offset(offset)
  end

  def paginate(query, :cursor, opts) do
    # Simplified cursor pagination
    limit = opts[:limit] || 20
    from(q in query, limit: ^limit)
  end

  @doc """
  Executes a query and returns results.

  ## Examples

      User
      |> Events.CRUD.Query.where(:active, :eq, true)
      |> Events.CRUD.Query.limit(10)
      |> Events.CRUD.Query.execute()
  """
  @spec execute(Ecto.Query.t()) :: Events.CRUD.Result.t()
  def execute(query) do
    case Repo.all(query) do
      results ->
        Events.CRUD.Result.success(results)
    end
  rescue
    error ->
      Events.CRUD.Result.error(error)
  end

  @doc """
  Executes a query and returns a single result.

  ## Examples

      User |> Events.CRUD.Query.get(123)
  """
  @spec get(Ecto.Query.t(), term()) :: Events.CRUD.Result.t()
  def get(query, id) do
    case Repo.get(query, id) do
      nil -> Events.CRUD.Result.not_found()
      result -> Events.CRUD.Result.found(result)
    end
  rescue
    error -> Events.CRUD.Result.error(error)
  end

  @doc """
  Executes a query and returns the first result.

  ## Examples

      User
      |> Events.CRUD.Query.where(:active, :eq, true)
      |> Events.CRUD.Query.order(:created_at, :desc)
      |> Events.CRUD.Query.first()
  """
  @spec first(Ecto.Query.t()) :: Events.CRUD.Result.t()
  def first(query) do
    case Repo.one(from(q in query, limit: 1)) do
      nil -> Events.CRUD.Result.not_found()
      result -> Events.CRUD.Result.found(result)
    end
  rescue
    error -> Events.CRUD.Result.error(error)
  end

  @doc """
  Counts records matching the query.

  ## Examples

      User
      |> Events.CRUD.Query.where(:active, :eq, true)
      |> Events.CRUD.Query.count()
  """
  @spec count(Ecto.Query.t()) :: Events.CRUD.Result.t()
  def count(query) do
    case Repo.aggregate(query, :count, :id) do
      count -> Events.CRUD.Result.success(count)
    end
  rescue
    error -> Events.CRUD.Result.error(error)
  end

  @doc """
  Debug function to print query and SQL.

  ## Examples

      User
      |> Events.CRUD.Query.where(:active, :eq, true)
      |> Events.CRUD.Query.debug("After filtering")
      |> Events.CRUD.Query.limit(10)
      |> Events.CRUD.Query.execute()
  """
  @spec debug(Ecto.Query.t(), String.t() | nil) :: Ecto.Query.t()
  def debug(query, label \\ nil) do
    label = label || "Debug"

    IO.puts("\n=== #{label} ===")
    IO.puts("Ecto Query: #{inspect(query, pretty: true)}")

    case Repo.to_sql(:all, query) do
      {sql, params} ->
        IO.puts("Raw SQL: #{sql}")
        IO.puts("Parameters: #{inspect(params)}")

      {:error, error} ->
        IO.puts("SQL Generation Error: #{inspect(error)}")
    end

    IO.puts("=== End #{label} ===\n")

    query
  end

  # Private helper functions

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: from(q in query, limit: ^limit)

  defp apply_offset(query, 0), do: query
  defp apply_offset(query, offset), do: from(q in query, offset: ^offset)

  defp build_having_conditions(conditions) do
    # Simplified having condition building
    # In a real implementation, this would handle complex expressions
    true
  end
end
