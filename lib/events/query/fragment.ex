defmodule Events.Query.Fragment do
  @moduledoc """
  Reusable query components inspired by PRQL's composability.

  Fragments are reusable pieces of query logic that can be included
  in any query. They promote DRY principles and make common query
  patterns easy to reuse.

  ## Defining Fragments

  Use `defragment/2` to define named fragments:

      defmodule MyApp.QueryFragments do
        use Events.Query.Fragment

        defragment :active_users do
          filter :status, :eq, "active"
          filter :verified, :eq, true
        end

        defragment :recent do
          filter :created_at, :gte, days_ago(30)
          order :created_at, :desc
        end

        defragment :limited, limit: 50 do
          paginate :offset, limit: limit
        end
      end

  ## Using Fragments

  Include fragments in queries using `include/2`:

      import Events.Query

      User
      |> Query.new()
      |> Query.include(MyApp.QueryFragments.active_users())
      |> Query.include(MyApp.QueryFragments.recent())
      |> Query.execute()

  ## Fragment with Parameters

  Fragments can accept parameters:

      defmodule MyApp.QueryFragments do
        use Events.Query.Fragment

        defragment :by_status, status: "active" do
          filter :status, :eq, status
        end

        defragment :paginated, page: 1, per_page: 20 do
          offset = (page - 1) * per_page
          paginate :offset, limit: per_page, offset: offset
        end
      end

      # Usage with parameters
      User
      |> Query.new()
      |> Query.include(MyApp.QueryFragments.by_status(status: "pending"))
      |> Query.include(MyApp.QueryFragments.paginated(page: 2, per_page: 10))
      |> Query.execute()
  """

  alias Events.Query.Token

  @doc """
  Use this module to define query fragments.

  ## Example

      defmodule MyApp.QueryFragments do
        use Events.Query.Fragment

        defragment :active do
          filter :active, :eq, true
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import Events.Query.Fragment, only: [defragment: 2, defragment: 3]
      import Events.Query, except: [new: 1]
    end
  end

  @doc """
  Define a reusable query fragment.

  ## Examples

      # Simple fragment
      defragment :active do
        filter :status, :eq, "active"
      end

      # Fragment with default parameters
      defragment :limited, limit: 20 do
        paginate :offset, limit: limit
      end
  """
  defmacro defragment(name, do: block) do
    quote do
      def unquote(name)() do
        unquote(name)([])
      end

      def unquote(name)(params) when is_list(params) do
        token = Token.new(:nested)
        apply_fragment_body(token, params, fn _params ->
          unquote(block)
        end)
      end
    end
  end

  defmacro defragment(name, defaults, do: block) when is_list(defaults) do
    quote do
      def unquote(name)() do
        unquote(name)([])
      end

      def unquote(name)(params) when is_list(params) do
        # Merge defaults with provided params
        merged_params = Keyword.merge(unquote(defaults), params)
        token = Token.new(:nested)

        # Bind params to local variables for use in the block
        Enum.reduce(merged_params, token, fn {key, value}, acc ->
          # We need to make params available to the block
          :ok
          acc
        end)

        # Execute the block with merged params available
        apply_fragment_body_with_params(token, merged_params, fn ->
          # Bind each param as a local variable using var!
          unquote(
            for {param_name, _default} <- defaults do
              quote do
                var!(unquote(Macro.var(param_name, nil))) =
                  Keyword.get(merged_params, unquote(param_name))
              end
            end
          )

          unquote(block)
        end)
      end
    end
  end

  @doc """
  Apply a fragment's operations to a token.

  This is used internally by fragment definitions.
  """
  def apply_fragment_body(token, params, body_fn) do
    # Execute the fragment body which returns operations
    result = body_fn.(params)
    merge_operations(token, result)
  end

  def apply_fragment_body_with_params(token, _params, body_fn) do
    result = body_fn.()
    merge_operations(token, result)
  end

  defp merge_operations(%Token{} = token, %Token{operations: ops}) do
    # Merge operations from the fragment into the token
    Enum.reduce(ops, token, fn op, acc ->
      Token.add_operation(acc, op)
    end)
  end

  defp merge_operations(token, _other) do
    # If the result isn't a token, just return the original
    token
  end

  @doc """
  Include a fragment's operations in a query token.

  ## Example

      token
      |> Query.include(MyFragments.active_users())
      |> Query.include(MyFragments.recent())
  """
  @spec include(Token.t(), Token.t()) :: Token.t()
  def include(%Token{} = token, %Token{operations: fragment_ops}) do
    Enum.reduce(fragment_ops, token, fn op, acc ->
      Token.add_operation(acc, op)
    end)
  end

  def include(%Token{} = token, nil), do: token

  @doc """
  Conditionally include a fragment.

  ## Example

      token
      |> Query.include_if(show_active?, MyFragments.active_users())
  """
  @spec include_if(Token.t(), boolean(), Token.t() | nil) :: Token.t()
  def include_if(token, true, fragment), do: include(token, fragment)
  def include_if(token, false, _fragment), do: token
  def include_if(token, nil, _fragment), do: token
end
