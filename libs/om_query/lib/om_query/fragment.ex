defmodule OmQuery.Fragment do
  @moduledoc """
  Reusable query components inspired by PRQL's composability.

  Fragments are reusable pieces of query logic that can be included
  in any query. They promote DRY principles and make common query
  patterns easy to reuse.

  ## Defining Fragments

  There are two ways to define fragments:

  ### 1. Using `fragment/2` (Recommended - Function-based)

  The simplest and most explicit approach. Just define regular functions
  that return a Token:

      defmodule MyApp.QueryFragments do
        alias OmQuery

        def active_users do
          OmQuery.Token.new(:nested)
          |> OmQuery.filter(:status, :eq, "active")
          |> OmQuery.filter(:verified, :eq, true)
        end

        def by_status(status \\\\ "active") do
          OmQuery.Token.new(:nested)
          |> OmQuery.filter(:status, :eq, status)
        end

        def paginated(page \\\\ 1, per_page \\\\ 20) do
          offset = (page - 1) * per_page

          OmQuery.Token.new(:nested)
          |> OmQuery.paginate(:offset, limit: per_page, offset: offset)
        end
      end

  ### 2. Using `defragment` Macro (DSL-based)

  For those who prefer the DSL syntax within fragments:

      defmodule MyApp.QueryFragments do
        use OmQuery.Fragment

        defragment :active_users do
          filter :status, :eq, "active"
          filter :verified, :eq, true
        end

        defragment :by_status, [status: "active"] do
          filter :status, :eq, params[:status]
        end

        defragment :paginated, [page: 1, per_page: 20] do
          offset = (params[:page] - 1) * params[:per_page]
          paginate :offset, limit: params[:per_page], offset: offset
        end
      end

  ## Using Fragments

  Include fragments in queries using `include/2`:

      import OmQuery

      User
      |> OmQuery.new()
      |> OmQuery.include(MyApp.QueryFragments.active_users())
      |> OmQuery.execute()

      # With parameters (function-based)
      User
      |> OmQuery.new()
      |> OmQuery.include(MyApp.QueryFragments.by_status("pending"))
      |> OmQuery.include(MyApp.QueryFragments.paginated(2, 10))
      |> OmQuery.execute()

      # With parameters (macro-based)
      User
      |> OmQuery.new()
      |> OmQuery.include(MyApp.QueryFragments.by_status(status: "pending"))
      |> OmQuery.include(MyApp.QueryFragments.paginated(page: 2, per_page: 10))
      |> OmQuery.execute()

  ## Fragment Composition

  Fragments can include other fragments:

      defmodule MyApp.QueryFragments do
        alias OmQuery

        def active_users do
          OmQuery.Token.new(:nested)
          |> OmQuery.filter(:status, :eq, "active")
        end

        def active_admins do
          active_users()
          |> OmQuery.filter(:role, :eq, "admin")
        end
      end
  """

  alias OmQuery.Token

  @doc """
  Use this module to define query fragments with the DSL.

  Imports the `defragment` macro and Query functions.

  ## Example

      defmodule MyApp.QueryFragments do
        use OmQuery.Fragment

        defragment :active do
          filter :active, :eq, true
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import OmQuery.Fragment, only: [defragment: 2, defragment: 3]
      import OmQuery, except: [new: 1]
    end
  end

  @doc """
  Define a reusable query fragment without parameters.

  ## Example

      defragment :active do
        filter :status, :eq, "active"
        order :created_at, :desc
      end
  """
  defmacro defragment(name, do: block) do
    quote do
      @doc "Fragment: #{unquote(name)} (no parameters)"
      def unquote(name)() do
        token = var!(query_token, OmQuery.DSL) = Token.new(:nested)
        unquote(block)
        var!(query_token, OmQuery.DSL)
      end

      @doc false
      def unquote(name)([]), do: unquote(name)()
    end
  end

  @doc """
  Define a reusable query fragment with parameters.

  Parameters are accessed via the `params` keyword inside the block.

  ## Example

      defragment :by_status, [status: "active"] do
        filter :status, :eq, params[:status]
      end

      defragment :paginated, [page: 1, per_page: 20] do
        offset = (params[:page] - 1) * params[:per_page]
        paginate :offset, limit: params[:per_page], offset: offset
      end

  ## Usage

      MyFragments.by_status(status: "pending")
      MyFragments.paginated(page: 2, per_page: 50)
  """
  defmacro defragment(name, defaults, do: block) when is_list(defaults) do
    quote do
      @doc "Fragment: #{unquote(name)} with params: #{inspect(unquote(defaults))}"
      def unquote(name)(opts \\ []) when is_list(opts) do
        # Merge defaults with provided options
        params = Keyword.merge(unquote(defaults), opts)

        # Set up the query token for DSL operations
        token = var!(query_token, OmQuery.DSL) = Token.new(:nested)

        # Make params available in the block
        var!(params) = params

        # Execute the fragment body
        unquote(block)

        # Return the modified token
        var!(query_token, OmQuery.DSL)
      end
    end
  end

  @doc """
  Include a fragment's operations in a query token.

  Merges all operations from the fragment into the target token.

  ## Examples

      # Include a simple fragment
      token
      |> OmQuery.include(MyFragments.active_users())

      # Include a parameterized fragment
      token
      |> OmQuery.include(MyFragments.by_status("pending"))

      # Chain multiple fragments
      token
      |> OmQuery.include(MyFragments.active_users())
      |> OmQuery.include(MyFragments.recent_first())
      |> OmQuery.include(MyFragments.paginated(page: 2))
  """
  @spec include(Token.t(), Token.t() | nil) :: Token.t()
  def include(%Token{} = token, %Token{operations: fragment_ops}) do
    Enum.reduce(fragment_ops, token, fn op, acc ->
      Token.add_operation(acc, op)
    end)
  end

  def include(%Token{} = token, nil), do: token

  @doc """
  Conditionally include a fragment based on a boolean or truthy value.

  ## Examples

      # Boolean condition
      token
      |> OmQuery.include_if(user.admin?, MyFragments.admin_only())

      # Truthy condition (nil/false are falsy)
      token
      |> OmQuery.include_if(params[:show_active], MyFragments.active_users())
  """
  @spec include_if(Token.t(), term(), Token.t() | nil) :: Token.t()
  def include_if(token, condition, fragment)

  def include_if(%Token{} = token, true, fragment), do: include(token, fragment)
  def include_if(%Token{} = token, false, _fragment), do: token
  def include_if(%Token{} = token, nil, _fragment), do: token

  # Any other truthy value includes the fragment
  def include_if(%Token{} = token, _truthy, fragment), do: include(token, fragment)

  @doc """
  Create a fragment from a list of operations programmatically.

  Useful for building fragments dynamically at runtime.

  ## Examples

      # Build fragment from a list of filter specs
      filters = [
        {:status, :eq, "active"},
        {:role, :in, ["admin", "manager"]}
      ]

      fragment = Fragment.from_filters(filters)
      OmQuery.include(token, fragment)
  """
  @spec from_filters([{atom(), atom(), term()} | {atom(), atom(), term(), keyword()}]) :: Token.t()
  def from_filters(filter_specs) when is_list(filter_specs) do
    Enum.reduce(filter_specs, Token.new(:nested), fn
      {field, op, value}, token ->
        Token.add_operation(token, {:filter, {field, op, value, []}})

      {field, op, value, opts}, token ->
        Token.add_operation(token, {:filter, {field, op, value, opts}})
    end)
  end

  @doc """
  Create a fragment that applies ordering.

  ## Examples

      fragment = Fragment.from_order([desc: :created_at, asc: :id])
      OmQuery.include(token, fragment)
  """
  @spec from_order([{:asc | :desc, atom()} | {atom(), :asc | :desc}]) :: Token.t()
  def from_order(order_specs) when is_list(order_specs) do
    Enum.reduce(order_specs, Token.new(:nested), fn
      # Ecto keyword style: [asc: :field]
      {dir, field}, token when dir in [:asc, :desc] ->
        Token.add_operation(token, {:order, {field, dir, []}})

      # Tuple style: [{:field, :asc}]
      {field, dir}, token when dir in [:asc, :desc] ->
        Token.add_operation(token, {:order, {field, dir, []}})
    end)
  end

  @doc """
  Compose multiple fragments into a single fragment.

  ## Examples

      active = MyFragments.active_users()
      recent = MyFragments.recent_first()
      limited = MyFragments.with_limit(50)

      combined = Fragment.compose([active, recent, limited])
      OmQuery.include(token, combined)
  """
  @spec compose([Token.t()]) :: Token.t()
  def compose(fragments) when is_list(fragments) do
    Enum.reduce(fragments, Token.new(:nested), fn fragment, acc ->
      include(acc, fragment)
    end)
  end
end
