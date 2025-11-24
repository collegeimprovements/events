defmodule Events.CRUD.DSL do
  @moduledoc """
  Clean, unified DSL for building CRUD operations.
  """

  defmacro query(schema \\ nil, opts \\ [], do: block) do
    quote do
      token =
        if unquote(schema) do
          build_only = Keyword.get(unquote(opts), :build_only, false)
          Events.CRUD.Token.new(unquote(schema), build_only: build_only)
        else
          Events.CRUD.Token.new()
        end

      unquote(block)
      token
    end
  end

  # Token-based operation macros
  defmacro where(token, field, op, value, opts \\ []) do
    quote do
      Events.CRUD.Token.add(
        unquote(token),
        {:where, {unquote(field), unquote(op), unquote(value), unquote(opts)}}
      )
    end
  end

  defmacro join(token, assoc_or_schema, type_or_binding \\ :inner, opts \\ []) do
    quote do
      Events.CRUD.Token.add(
        unquote(token),
        {:join, {unquote(assoc_or_schema), unquote(type_or_binding), unquote(opts)}}
      )
    end
  end

  defmacro order(token, field, dir \\ :asc, opts \\ []) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:order, {unquote(field), unquote(dir), unquote(opts)}})
    end
  end

  defmacro preload(token, assoc, do: nested_block) do
    quote do
      nested_token = Events.CRUD.Token.new()
      token = nested_token
      unquote(nested_block)
      Events.CRUD.Token.add(unquote(token), {:preload, {unquote(assoc), nested_token.operations}})
    end
  end

  # Additional helper macros for nested operations
  defmacro limit(token, value) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:limit, unquote(value)})
    end
  end

  defmacro offset(token, value) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:offset, unquote(value)})
    end
  end

  defmacro paginate(token, type, opts \\ []) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:paginate, {unquote(type), unquote(opts)}})
    end
  end

  defmacro select(token, fields, opts \\ []) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:select, {unquote(fields), unquote(opts)}})
    end
  end

  defmacro group(token, fields, opts \\ []) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:group, {unquote(fields), unquote(opts)}})
    end
  end

  defmacro having(token, conditions, opts \\ []) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:having, {unquote(conditions), unquote(opts)}})
    end
  end

  defmacro window(token, name, definition) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:window, {unquote(name), unquote(definition)}})
    end
  end

  # Raw SQL as first-class
  defmacro raw(token, sql) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:raw, {:sql, unquote(sql), %{}}})
    end
  end

  defmacro raw(token, sql, params) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:raw, {:sql, unquote(sql), unquote(params)}})
    end
  end

  defmacro raw_where(token, fragment) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:raw, {:fragment, unquote(fragment), %{}}})
    end
  end

  defmacro raw_where(token, fragment, params) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:raw, {:fragment, unquote(fragment), unquote(params)}})
    end
  end

  defmacro debug(token) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:debug, nil})
    end
  end

  defmacro debug(token, label) do
    quote do
      Events.CRUD.Token.add(unquote(token), {:debug, unquote(label)})
    end
  end

  defmacro debug() do
    quote do
      token = Events.CRUD.Token.add(token, {:debug, nil})
    end
  end

  defmacro debug(label) do
    quote do
      token = Events.CRUD.Token.add(token, {:debug, unquote(label)})
    end
  end

  # CRUD operations
  defmacro create(schema, attrs, opts \\ []), do: execute_crud(:create, {schema, attrs, opts})
  defmacro update(record, attrs, opts \\ []), do: execute_crud(:update, {record, attrs, opts})
  defmacro delete(record, opts \\ []), do: execute_crud(:delete, {record, opts})
  defmacro get(schema, id, opts \\ []), do: execute_crud(:get, {schema, id, opts})

  # List operation (uses query building)
  defmacro list(schema, opts \\ [], do: block) do
    quote do
      token = query(unquote(schema), do: unquote(block))
      Events.CRUD.Token.add(token, {:list, {unquote(schema), unquote(opts)}})
      Events.CRUD.Token.execute(token)
    end
  end

  defp execute_crud(operation, spec) do
    quote do
      token = Events.CRUD.Token.new() |> Events.CRUD.Token.add({unquote(operation), unquote(spec)})
      Events.CRUD.Token.execute(token)
    end
  end
end
