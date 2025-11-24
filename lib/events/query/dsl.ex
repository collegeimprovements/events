defmodule Events.Query.DSL do
  @moduledoc """
  Macro-based DSL for building queries.

  Provides a clean, composable syntax inspired by Ecto.Query.

  ## Examples

      import Events.Query.DSL

      # Simple query
      query User do
        filter :status, :eq, "active"
        filter :age, :gte, 18
        order :name, :asc
        limit 10
      end

      # With pagination
      query Post do
        filter :published, :eq, true
        order :published_at, :desc
        paginate :offset, limit: 20, offset: 40
      end

      # Nested preloads
      query User do
        filter :status, :eq, "active"

        preload :posts do
          filter :published, :eq, true
          order :created_at, :desc
          limit 5
        end

        preload :comments do
          filter :approved, :eq, true
        end
      end

      # Complex joins
      query Product do
        filter :active, :eq, true

        join :category, :inner, as: :cat

        filter :cat, :name, :eq, "Electronics", binding: :cat

        select %{
          product_name: :name,
          category_name: {:cat, :name}
        }
      end

      # CTEs and windows
      query Order do
        with_cte :recent_orders do
          filter :created_at, :gte, ~D[2024-01-01]
        end

        window :running_total,
          partition_by: :customer_id,
          order_by: [asc: :created_at]

        select %{
          order_id: :id,
          amount: :amount,
          total: {:window, :sum, :amount, :running_total}
        }
      end
  """

  @doc """
  Defines a query block.

  Returns a token that can be piped to `execute/1`.
  """
  defmacro query(source, do: block) do
    quote do
      token = Events.Query.new(unquote(source))
      var!(query_token, Events.Query.DSL) = token
      unquote(block)
      var!(query_token, Events.Query.DSL)
    end
  end

  @doc "Add a filter condition"
  defmacro filter(field, op, value) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.filter(var!(query_token, Events.Query.DSL), unquote(field), unquote(op), unquote(value))
    end
  end

  defmacro filter(field, op, value, opts) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.filter(
          var!(query_token, Events.Query.DSL),
          unquote(field),
          unquote(op),
          unquote(value),
          unquote(opts)
        )
    end
  end

  @doc "Add ordering"
  defmacro order(field, direction) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.order(var!(query_token, Events.Query.DSL), unquote(field), unquote(direction))
    end
  end

  @doc "Add limit"
  defmacro limit(value) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.limit(var!(query_token, Events.Query.DSL), unquote(value))
    end
  end

  @doc "Add offset"
  defmacro offset(value) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.offset(var!(query_token, Events.Query.DSL), unquote(value))
    end
  end

  @doc "Add pagination"
  defmacro paginate(type, opts \\ []) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.paginate(var!(query_token, Events.Query.DSL), unquote(type), unquote(opts))
    end
  end

  @doc "Add a join"
  defmacro join(assoc_or_schema, type \\ :inner, opts \\ []) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.join(
          var!(query_token, Events.Query.DSL),
          unquote(assoc_or_schema),
          unquote(type),
          unquote(opts)
        )
    end
  end

  @doc "Add a simple preload"
  defmacro preload(association) when is_atom(association) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.preload(var!(query_token, Events.Query.DSL), unquote(association))
    end
  end

  @doc "Add a nested preload with filters"
  defmacro preload(association, do: block) do
    quote do
      nested_fn = fn nested_token ->
        var!(query_token, Events.Query.DSL) = nested_token
        unquote(block)
        var!(query_token, Events.Query.DSL)
      end

      var!(query_token, Events.Query.DSL) =
        Events.Query.preload(var!(query_token, Events.Query.DSL), unquote(association), nested_fn)
    end
  end

  @doc "Add select clause"
  defmacro select(fields) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.select(var!(query_token, Events.Query.DSL), unquote(fields))
    end
  end

  @doc "Add group by"
  defmacro group_by(fields) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.group_by(var!(query_token, Events.Query.DSL), unquote(fields))
    end
  end

  @doc "Add having clause"
  defmacro having(conditions) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.having(var!(query_token, Events.Query.DSL), unquote(conditions))
    end
  end

  @doc "Add distinct"
  defmacro distinct(value) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.distinct(var!(query_token, Events.Query.DSL), unquote(value))
    end
  end

  @doc "Add lock"
  defmacro lock(mode) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.lock(var!(query_token, Events.Query.DSL), unquote(mode))
    end
  end

  @doc "Add CTE"
  defmacro with_cte(name, do: block) do
    quote do
      cte_token = Events.Query.new(:nested)
      var!(query_token, Events.Query.DSL) = cte_token
      unquote(block)
      cte_result = var!(query_token, Events.Query.DSL)

      var!(query_token, Events.Query.DSL) =
        Events.Query.with_cte(var!(query_token, Events.Query.DSL), unquote(name), cte_result)
    end
  end

  @doc "Add window definition"
  defmacro window(name, definition) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.window(var!(query_token, Events.Query.DSL), unquote(name), unquote(definition))
    end
  end

  @doc "Add raw WHERE clause"
  defmacro raw_where(sql, params \\ %{}) do
    quote do
      var!(query_token, Events.Query.DSL) =
        Events.Query.raw_where(var!(query_token, Events.Query.DSL), unquote(sql), unquote(params))
    end
  end

  @doc "Execute the query"
  defmacro execute(opts \\ []) do
    quote do
      Events.Query.execute(var!(query_token, Events.Query.DSL), unquote(opts))
    end
  end
end
