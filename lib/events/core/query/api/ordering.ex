defmodule Events.Core.Query.Api.Ordering do
  @moduledoc false
  # Internal module for Query - ordering operations
  #
  # Handles order/order_by operations with support for:
  # - Single field ordering
  # - Multiple field ordering  
  # - Binding-aware ordering

  alias Events.Core.Query.Token

  @doc """
  Add an order clause to the query.

  Supports both single field and list syntax.

  ## Parameters

  - `token` - The query token
  - `field_or_list` - Field atom or list of order specifications
  - `direction` - `:asc` or `:desc` (or nulls variants)
  - `opts` - Options (e.g., `:binding`)
  """
  @spec order_by(Token.t(), atom() | list(), :asc | :desc, keyword()) :: Token.t()
  def order_by(token, field_or_list, direction \\ :asc, opts \\ [])

  # List form - delegate to order_bys
  def order_by(token, order_list, _direction, _opts) when is_list(order_list) do
    order_bys(token, order_list)
  end

  # Single field form
  def order_by(token, field, direction, opts) when is_atom(field) do
    Token.add_operation(token, {:order, {field, direction, opts}})
  end

  @doc """
  Alias for `order_by/4`. Semantic alternative name.

  Supports both single field and list syntax.

  See `order_by/4` for documentation.
  """
  @spec order(Token.t(), atom() | list(), :asc | :desc, keyword()) :: Token.t()
  def order(token, field_or_list, direction \\ :asc, opts \\ []) do
    order_by(token, field_or_list, direction, opts)
  end

  @doc """
  Add multiple order clauses at once (Ecto-style naming).

  Alias: `orders/2` - Semantic alternative name for the same operation.

  Supports **both** Ecto keyword syntax and tuple syntax!

  ## Parameters

  - `token` - The query token
  - `order_list` - List of order specifications. Each can be:
    - `field` - Atom, defaults to `:asc`
    - **Ecto keyword syntax**: `{direction, field}` - e.g., `asc: :name`
    - **Tuple syntax**: `{field, direction}` - e.g., `{:name, :asc}`
    - `{field, direction, opts}` - 3-tuple with options

  The function intelligently detects which syntax you're using!

  ## Examples

      # Plain atoms (all default to :asc)
      Query.order_bys(token, [:name, :email, :id])

      # Ecto keyword syntax (NEW! - just like Ecto.Query)
      Query.order_bys(token, [asc: :name, desc: :created_at, asc: :id])
      Query.order_bys(token, [desc: :priority, desc_nulls_first: :score])

      # Tuple syntax (our original)
      Query.order_bys(token, [
        {:priority, :desc},
        {:created_at, :desc},
        {:id, :asc}
      ])

      # 3-tuples with options
      Query.order_bys(token, [
        {:priority, :desc, []},
        {:title, :asc, [binding: :posts]},
        {:id, :asc, []}
      ])

      # Mixed formats work too!
      Query.order_bys(token, [
        :name,                              # Plain atom
        asc: :email,                        # Ecto keyword syntax
        {:created_at, :desc},               # Tuple syntax
        {:title, :asc, [binding: :posts]}  # Tuple with opts
      ])
  """
  @spec order_bys(Token.t(), [
          atom()
          | {atom(), :asc | :desc}
          | {atom(), :asc | :desc, keyword()}
        ]) :: Token.t()
  def order_bys(token, order_list) when is_list(order_list) do
    Enum.reduce(order_list, token, fn
      # Plain atom - defaults to :asc
      field, acc when is_atom(field) ->
        order_by(acc, field, :asc)

      # 2-tuple - could be keyword or tuple syntax
      {key, value}, acc ->
        cond do
          # Ecto keyword syntax: [asc: :field, desc: :field]
          # Key is direction, value is field
          key in [
            :asc,
            :desc,
            :asc_nulls_first,
            :asc_nulls_last,
            :desc_nulls_first,
            :desc_nulls_last
          ] ->
            order_by(acc, value, key)

          # Tuple syntax: [{:field, :asc}, {:field, :desc}]
          # Key is field, value is direction
          value in [
            :asc,
            :desc,
            :asc_nulls_first,
            :asc_nulls_last,
            :desc_nulls_first,
            :desc_nulls_last
          ] ->
            order_by(acc, key, value)

          # Ambiguous - assume tuple syntax (field, direction) for backward compatibility
          true ->
            order_by(acc, key, value)
        end

      # 3-tuple - always tuple syntax with opts: {:field, :direction, opts}
      {field, direction, opts}, acc ->
        order_by(acc, field, direction, opts)
    end)
  end

  @doc """
  Alias for `order_bys/2`. Semantic alternative name.

  See `order_bys/2` for documentation.
  """
  @spec orders(Token.t(), [
          atom()
          | {atom(), :asc | :desc}
          | {atom(), :asc | :desc, keyword()}
        ]) :: Token.t()
  def orders(token, order_list) when is_list(order_list) do
    order_bys(token, order_list)
  end
end
