defmodule Events.Core.Query.Debug do
  @moduledoc """
  Comprehensive debugging utilities for the Query system.

  Works like `IO.inspect` - can be placed anywhere in a pipeline and returns
  the input unchanged, making it fully composable.

  ## Supported Formats

  - `:raw_sql` - Raw SQL string with interpolated parameters (default)
  - `:sql` - Alias for `:raw_sql`
  - `:sql_params` - SQL with separate params list `{sql, params}`
  - `:ecto` - Ecto.Query struct inspection
  - `:dsl` - DSL macro syntax representation
  - `:pipeline` - Pipeline syntax representation
  - `:token` - Token struct with operations
  - `:explain` - PostgreSQL EXPLAIN output (requires DB connection)
  - `:explain_analyze` - PostgreSQL EXPLAIN ANALYZE (executes query!)
  - `:all` - All formats combined

  ## Usage

  ```elixir
  # Default: prints raw SQL
  Product
  |> Query.new()
  |> Query.filter(:status, :eq, "active")
  |> Query.debug()
  |> Query.execute()

  # Specify format
  Product
  |> Query.new()
  |> Query.filter(:status, :eq, "active")
  |> Query.debug(:pipeline)
  |> Query.order(:name, :asc)
  |> Query.debug(:raw_sql)
  |> Query.execute()

  # With options
  Product
  |> Query.new()
  |> Query.filter(:status, :eq, "active")
  |> Query.debug(:raw_sql, label: "After filter", pretty: true)
  |> Query.execute()

  # Multiple formats at once
  token |> Query.debug([:raw_sql, :pipeline])

  # In FacetedSearch
  FacetedSearch.new(Product)
  |> FacetedSearch.search("iphone")
  |> Query.debug(:dsl)
  |> FacetedSearch.execute()
  ```

  ## Options

  - `:label` - Label to print before output (default: "Query Debug")
  - `:pretty` - Pretty print output (default: true)
  - `:io` - IO device to write to (default: :stdio)
  - `:repo` - Repo module for SQL generation (default: inferred or configured default_repo)
  - `:color` - ANSI color for output (default: :cyan)
  - `:stacktrace` - Include stacktrace location (default: false)
  - `:return` - What to return: `:input` (default), `:output`, `:both`
  """

  alias Events.Core.Query.Token
  alias Events.Core.Query.Builder
  alias Events.Core.Query.SyntaxConverter
  alias Events.Core.Query.FacetedSearch

  # Configurable default repo - can be overridden via application config
  @default_repo Application.compile_env(:events, [Events.Core.Query, :default_repo], nil)

  # Note: Ecto.Query not imported - we work with Token and use Builder

  @type format ::
          :raw_sql
          | :sql
          | :sql_params
          | :ecto
          | :dsl
          | :pipeline
          | :token
          | :explain
          | :explain_analyze
          | :all

  @type debug_opts :: [
          label: String.t(),
          pretty: boolean(),
          io: atom(),
          repo: module(),
          color: atom(),
          stacktrace: boolean(),
          return: :input | :output | :both
        ]

  @default_opts [
    label: "Query Debug",
    pretty: true,
    io: :stdio,
    color: :cyan,
    stacktrace: false,
    return: :input
  ]

  @doc """
  Debug a Token, Ecto.Query, or any query-like structure.

  Returns the input unchanged (like IO.inspect) for pipeline composition.

  ## Examples

      # In a pipeline - prints and passes through
      token
      |> Query.filter(:status, :eq, "active")
      |> Query.debug()  # prints SQL, returns token
      |> Query.order(:name, :asc)
      |> Query.execute()

      # Specify format
      Query.debug(token, :pipeline)
      Query.debug(token, :dsl)
      Query.debug(token, [:raw_sql, :token])

      # With options
      Query.debug(token, :raw_sql, label: "Product Query", color: :green)
  """
  @spec debug(Token.t() | Ecto.Query.t() | term(), format() | [format()], debug_opts()) :: term()
  def debug(input, format \\ :raw_sql, opts \\ [])

  def debug(input, opts, []) when is_list(opts) and not is_atom(hd(opts)) do
    # Called as debug(input, opts) - opts is keyword list
    debug(input, :raw_sql, opts)
  end

  def debug(input, format, opts) when is_list(format) do
    # Multiple formats
    merged_opts = Keyword.merge(@default_opts, opts)
    Enum.each(format, fn fmt -> print_format(input, fmt, merged_opts) end)
    return_value(input, merged_opts, format_output(input, format, merged_opts))
  end

  def debug(input, format, opts) when is_atom(format) do
    merged_opts = Keyword.merge(@default_opts, opts)
    output = print_format(input, format, merged_opts)
    return_value(input, merged_opts, output)
  end

  @doc """
  Get debug output as string without printing.

  Useful for logging or testing.

  ## Examples

      sql = Query.Debug.to_string(token, :raw_sql)
      Logger.info("Executing: \#{sql}")
  """
  @spec to_string(Token.t() | Ecto.Query.t(), format(), debug_opts()) :: String.t()
  def to_string(input, format \\ :raw_sql, opts \\ []) do
    format_output(input, format, Keyword.merge(@default_opts, opts))
  end

  @doc """
  Get all debug formats as a map.

  ## Examples

      info = Query.Debug.inspect_all(token)
      # => %{raw_sql: "SELECT ...", pipeline: "User |> ...", ...}
  """
  @spec inspect_all(Token.t() | Ecto.Query.t(), debug_opts()) :: map()
  def inspect_all(input, opts \\ []) do
    merged_opts = Keyword.merge(@default_opts, opts)

    %{
      raw_sql: format_output(input, :raw_sql, merged_opts),
      sql_params: format_output(input, :sql_params, merged_opts),
      ecto: format_output(input, :ecto, merged_opts),
      dsl: format_output(input, :dsl, merged_opts),
      pipeline: format_output(input, :pipeline, merged_opts),
      token: format_output(input, :token, merged_opts)
    }
  end

  # Print formatted output
  defp print_format(input, format, opts) do
    output = format_output(input, format, opts)
    label = opts[:label]
    color = opts[:color]
    io = opts[:io]
    stacktrace = opts[:stacktrace]

    # Build header
    header = format_header(format, label, color)

    # Build location info if requested
    location =
      if stacktrace do
        case Process.info(self(), :current_stacktrace) do
          {:current_stacktrace, stack} ->
            find_caller_location(stack)

          _ ->
            ""
        end
      else
        ""
      end

    # Print
    IO.puts(io, header)

    if location != "" do
      IO.puts(io, colorize("  at #{location}", :light_black))
    end

    IO.puts(io, "")

    if opts[:pretty] do
      IO.puts(io, output)
    else
      IO.write(io, output)
    end

    IO.puts(io, "")
    IO.puts(io, colorize(String.duplicate("─", 60), color))
    IO.puts(io, "")

    output
  end

  # Format output based on type
  defp format_output(input, format, opts)

  # Token input
  defp format_output(%Token{} = token, :raw_sql, opts) do
    case token_to_sql(token, opts) do
      {:ok, sql} -> sql
      {:error, reason} -> "-- Error generating SQL: #{reason}"
    end
  end

  defp format_output(%Token{} = token, :sql, opts) do
    format_output(token, :raw_sql, opts)
  end

  defp format_output(%Token{} = token, :sql_params, opts) do
    case token_to_sql_with_params(token, opts) do
      {:ok, sql, params} ->
        """
        SQL: #{sql}

        Params: #{inspect(params, pretty: true)}
        """

      {:error, reason} ->
        "-- Error: #{reason}"
    end
  end

  defp format_output(%Token{} = token, :ecto, _opts) do
    case token_to_ecto(token) do
      {:ok, query} -> inspect(query, pretty: true, limit: :infinity)
      {:error, reason} -> "-- Error building Ecto query: #{reason}"
    end
  end

  defp format_output(%Token{source: source} = token, :dsl, _opts) do
    schema = extract_schema(source)
    SyntaxConverter.token_to_dsl(token, schema)
  end

  defp format_output(%Token{source: source} = token, :pipeline, _opts) do
    schema = extract_schema(source)
    SyntaxConverter.token_to_pipeline(token, schema)
  end

  defp format_output(%Token{} = token, :token, _opts) do
    """
    %Events.Core.Query.Token{
      source: #{inspect(token.source)},
      operations: #{inspect(token.operations, pretty: true, limit: :infinity)},
      metadata: #{inspect(token.metadata, pretty: true)}
    }
    """
  end

  defp format_output(%Token{} = token, :explain, opts) do
    case explain_query(token, opts, false) do
      {:ok, explain} -> explain
      {:error, reason} -> "-- Error: #{reason}"
    end
  end

  defp format_output(%Token{} = token, :explain_analyze, opts) do
    case explain_query(token, opts, true) do
      {:ok, explain} -> explain
      {:error, reason} -> "-- Error: #{reason}"
    end
  end

  defp format_output(%Token{} = token, :all, opts) do
    formats = [:raw_sql, :sql_params, :ecto, :dsl, :pipeline, :token]

    formats
    |> Enum.map(fn fmt ->
      """
      #{format_header(fmt, nil, opts[:color])}
      #{format_output(token, fmt, opts)}
      """
    end)
    |> Enum.join("\n")
  end

  # Ecto.Query input
  defp format_output(%Ecto.Query{} = query, :raw_sql, opts) do
    repo = get_repo(opts)
    {sql, params} = repo.to_sql(:all, query)
    interpolate_sql(sql, params)
  end

  defp format_output(%Ecto.Query{} = query, :sql, opts) do
    format_output(query, :raw_sql, opts)
  end

  defp format_output(%Ecto.Query{} = query, :sql_params, opts) do
    repo = get_repo(opts)
    {sql, params} = repo.to_sql(:all, query)

    """
    SQL: #{sql}

    Params: #{inspect(params, pretty: true)}
    """
  end

  defp format_output(%Ecto.Query{} = query, :ecto, _opts) do
    inspect(query, pretty: true, limit: :infinity)
  end

  defp format_output(%Ecto.Query{}, :dsl, _opts) do
    "-- DSL conversion not available for raw Ecto.Query"
  end

  defp format_output(%Ecto.Query{}, :pipeline, _opts) do
    "-- Pipeline conversion not available for raw Ecto.Query"
  end

  defp format_output(%Ecto.Query{}, :token, _opts) do
    "-- Token format not available for raw Ecto.Query"
  end

  defp format_output(%Ecto.Query{} = query, :explain, opts) do
    repo = get_repo(opts)

    case repo.explain(:all, query) do
      explain when is_binary(explain) -> explain
      other -> inspect(other, pretty: true)
    end
  rescue
    e -> "-- Error: #{Exception.message(e)}"
  end

  defp format_output(%Ecto.Query{} = query, :explain_analyze, opts) do
    repo = get_repo(opts)

    case repo.explain(:all, query, analyze: true) do
      explain when is_binary(explain) -> explain
      other -> inspect(other, pretty: true)
    end
  rescue
    e -> "-- Error: #{Exception.message(e)}"
  end

  defp format_output(%Ecto.Query{} = query, :all, opts) do
    formats = [:raw_sql, :sql_params, :ecto]

    formats
    |> Enum.map(fn fmt ->
      """
      #{format_header(fmt, nil, opts[:color])}
      #{format_output(query, fmt, opts)}
      """
    end)
    |> Enum.join("\n")
  end

  # FacetedSearch input - convert to token first
  defp format_output(%FacetedSearch{} = builder, format, opts) do
    token = faceted_to_token(builder)
    faceted_header = "-- FacetedSearch (converted to Token)\n"

    case format do
      :faceted ->
        inspect_faceted_search(builder)

      :all ->
        faceted_header <>
          "\n" <> format_output(token, :all, opts) <> "\n\n" <> inspect_faceted_search(builder)

      _ ->
        faceted_header <> format_output(token, format, opts)
    end
  end

  # Unknown input - just inspect
  defp format_output(input, _format, _opts) do
    inspect(input, pretty: true, limit: :infinity)
  end

  # Convert FacetedSearch to Token for debugging
  defp faceted_to_token(%FacetedSearch{
         source: source,
         filters: filters,
         search_config: search_config,
         ordering: ordering,
         preloads: preloads,
         pagination: pagination,
         select_fields: select_fields
       }) do
    alias Events.Core.Query

    # Start with new token
    token = Token.new(source)

    # Apply search if configured
    token =
      case search_config do
        {term, fields, opts} when is_binary(term) and term != "" ->
          Query.search(token, term, fields, opts)

        _ ->
          token
      end

    # Apply filters
    token = Query.filter_by(token, filters)

    # Apply ordering
    token =
      Enum.reduce(ordering, token, fn {field, direction}, acc ->
        Query.order(acc, field, direction)
      end)

    # Apply pagination
    token =
      case pagination do
        {type, opts} -> Query.paginate(token, type, opts)
        _ -> token
      end

    # Apply preloads
    token =
      case preloads do
        [] -> token
        preloads -> Query.preload(token, preloads)
      end

    # Apply select
    case select_fields do
      nil -> token
      fields -> Query.select(token, fields)
    end
  end

  # Pretty print FacetedSearch state
  defp inspect_faceted_search(%FacetedSearch{} = builder) do
    """
    [FACETED SEARCH STATE]
    Source: #{inspect(builder.source)}
    Search: #{inspect(builder.search_config)}
    Filters: #{inspect(builder.filters, pretty: true)}
    Facets: #{inspect(builder.facets, pretty: true)}
    Pagination: #{inspect(builder.pagination)}
    Ordering: #{inspect(builder.ordering)}
    Preloads: #{inspect(builder.preloads)}
    Select: #{inspect(builder.select_fields)}
    """
  end

  # Helper: Convert token to SQL
  defp token_to_sql(%Token{} = token, opts) do
    with {:ok, query} <- token_to_ecto(token) do
      repo = get_repo(opts)
      {sql, params} = repo.to_sql(:all, query)
      {:ok, interpolate_sql(sql, params)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp token_to_sql_with_params(%Token{} = token, opts) do
    with {:ok, query} <- token_to_ecto(token) do
      repo = get_repo(opts)
      {sql, params} = repo.to_sql(:all, query)
      {:ok, sql, params}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Helper: Convert token to Ecto.Query
  defp token_to_ecto(%Token{} = token) do
    query = Builder.build(token)
    {:ok, query}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Helper: Run EXPLAIN
  defp explain_query(%Token{} = token, opts, analyze?) do
    with {:ok, query} <- token_to_ecto(token) do
      repo = get_repo(opts)
      explain_opts = if analyze?, do: [analyze: true], else: []

      case repo.explain(:all, query, explain_opts) do
        explain when is_binary(explain) -> {:ok, explain}
        other -> {:ok, inspect(other, pretty: true)}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Helper: Interpolate params into SQL for readable output
  defp interpolate_sql(sql, params) do
    params
    |> Enum.with_index(1)
    |> Enum.reduce(sql, fn {param, idx}, acc ->
      placeholder = "$#{idx}"
      value = format_sql_value(param)
      String.replace(acc, placeholder, value, global: false)
    end)
  end

  defp format_sql_value(nil), do: "NULL"
  defp format_sql_value(true), do: "TRUE"
  defp format_sql_value(false), do: "FALSE"
  defp format_sql_value(value) when is_binary(value), do: "'#{escape_sql(value)}'"
  defp format_sql_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_sql_value(value) when is_float(value), do: Float.to_string(value)
  defp format_sql_value(%Decimal{} = d), do: Decimal.to_string(d)

  defp format_sql_value(%DateTime{} = dt),
    do: "'#{DateTime.to_iso8601(dt)}'"

  defp format_sql_value(%NaiveDateTime{} = dt),
    do: "'#{NaiveDateTime.to_iso8601(dt)}'"

  defp format_sql_value(%Date{} = d), do: "'#{Date.to_iso8601(d)}'"
  defp format_sql_value(%Time{} = t), do: "'#{Time.to_iso8601(t)}'"

  defp format_sql_value(list) when is_list(list),
    do: "ARRAY[#{Enum.map_join(list, ", ", &format_sql_value/1)}]"

  defp format_sql_value(value), do: inspect(value)

  defp escape_sql(value), do: String.replace(value, "'", "''")

  # Helper: Get repo from opts or config
  defp get_repo(opts) do
    opts[:repo] || Application.get_env(:events, :repo) || @default_repo ||
      raise "No repo configured. Pass :repo option or configure default_repo: config :events, Events.Core.Query, default_repo: MyApp.Repo"
  end

  # Helper: Extract schema from token source
  defp extract_schema(module) when is_atom(module), do: module
  defp extract_schema(%Ecto.Query{from: %{source: {_, schema}}}), do: schema
  defp extract_schema(_), do: :query

  # Helper: Format header
  defp format_header(format, label, color) do
    format_name =
      case format do
        :raw_sql -> "RAW SQL"
        :sql -> "RAW SQL"
        :sql_params -> "SQL + PARAMS"
        :ecto -> "ECTO QUERY"
        :dsl -> "DSL SYNTAX"
        :pipeline -> "PIPELINE SYNTAX"
        :token -> "TOKEN STRUCT"
        :explain -> "EXPLAIN"
        :explain_analyze -> "EXPLAIN ANALYZE"
        :all -> "ALL FORMATS"
        other -> String.upcase(Atom.to_string(other))
      end

    header =
      if label do
        "#{label} [#{format_name}]"
      else
        "[#{format_name}]"
      end

    colorize("═══ #{header} " <> String.duplicate("═", max(0, 55 - String.length(header))), color)
  end

  # Helper: Find caller location in stacktrace
  defp find_caller_location(stack) do
    stack
    |> Enum.find(fn {mod, _fun, _arity, _loc} ->
      mod_string = Atom.to_string(mod)

      not String.starts_with?(mod_string, "Events.Core.Query.Debug") and
        not String.starts_with?(mod_string, "Elixir.Events.Core.Query.Debug") and
        not String.starts_with?(mod_string, ":erlang")
    end)
    |> case do
      {mod, fun, arity, loc} ->
        file = Keyword.get(loc, :file, "unknown")
        line = Keyword.get(loc, :line, 0)
        "#{mod}.#{fun}/#{arity} (#{file}:#{line})"

      _ ->
        ""
    end
  end

  # Helper: ANSI colorization
  defp colorize(text, color) do
    if IO.ANSI.enabled?() do
      [apply(IO.ANSI, color, []), text, IO.ANSI.reset()]
      |> IO.iodata_to_binary()
    else
      text
    end
  end

  # Helper: Return value based on opts
  defp return_value(input, opts, output) do
    case opts[:return] do
      :output -> output
      :both -> {input, output}
      _ -> input
    end
  end
end
