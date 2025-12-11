defmodule OmQuery.DSL do
  @moduledoc """
  Macro-based DSL for building queries.

  Provides a clean, composable syntax inspired by Ecto.Query.

  ## Comparison Operators (Ecto-like)

  Use familiar comparison syntax directly:

      import OmQuery.DSL

      query User do
        where :age >= 18
        where :status == "active"
        where :email != nil
        where :role in ["admin", "moderator"]
        where :name =~ "%john%"    # ilike pattern
      end

  ## Traditional Filter Syntax

      query User do
        filter :status, :eq, "active"
        filter :age, :gte, 18
        filter :score, :between, {50, 100}
      end

  ## Keyword Shorthand

      query User do
        where status: "active", verified: true
      end

  ## Binding Tuple Support

  Reference joined tables with `{binding, :field}`:

      query Product do
        join :category, :left, as: :cat
        where {:cat, :name} == "Electronics"
        where {:cat, :priority} >= 1
      end

  ## Options Support

      query User do
        where :email == "JOHN@EXAMPLE.COM", case: :insensitive
        where {:cat, :name} == "electronics", case: :insensitive
      end

  ## Examples

      import OmQuery.DSL

      # Simple query with operators
      query User do
        where :status == "active"
        where :age >= 18
        order :name, :asc
        limit 10
      end

      # Complex joins
      query Product do
        where :active == true
        join :category, :inner, as: :cat
        filter :name, :eq, "Electronics", binding: :cat
        select %{product_name: :name, category_name: {:cat, :name}}
      end
  """

  # Supported comparison operators for where/on/maybe macros
  @comparison_ops [:==, :!=, :>, :>=, :<, :<=, :in, :=~]

  # ============================================================================
  # Query Block
  # ============================================================================

  @doc """
  Defines a query block. Returns a token that can be piped to `execute/1`.
  """
  defmacro query(source, do: block) do
    quote do
      var!(query_token, OmQuery.DSL) = OmQuery.new(unquote(source))
      unquote(block)
      var!(query_token, OmQuery.DSL)
    end
  end

  # ============================================================================
  # WHERE - Unified Comparison Operators
  # ============================================================================

  @doc """
  Add a filter using comparison operators or keyword list.

  ## Syntax Variants

      # Simple field comparisons
      where :age >= 18
      where :status == "active"
      where :role in ["admin", "mod"]
      where :name =~ "%john%"

      # Binding tuple for joined tables
      where {:cat, :name} == "Electronics"

      # With options
      where :email == "JOHN@EXAMPLE.COM", case: :insensitive

      # Keyword list shorthand
      where status: "active", verified: true
  """
  # Keyword list: where status: "active", verified: true
  defmacro where(filters) when is_list(filters) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(var!(query_token, OmQuery.DSL), unquote(filters))
    end
  end

  # Comparison operators: where :field op value
  defmacro where({op, _, [lhs, rhs]}) when op in @comparison_ops do
    {field, binding} = parse_field(lhs)
    {internal_op, value} = translate_operator(op, rhs)
    opts = if binding, do: [binding: binding], else: []

    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(internal_op),
          unquote(value),
          unquote(opts)
        )
    end
  end

  # Comparison operators with options: where :field op value, case: :insensitive
  defmacro where({op, _, [lhs, rhs]}, user_opts)
           when op in @comparison_ops and is_list(user_opts) do
    {field, binding} = parse_field(lhs)
    {internal_op, value} = translate_operator(op, rhs)
    opts = build_opts(binding, user_opts)

    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(internal_op),
          unquote(value),
          unquote(opts)
        )
    end
  end

  # ============================================================================
  # FILTER - Traditional syntax
  # ============================================================================

  @doc "Add a filter with explicit operator: filter :field, :op, value"
  defmacro filter(field, op, value) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(op),
          unquote(value)
        )
    end
  end

  defmacro filter(field, op, value, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(op),
          unquote(value),
          unquote(opts)
        )
    end
  end

  @doc "Add multiple filters at once"
  defmacro filters(filter_list) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filters(var!(query_token, OmQuery.DSL), unquote(filter_list))
    end
  end

  # ============================================================================
  # ON - Filter on joined table binding
  # ============================================================================

  @doc """
  Add a filter on a joined table using its binding name.

      join :category, :left, as: :cat
      on :cat, :name == "Electronics"
      on :cat, :priority >= 1, case: :insensitive
  """
  # on :binding, :field op value
  defmacro on(binding, {op, _, [field, value]}) when is_atom(binding) and op in @comparison_ops do
    {internal_op, actual_value} = translate_operator(op, value)

    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(internal_op),
          unquote(actual_value),
          binding: unquote(binding)
        )
    end
  end

  # on :binding, :field op value, opts
  defmacro on(binding, {op, _, [field, value]}, user_opts)
           when is_atom(binding) and op in @comparison_ops do
    {internal_op, actual_value} = translate_operator(op, value)
    opts = build_opts(binding, user_opts)

    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.filter(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(internal_op),
          unquote(actual_value),
          unquote(opts)
        )
    end
  end

  # ============================================================================
  # MAYBE - Conditional filters (only apply if value is present)
  # ============================================================================

  @doc """
  Conditionally apply a filter only if the value is present.

      maybe :status == params[:status]
      maybe :role in params[:roles], when: :not_empty
      maybe {:cat, :name} == params[:category]
  """
  # maybe :field op value
  defmacro maybe({op, _, [lhs, rhs]}) when op in @comparison_ops do
    {field, binding} = parse_field(lhs)
    {internal_op, value} = translate_operator(op, rhs)
    opts = if binding, do: [binding: binding], else: []

    if binding do
      quote do
        var!(query_token, OmQuery.DSL) =
          OmQuery.maybe_on(
            var!(query_token, OmQuery.DSL),
            unquote(binding),
            unquote(field),
            unquote(value),
            unquote(internal_op),
            unquote(opts)
          )
      end
    else
      quote do
        var!(query_token, OmQuery.DSL) =
          OmQuery.maybe(
            var!(query_token, OmQuery.DSL),
            unquote(field),
            unquote(value),
            unquote(internal_op),
            unquote(opts)
          )
      end
    end
  end

  # maybe :field op value, opts
  defmacro maybe({op, _, [lhs, rhs]}, user_opts)
           when op in @comparison_ops and is_list(user_opts) do
    {field, binding} = parse_field(lhs)
    {internal_op, value} = translate_operator(op, rhs)
    opts = build_opts(binding, user_opts)

    if binding do
      quote do
        var!(query_token, OmQuery.DSL) =
          OmQuery.maybe_on(
            var!(query_token, OmQuery.DSL),
            unquote(binding),
            unquote(field),
            unquote(value),
            unquote(internal_op),
            unquote(opts)
          )
      end
    else
      quote do
        var!(query_token, OmQuery.DSL) =
          OmQuery.maybe(
            var!(query_token, OmQuery.DSL),
            unquote(field),
            unquote(value),
            unquote(internal_op),
            unquote(opts)
          )
      end
    end
  end

  # ============================================================================
  # JOIN Operations
  # ============================================================================

  @doc "Add a join: join :assoc, :type, opts"
  defmacro join(assoc, type, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.join(
          var!(query_token, OmQuery.DSL),
          unquote(assoc),
          unquote(type),
          unquote(opts)
        )
    end
  end

  @doc "Left join shorthand"
  defmacro left_join(assoc, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.left_join(
          var!(query_token, OmQuery.DSL),
          unquote(assoc),
          unquote(opts)
        )
    end
  end

  @doc "Inner join shorthand"
  defmacro inner_join(assoc, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.inner_join(
          var!(query_token, OmQuery.DSL),
          unquote(assoc),
          unquote(opts)
        )
    end
  end

  @doc "Right join shorthand"
  defmacro right_join(assoc, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.right_join(
          var!(query_token, OmQuery.DSL),
          unquote(assoc),
          unquote(opts)
        )
    end
  end

  @doc "Full join shorthand"
  defmacro full_join(assoc, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.full_join(
          var!(query_token, OmQuery.DSL),
          unquote(assoc),
          unquote(opts)
        )
    end
  end

  @doc "Cross join shorthand"
  defmacro cross_join(assoc, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.cross_join(
          var!(query_token, OmQuery.DSL),
          unquote(assoc),
          unquote(opts)
        )
    end
  end

  # ============================================================================
  # ORDER Operations
  # ============================================================================

  @doc "Add ordering: order :field, :direction"
  defmacro order(field, direction \\ :asc) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.order(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(direction)
        )
    end
  end

  defmacro order(field, direction, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.order(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(direction),
          unquote(opts)
        )
    end
  end

  @doc "Add multiple orderings"
  defmacro orders(order_list) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.orders(var!(query_token, OmQuery.DSL), unquote(order_list))
    end
  end

  # ============================================================================
  # PAGINATION
  # ============================================================================

  @doc "Add pagination: paginate :type, opts"
  defmacro paginate(type, opts \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.paginate(
          var!(query_token, OmQuery.DSL),
          unquote(type),
          unquote(opts)
        )
    end
  end

  @doc "Set limit"
  defmacro limit(n) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.limit(var!(query_token, OmQuery.DSL), unquote(n))
    end
  end

  @doc "Set offset"
  defmacro offset(n) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.offset(var!(query_token, OmQuery.DSL), unquote(n))
    end
  end

  # ============================================================================
  # SELECT & PRELOAD
  # ============================================================================

  @doc "Select specific fields"
  defmacro select(fields) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.select(var!(query_token, OmQuery.DSL), unquote(fields))
    end
  end

  @doc "Preload associations"
  defmacro preload(assoc) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.preload(var!(query_token, OmQuery.DSL), unquote(assoc))
    end
  end

  defmacro preload(assoc, do: block) do
    quote do
      # Save the outer query token
      outer_token = var!(query_token, OmQuery.DSL)

      # Build preload with a function that creates the nested query
      var!(query_token, OmQuery.DSL) =
        OmQuery.preload(outer_token, unquote(assoc), fn _nested ->
          # Create a fresh nested token and execute the block
          inner_token = OmQuery.new(:nested)
          var!(query_token, OmQuery.DSL) = inner_token
          unquote(block)
          var!(query_token, OmQuery.DSL)
        end)
    end
  end

  @doc "Distinct query"
  defmacro distinct(value \\ true) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.distinct(var!(query_token, OmQuery.DSL), unquote(value))
    end
  end

  @doc "Group by fields"
  defmacro group_by(fields) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.group_by(var!(query_token, OmQuery.DSL), unquote(fields))
    end
  end

  @doc "Having clause"
  defmacro having(conditions) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.having(var!(query_token, OmQuery.DSL), unquote(conditions))
    end
  end

  # ============================================================================
  # CTE (Common Table Expressions)
  # ============================================================================

  @doc "Define a CTE"
  defmacro with_cte(name, do: block) do
    quote do
      # Save the outer query token
      outer_token = var!(query_token, OmQuery.DSL)

      # Create nested token and execute block
      cte_token = OmQuery.new(:nested)
      var!(query_token, OmQuery.DSL) = cte_token
      unquote(block)
      cte_result = var!(query_token, OmQuery.DSL)

      # Add CTE to the outer token
      var!(query_token, OmQuery.DSL) =
        OmQuery.with_cte(outer_token, unquote(name), cte_result)
    end
  end

  defmacro with_cte(name, token) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.with_cte(
          var!(query_token, OmQuery.DSL),
          unquote(name),
          unquote(token)
        )
    end
  end

  # ============================================================================
  # WINDOW Functions
  # ============================================================================

  @doc "Define a window"
  defmacro window(name, definition) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.window(
          var!(query_token, OmQuery.DSL),
          unquote(name),
          unquote(definition)
        )
    end
  end

  # ============================================================================
  # RAW SQL
  # ============================================================================

  @doc "Add raw SQL WHERE clause"
  defmacro raw_where(sql, params \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.raw(
          var!(query_token, OmQuery.DSL),
          unquote(sql),
          unquote(params)
        )
    end
  end

  defmacro raw(sql, params \\ []) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.raw(
          var!(query_token, OmQuery.DSL),
          unquote(sql),
          unquote(params)
        )
    end
  end

  # ============================================================================
  # OR/AND/NOT Filter Groups
  # ============================================================================

  @doc "Combine filters with OR"
  defmacro any_of(filters) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_any(var!(query_token, OmQuery.DSL), unquote(filters))
    end
  end

  @doc "Combine filters with AND"
  defmacro all_of(filters) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_all(var!(query_token, OmQuery.DSL), unquote(filters))
    end
  end

  @doc "Combine filters with NOT OR"
  defmacro none_of(filters) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_none(var!(query_token, OmQuery.DSL), unquote(filters))
    end
  end

  # ============================================================================
  # Convenience Filter Helpers
  # ============================================================================

  @doc "Negate a filter"
  defmacro where_not(field, op, value) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_not(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(op),
          unquote(value)
        )
    end
  end

  defmacro where_not(field, op, value, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_not(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(op),
          unquote(value),
          unquote(opts)
        )
    end
  end

  @doc "Field-to-field comparison"
  defmacro where_field(field1, op, field2) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_field(
          var!(query_token, OmQuery.DSL),
          unquote(field1),
          unquote(op),
          unquote(field2)
        )
    end
  end

  defmacro where_field(field1, op, field2, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_field(
          var!(query_token, OmQuery.DSL),
          unquote(field1),
          unquote(op),
          unquote(field2),
          unquote(opts)
        )
    end
  end

  @doc "Between range"
  defmacro between(field, min, max) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.between(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(min),
          unquote(max)
        )
    end
  end

  defmacro between(field, min, max, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.between(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(min),
          unquote(max),
          unquote(opts)
        )
    end
  end

  @doc "At least (>=)"
  defmacro at_least(field, value) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.at_least(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(value)
        )
    end
  end

  defmacro at_least(field, value, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.at_least(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(value),
          unquote(opts)
        )
    end
  end

  @doc "At most (<=)"
  defmacro at_most(field, value) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.at_most(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(value)
        )
    end
  end

  defmacro at_most(field, value, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.at_most(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(value),
          unquote(opts)
        )
    end
  end

  # ============================================================================
  # String Operation Helpers
  # ============================================================================

  @doc "Starts with pattern"
  defmacro starts_with(field, prefix) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.starts_with(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(prefix)
        )
    end
  end

  defmacro starts_with(field, prefix, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.starts_with(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(prefix),
          unquote(opts)
        )
    end
  end

  @doc "Ends with pattern"
  defmacro ends_with(field, suffix) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.ends_with(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(suffix)
        )
    end
  end

  defmacro ends_with(field, suffix, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.ends_with(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(suffix),
          unquote(opts)
        )
    end
  end

  @doc "Contains string"
  defmacro contains_string(field, substring) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.contains_string(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(substring)
        )
    end
  end

  defmacro contains_string(field, substring, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.contains_string(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(substring),
          unquote(opts)
        )
    end
  end

  # ============================================================================
  # Null/Blank Helpers
  # ============================================================================

  @doc "Check for null"
  defmacro null(field) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_nil(var!(query_token, OmQuery.DSL), unquote(field))
    end
  end

  defmacro null(field, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_nil(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(opts)
        )
    end
  end

  @doc "Check for not null"
  defmacro not_null(field) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_not_nil(var!(query_token, OmQuery.DSL), unquote(field))
    end
  end

  defmacro not_null(field, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_not_nil(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(opts)
        )
    end
  end

  @doc "Check for blank (null or empty string)"
  defmacro blank(field) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_blank(var!(query_token, OmQuery.DSL), unquote(field))
    end
  end

  defmacro blank(field, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_blank(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(opts)
        )
    end
  end

  @doc "Check for present (not null and not empty)"
  defmacro present(field) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_present(var!(query_token, OmQuery.DSL), unquote(field))
    end
  end

  defmacro present(field, opts) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.where_present(
          var!(query_token, OmQuery.DSL),
          unquote(field),
          unquote(opts)
        )
    end
  end

  # ============================================================================
  # Scope Helpers
  # ============================================================================

  @doc "Apply a scope function"
  defmacro scope(scope_fn) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.scope(var!(query_token, OmQuery.DSL), unquote(scope_fn))
    end
  end

  @doc "Apply a named scope from module"
  defmacro apply_scope(module, scope_name) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.apply_scope(
          var!(query_token, OmQuery.DSL),
          unquote(module),
          unquote(scope_name)
        )
    end
  end

  defmacro apply_scope(module, scope_name, args) do
    quote do
      var!(query_token, OmQuery.DSL) =
        OmQuery.apply_scope(
          var!(query_token, OmQuery.DSL),
          unquote(module),
          unquote(scope_name),
          unquote(args)
        )
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Parse field from AST - handles both simple :field and {binding, :field}
  defp parse_field({binding, field}) when is_atom(binding) and is_atom(field), do: {field, binding}
  defp parse_field(field) when is_atom(field), do: {field, nil}

  # Translate AST operator to internal operator, handling nil special cases
  defp translate_operator(:==, nil), do: {:is_nil, true}
  defp translate_operator(:!=, nil), do: {:not_nil, true}
  defp translate_operator(:==, value), do: {:eq, value}
  defp translate_operator(:!=, value), do: {:neq, value}
  defp translate_operator(:>, value), do: {:gt, value}
  defp translate_operator(:>=, value), do: {:gte, value}
  defp translate_operator(:<, value), do: {:lt, value}
  defp translate_operator(:<=, value), do: {:lte, value}
  defp translate_operator(:in, value), do: {:in, value}
  defp translate_operator(:=~, value), do: {:ilike, value}

  # Build opts list from binding and user options
  # Order matters for tests: binding comes first, then other options
  defp build_opts(binding, user_opts) do
    []
    |> maybe_add_opt(:binding, binding)
    |> maybe_add_opt(:case_insensitive, user_opts[:case] == :insensitive)
    |> maybe_add_opt(:cast, user_opts[:cast])
    |> maybe_add_opt(:when, user_opts[:when])
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, _key, false), do: opts
  defp maybe_add_opt(opts, key, value), do: opts ++ [{key, value}]
end
