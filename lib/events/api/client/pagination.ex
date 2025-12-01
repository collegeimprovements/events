defmodule Events.Api.Client.Pagination do
  @moduledoc """
  Pagination helpers for API clients.

  Provides utilities for handling paginated API responses, including
  automatic pagination via streams and cursor/offset-based pagination.

  ## Stream-Based Pagination

  The most ergonomic way to handle pagination is via streams:

      # Fetch all customers (auto-paginates)
      Stripe.new(config)
      |> Stripe.customers()
      |> Pagination.stream(&Stripe.list/2)
      |> Enum.take(100)

      # Process in batches
      Stripe.new(config)
      |> Stripe.customers()
      |> Pagination.stream(&Stripe.list/2, batch_size: 50)
      |> Stream.each(&process_batch/1)
      |> Stream.run()

  ## Pagination Strategies

  ### Cursor-Based (Stripe, Slack, etc.)

      Pagination.stream(request, fetcher,
        strategy: :cursor,
        cursor_path: ["data", Access.at(-1), "id"],  # Path to next cursor
        cursor_param: :starting_after,               # Param name for cursor
        has_more_path: ["has_more"]                  # Path to has_more flag
      )

  ### Offset-Based (Traditional APIs)

      Pagination.stream(request, fetcher,
        strategy: :offset,
        offset_param: :offset,
        limit_param: :limit,
        total_path: ["meta", "total"]
      )

  ### Link Header (GitHub, REST APIs)

      Pagination.stream(request, fetcher,
        strategy: :link_header
      )

  ### Page Number (Simple APIs)

      Pagination.stream(request, fetcher,
        strategy: :page,
        page_param: :page,
        per_page: 100
      )

  ## Collecting Results

      # Collect all items
      {:ok, all_items} = Pagination.collect_all(request, fetcher)

      # Collect with limit
      {:ok, items} = Pagination.collect_all(request, fetcher, max_items: 500)
  """

  alias Events.Api.Client.{Request, Response}

  @type strategy :: :cursor | :offset | :link_header | :page
  @type fetcher :: (Request.t(), keyword() -> {:ok, Response.t()} | {:error, term()})
  @type item :: map()

  @default_batch_size 100

  # ============================================
  # Stream API
  # ============================================

  @doc """
  Creates a stream that automatically paginates through results.

  The stream lazily fetches pages as items are consumed, making it
  memory-efficient for large datasets.

  ## Options

  - `:strategy` - Pagination strategy (:cursor, :offset, :link_header, :page). Default: :cursor
  - `:batch_size` - Number of items per page. Default: 100
  - `:max_pages` - Maximum number of pages to fetch. Default: unlimited
  - `:data_path` - Path to items in response. Default: ["data"]
  - `:flatten` - Whether to flatten items from pages. Default: true

  ### Cursor Strategy Options

  - `:cursor_path` - Path to extract next cursor from response
  - `:cursor_param` - Query parameter name for cursor. Default: :starting_after
  - `:has_more_path` - Path to has_more flag. Default: ["has_more"]

  ### Offset Strategy Options

  - `:offset_param` - Query parameter for offset. Default: :offset
  - `:limit_param` - Query parameter for limit. Default: :limit
  - `:total_path` - Path to total count in response

  ### Page Strategy Options

  - `:page_param` - Query parameter for page number. Default: :page
  - `:per_page_param` - Query parameter for per_page. Default: :per_page
  - `:total_pages_path` - Path to total pages in response

  ## Examples

      # Basic usage with cursor pagination
      stream = Pagination.stream(request, &Client.list/2)
      Enum.take(stream, 50)

      # With custom options
      stream = Pagination.stream(request, &Client.list/2,
        strategy: :cursor,
        batch_size: 50,
        cursor_param: :after,
        data_path: ["items"]
      )
  """
  @spec stream(Request.t(), fetcher(), keyword()) :: Enumerable.t()
  def stream(%Request{} = request, fetcher, opts \\ []) when is_function(fetcher, 2) do
    strategy = Keyword.get(opts, :strategy, :cursor)
    flatten = Keyword.get(opts, :flatten, true)

    stream =
      Stream.resource(
        fn -> init_state(request, opts, strategy) end,
        fn state -> next_page(state, fetcher, strategy) end,
        fn _state -> :ok end
      )

    if flatten do
      Stream.flat_map(stream, & &1)
    else
      stream
    end
  end

  @doc """
  Creates a stream that yields pages (batches) instead of individual items.

  Useful when you want to process items in batches.

  ## Examples

      Pagination.stream_pages(request, &Client.list/2)
      |> Stream.each(fn page ->
        Enum.each(page, &process_item/1)
      end)
      |> Stream.run()
  """
  @spec stream_pages(Request.t(), fetcher(), keyword()) :: Enumerable.t()
  def stream_pages(%Request{} = request, fetcher, opts \\ []) do
    stream(request, fetcher, Keyword.put(opts, :flatten, false))
  end

  # ============================================
  # Collection API
  # ============================================

  @doc """
  Collects all paginated results into a list.

  ## Options

  - `:max_items` - Maximum number of items to collect
  - `:max_pages` - Maximum number of pages to fetch
  - All options from `stream/3`

  ## Examples

      {:ok, all_customers} = Pagination.collect_all(request, &Stripe.list/2)
      {:ok, first_500} = Pagination.collect_all(request, &Stripe.list/2, max_items: 500)
  """
  @spec collect_all(Request.t(), fetcher(), keyword()) :: {:ok, [item()]} | {:error, term()}
  def collect_all(%Request{} = request, fetcher, opts \\ []) do
    max_items = Keyword.get(opts, :max_items, :infinity)

    try do
      items =
        request
        |> stream(fetcher, opts)
        |> maybe_take(max_items)
        |> Enum.to_list()

      {:ok, items}
    rescue
      e -> {:error, e}
    catch
      {:pagination_error, reason} -> {:error, reason}
    end
  end

  defp maybe_take(stream, :infinity), do: stream
  defp maybe_take(stream, n), do: Stream.take(stream, n)

  @doc """
  Fetches a single page of results.

  ## Options

  - `:cursor` - Cursor for cursor-based pagination
  - `:offset` - Offset for offset-based pagination
  - `:page` - Page number for page-based pagination
  - `:limit` - Number of items per page

  ## Examples

      {:ok, %{items: items, next_cursor: cursor, has_more: true}} =
        Pagination.fetch_page(request, &Client.list/2, limit: 50)

      {:ok, %{items: more_items, ...}} =
        Pagination.fetch_page(request, &Client.list/2, cursor: cursor, limit: 50)
  """
  @spec fetch_page(Request.t(), fetcher(), keyword()) ::
          {:ok, %{items: [item()], next_cursor: term(), has_more: boolean()}} | {:error, term()}
  def fetch_page(%Request{} = request, fetcher, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :cursor)
    data_path = Keyword.get(opts, :data_path, ["data"])

    params = build_page_params(opts, strategy)

    case fetcher.(request, params) do
      {:ok, %Response{} = response} ->
        items = get_in(response.body, data_path) || []
        {has_more, next_cursor} = extract_pagination_info(response, opts, strategy)

        {:ok, %{items: items, next_cursor: next_cursor, has_more: has_more}}

      {:error, _} = error ->
        error
    end
  end

  # ============================================
  # Helpers for Custom Implementations
  # ============================================

  @doc """
  Extracts the next cursor from a response.

  ## Examples

      cursor = Pagination.extract_cursor(response, path: ["data", Access.at(-1), "id"])
  """
  @spec extract_cursor(Response.t() | map(), keyword()) :: term()
  def extract_cursor(%Response{body: body}, opts), do: extract_cursor(body, opts)

  def extract_cursor(body, opts) when is_map(body) do
    path = Keyword.get(opts, :path, ["data", Access.at(-1), "id"])
    get_in(body, path)
  end

  @doc """
  Parses a Link header for pagination URLs.

  ## Examples

      links = Pagination.parse_link_header(response)
      #=> %{next: "https://api.example.com/items?page=2", prev: nil, first: "...", last: "..."}
  """
  @spec parse_link_header(Response.t() | String.t()) :: %{
          next: String.t() | nil,
          prev: String.t() | nil,
          first: String.t() | nil,
          last: String.t() | nil
        }
  def parse_link_header(%Response{} = response) do
    link_header = Response.get_header(response, "link") || ""
    parse_link_header(link_header)
  end

  def parse_link_header(header) when is_binary(header) do
    links =
      header
      |> String.split(",")
      |> Enum.map(&parse_link_part/1)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    %{
      next: Map.get(links, "next"),
      prev: Map.get(links, "prev"),
      first: Map.get(links, "first"),
      last: Map.get(links, "last")
    }
  end

  defp parse_link_part(part) do
    case Regex.run(~r/<([^>]+)>;\s*rel="([^"]+)"/, String.trim(part)) do
      [_, url, rel] -> {rel, url}
      _ -> nil
    end
  end

  # ============================================
  # Private: Stream Implementation
  # ============================================

  defp init_state(request, opts, strategy) do
    %{
      request: request,
      opts: opts,
      strategy: strategy,
      cursor: nil,
      offset: 0,
      page: 1,
      pages_fetched: 0,
      max_pages: Keyword.get(opts, :max_pages, :infinity),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      done: false
    }
  end

  defp next_page(%{done: true} = state, _fetcher, _strategy), do: {:halt, state}

  defp next_page(state, _fetcher, _strategy)
       when state.max_pages != :infinity and state.pages_fetched >= state.max_pages do
    {:halt, state}
  end

  defp next_page(state, fetcher, strategy) do
    params = build_params(state, strategy)

    case fetcher.(state.request, params) do
      {:ok, %Response{} = response} ->
        data_path = Keyword.get(state.opts, :data_path, ["data"])
        items = get_in(response.body, data_path) || []
        {has_more, next_cursor} = extract_pagination_info(response, state.opts, strategy)

        new_state =
          state
          |> Map.put(:pages_fetched, state.pages_fetched + 1)
          |> Map.put(:done, not has_more or Enum.empty?(items))
          |> update_pagination_state(next_cursor, strategy)

        {[items], new_state}

      {:error, reason} ->
        throw({:pagination_error, reason})
    end
  end

  defp build_params(state, :cursor) do
    params = [limit: state.batch_size]
    cursor_param = Keyword.get(state.opts, :cursor_param, :starting_after)

    case state.cursor do
      nil -> params
      cursor -> Keyword.put(params, cursor_param, cursor)
    end
  end

  defp build_params(state, :offset) do
    limit_param = Keyword.get(state.opts, :limit_param, :limit)
    offset_param = Keyword.get(state.opts, :offset_param, :offset)

    [{limit_param, state.batch_size}, {offset_param, state.offset}]
  end

  defp build_params(state, :page) do
    page_param = Keyword.get(state.opts, :page_param, :page)
    per_page_param = Keyword.get(state.opts, :per_page_param, :per_page)

    [{page_param, state.page}, {per_page_param, state.batch_size}]
  end

  defp build_params(state, :link_header) do
    # For link header, we use the URL directly on subsequent requests
    [limit: state.batch_size]
  end

  defp build_page_params(opts, :cursor) do
    params = [limit: Keyword.get(opts, :limit, @default_batch_size)]
    cursor_param = Keyword.get(opts, :cursor_param, :starting_after)

    case Keyword.get(opts, :cursor) do
      nil -> params
      cursor -> Keyword.put(params, cursor_param, cursor)
    end
  end

  defp build_page_params(opts, :offset) do
    limit_param = Keyword.get(opts, :limit_param, :limit)
    offset_param = Keyword.get(opts, :offset_param, :offset)

    [
      {limit_param, Keyword.get(opts, :limit, @default_batch_size)},
      {offset_param, Keyword.get(opts, :offset, 0)}
    ]
  end

  defp build_page_params(opts, :page) do
    page_param = Keyword.get(opts, :page_param, :page)
    per_page_param = Keyword.get(opts, :per_page_param, :per_page)

    [
      {page_param, Keyword.get(opts, :page, 1)},
      {per_page_param, Keyword.get(opts, :limit, @default_batch_size)}
    ]
  end

  defp build_page_params(opts, :link_header) do
    [limit: Keyword.get(opts, :limit, @default_batch_size)]
  end

  defp extract_pagination_info(response, opts, :cursor) do
    has_more_path = Keyword.get(opts, :has_more_path, ["has_more"])
    cursor_path = Keyword.get(opts, :cursor_path, ["data", Access.at(-1), "id"])

    has_more = get_in(response.body, has_more_path) == true
    cursor = get_in(response.body, cursor_path)

    {has_more, cursor}
  end

  defp extract_pagination_info(response, opts, :offset) do
    total_path = Keyword.get(opts, :total_path)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    data_path = Keyword.get(opts, :data_path, ["data"])

    items = get_in(response.body, data_path) || []
    current_count = length(items)

    has_more =
      case total_path do
        nil -> current_count >= batch_size
        path -> get_in(response.body, path) > 0
      end

    {has_more, nil}
  end

  defp extract_pagination_info(response, _opts, :link_header) do
    links = parse_link_header(response)
    has_more = links.next != nil
    {has_more, links.next}
  end

  defp extract_pagination_info(response, opts, :page) do
    total_pages_path = Keyword.get(opts, :total_pages_path)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    data_path = Keyword.get(opts, :data_path, ["data"])

    items = get_in(response.body, data_path) || []
    current_count = length(items)

    has_more =
      case total_pages_path do
        nil -> current_count >= batch_size
        path -> get_in(response.body, path) > 0
      end

    {has_more, nil}
  end

  defp update_pagination_state(state, cursor, :cursor), do: %{state | cursor: cursor}

  defp update_pagination_state(state, _cursor, :offset),
    do: %{state | offset: state.offset + state.batch_size}

  defp update_pagination_state(state, _cursor, :page), do: %{state | page: state.page + 1}
  defp update_pagination_state(state, next_url, :link_header), do: %{state | cursor: next_url}
end
