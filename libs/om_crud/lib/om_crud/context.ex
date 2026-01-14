defmodule OmCrud.Context do
  @moduledoc """
  Context-level CRUD integration for generating resource functions.

  This module provides macros to generate standard CRUD functions for schemas
  within context modules, reducing boilerplate while maintaining explicit control.

  ## Usage

      defmodule MyApp.Accounts do
        use OmCrud.Context

        # Generate all CRUD functions with defaults
        crud User

        # Customize with options
        crud Role,
          only: [:create, :fetch, :update],
          default_limit: 50,
          max_limit: 200

        # With custom preloads
        crud Membership, preload: [:account, :user]
      end

  ## Generated Functions

  For each schema, the following functions are generated:

  ### Read Operations
  - `fetch_<resource>(id, opts)` - Returns `{:ok, record}` or `{:error, :not_found}`
  - `fetch_<resource>!(id, opts)` - Returns record or raises `Ecto.NoResultsError`
  - `get_<resource>(id, opts)` - Returns record or `nil`
  - `list_<resources>(opts)` - Returns `{:ok, %OmCrud.Result{}}` with cursor pagination
  - `filter_<resources>(filters, opts)` - Returns `{:ok, %OmCrud.Result{}}` with filters
  - `count_<resources>(opts)` - Returns `{:ok, count}`
  - `first_<resource>(opts)` - Returns `{:ok, record}` or `{:error, :not_found}`
  - `first_<resource>!(opts)` - Returns record or raises
  - `last_<resource>(opts)` - Returns `{:ok, record}` or `{:error, :not_found}`
  - `last_<resource>!(opts)` - Returns record or raises
  - `<resource>_exists?(id_or_filters)` - Returns boolean
  - `stream_<resources>(opts)` - Returns `Stream.t()`

  ### Write Operations
  - `create_<resource>(attrs, opts)` - Creates a record
  - `create_<resource>!(attrs, opts)` - Creates or raises `Ecto.InvalidChangesetError`
  - `update_<resource>(record, attrs, opts)` - Updates a record
  - `update_<resource>!(record, attrs, opts)` - Updates or raises
  - `delete_<resource>(record, opts)` - Deletes a record
  - `delete_<resource>!(record, opts)` - Deletes or raises

  ### Bulk Operations
  - `create_all_<resources>(entries, opts)` - Bulk insert
  - `update_all_<resources>(filters, changes, opts)` - Bulk update with filters
  - `delete_all_<resources>(filters, opts)` - Bulk delete with filters

  ## Crud Macro Options

  ### Function Generation
  - `:only` - List of functions to generate
  - `:except` - List of functions to exclude
  - `:as` - Override the resource name
  - `:bang` - Generate bang variants (default: `true`)
  - `:filterable` - Generate `filter_*` functions (default: `true`)

  ### Pagination
  - `:pagination` - `:cursor` (default), `:offset`, or `false`
  - `:default_limit` - Default page size (default: `20`)
  - `:max_limit` - Maximum allowed limit (default: `100`)

  ### Query Defaults
  - `:order_by` - Default ordering (default: `[desc: :inserted_at, asc: :id]`)
  - `:cursor_fields` - Fields for cursor pagination (default: `[:inserted_at, :id]`)
  - `:preload` - Default associations to preload
  - `:batch_size` - Default batch size for streaming (default: `500`)

  ### Execution Options
  - `:repo` - Default repository module
  - `:timeout` - Default timeout in milliseconds
  - `:prefix` - Schema prefix for multi-tenancy
  - `:log` - Logging level or `false` to disable

  ## Result Format

  List and filter operations return `%OmCrud.Result{}`:

      {:ok, %OmCrud.Result{
        data: [%User{}, ...],
        pagination: %OmCrud.Pagination{
          type: :cursor,
          has_more: true,
          has_previous: false,
          start_cursor: "eyJpZCI6...",
          end_cursor: "eyJpZCI6...",
          limit: 20
        }
      }}

  ## Overriding Generated Functions

  All generated functions are marked as `defoverridable`:

      defmodule MyApp.Accounts do
        use OmCrud.Context

        crud User

        # Override with custom logic
        def create_user(attrs, opts \\\\ []) do
          attrs
          |> Map.put(:created_by, opts[:current_user_id])
          |> then(&OmCrud.create(User, &1, opts))
        end
      end
  """

  # Aliases used in generated code - referenced with full module name
  # OmCrud.Result, OmCrud.Pagination, OmCrud.Telemetry

  @doc false
  defmacro __using__(_opts) do
    quote do
      import OmCrud.Context, only: [crud: 1, crud: 2]

      # Shared helper functions for all crud macros
      @doc false
      def __apply_crud_filters__(query, []), do: query

      def __apply_crud_filters__(query, filters) do
        Enum.reduce(filters, query, fn
          {field, op, value, filter_opts}, q ->
            OmQuery.filter(q, field, op, value, filter_opts)

          {field, op, value}, q ->
            OmQuery.filter(q, field, op, value)
        end)
      end

      @doc false
      def __apply_crud_query_opts__(query, opts) do
        query
        |> apply_opt_if_present(opts, :select, &OmQuery.select/2)
        |> apply_opt_if_present(opts, :distinct, &OmQuery.distinct/2)
        |> apply_opt_if_present(opts, :lock, &OmQuery.lock/2)
      end

      defp apply_opt_if_present(query, opts, key, apply_fn) do
        case opts[key] do
          nil -> query
          value -> apply_fn.(query, value)
        end
      end

      @doc false
      def __preload_crud_records__(records, [], _opts), do: records

      def __preload_crud_records__(records, preloads, opts) do
        repo = OmCrud.Options.repo(opts)
        repo.preload(records, preloads)
      end

      @doc false
      def __reverse_crud_order__(order_by) do
        Enum.map(order_by, fn
          {:asc, field} -> {:desc, field}
          {:desc, field} -> {:asc, field}
          {field, :asc} -> {field, :desc}
          {field, :desc} -> {field, :asc}
        end)
      end

      @doc false
      def __maybe_add_changeset__(opts, nil), do: opts
      def __maybe_add_changeset__(opts, changeset), do: Keyword.put_new(opts, :changeset, changeset)
    end
  end

  @doc """
  Generate CRUD functions for a schema.

  See module documentation for full list of options.
  """
  defmacro crud(schema, opts \\ []) do
    schema_mod = Macro.expand(schema, __CALLER__)
    resource = resource_name(schema_mod, opts)
    resources = pluralize(resource)

    # Extract all configuration
    functions = determine_functions(opts)
    default_preload = Keyword.get(opts, :preload, [])
    default_changeset = Keyword.get(opts, :changeset)
    generate_bang = Keyword.get(opts, :bang, true)
    filterable = Keyword.get(opts, :filterable, true)

    # Pagination options
    default_limit = Keyword.get(opts, :default_limit, 20)
    max_limit = Keyword.get(opts, :max_limit, 100)
    order_by = Keyword.get(opts, :order_by, [desc: :inserted_at, asc: :id])
    cursor_fields = Keyword.get(opts, :cursor_fields, [:inserted_at, :id])
    batch_size = Keyword.get(opts, :batch_size, 500)

    # Crud-level defaults for repo operations
    default_opts =
      opts
      |> Keyword.take([:repo, :timeout, :prefix, :log])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    # Build config map for generated functions
    config = %{
      schema: schema_mod,
      default_preload: default_preload,
      default_changeset: default_changeset,
      default_opts: default_opts,
      default_limit: default_limit,
      max_limit: max_limit,
      order_by: order_by,
      cursor_fields: cursor_fields,
      batch_size: batch_size
    }

    # Generate function definitions
    function_defs =
      functions
      |> Enum.flat_map(fn fun ->
        generate_function(fun, schema_mod, resource, resources, config, generate_bang, filterable)
      end)

    # Build overridable declarations
    overridable_fns = build_overridable_list(functions, resource, resources, generate_bang, filterable)

    quote do
      unquote_splicing(function_defs)
      defoverridable unquote(overridable_fns)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────

  defp resource_name(schema, opts) do
    case Keyword.get(opts, :as) do
      nil ->
        schema
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()

      name when is_atom(name) ->
        name
    end
  end

  defp pluralize(name) when is_atom(name) do
    str = Atom.to_string(name)

    pluralized =
      cond do
        String.ends_with?(str, "y") and not String.ends_with?(str, ["ay", "ey", "iy", "oy", "uy"]) ->
          String.slice(str, 0..-2//1) <> "ies"

        String.ends_with?(str, ["s", "x", "z", "ch", "sh"]) ->
          str <> "es"

        true ->
          str <> "s"
      end

    String.to_atom(pluralized)
  end

  @all_functions [
    :fetch,
    :get,
    :list,
    :filter,
    :count,
    :first,
    :last,
    :exists?,
    :stream,
    :create,
    :update,
    :delete,
    :create_all,
    :update_all,
    :delete_all
  ]

  defp determine_functions(opts) do
    case {Keyword.get(opts, :only), Keyword.get(opts, :except)} do
      {nil, nil} -> @all_functions
      {only, nil} when is_list(only) -> Enum.filter(@all_functions, &(&1 in only))
      {nil, except} when is_list(except) -> Enum.reject(@all_functions, &(&1 in except))
      _ -> @all_functions
    end
  end

  defp build_overridable_list(functions, resource, resources, generate_bang, filterable) do
    Enum.flat_map(functions, fn
      :fetch ->
        base = [{:"fetch_#{resource}", 1}, {:"fetch_#{resource}", 2}]
        maybe_add_bang(base, generate_bang, [{:"fetch_#{resource}!", 1}, {:"fetch_#{resource}!", 2}])

      :get ->
        [{:"get_#{resource}", 1}, {:"get_#{resource}", 2}]

      :list ->
        [{:"list_#{resources}", 0}, {:"list_#{resources}", 1}]

      :filter when filterable ->
        [{:"filter_#{resources}", 1}, {:"filter_#{resources}", 2}]

      :filter ->
        []

      :count ->
        [{:"count_#{resources}", 0}, {:"count_#{resources}", 1}]

      :first ->
        base = [{:"first_#{resource}", 0}, {:"first_#{resource}", 1}]
        maybe_add_bang(base, generate_bang, [{:"first_#{resource}!", 0}, {:"first_#{resource}!", 1}])

      :last ->
        base = [{:"last_#{resource}", 0}, {:"last_#{resource}", 1}]
        maybe_add_bang(base, generate_bang, [{:"last_#{resource}!", 0}, {:"last_#{resource}!", 1}])

      :exists? ->
        [{:"#{resource}_exists?", 1}, {:"#{resource}_exists?", 2}]

      :stream ->
        [{:"stream_#{resources}", 0}, {:"stream_#{resources}", 1}]

      :create ->
        base = [{:"create_#{resource}", 1}, {:"create_#{resource}", 2}]
        maybe_add_bang(base, generate_bang, [{:"create_#{resource}!", 1}, {:"create_#{resource}!", 2}])

      :update ->
        base = [{:"update_#{resource}", 2}, {:"update_#{resource}", 3}]
        maybe_add_bang(base, generate_bang, [{:"update_#{resource}!", 2}, {:"update_#{resource}!", 3}])

      :delete ->
        base = [{:"delete_#{resource}", 1}, {:"delete_#{resource}", 2}]
        maybe_add_bang(base, generate_bang, [{:"delete_#{resource}!", 1}, {:"delete_#{resource}!", 2}])

      :create_all ->
        [{:"create_all_#{resources}", 1}, {:"create_all_#{resources}", 2}]

      :update_all ->
        [{:"update_all_#{resources}", 2}, {:"update_all_#{resources}", 3}]

      :delete_all ->
        [{:"delete_all_#{resources}", 1}, {:"delete_all_#{resources}", 2}]
    end)
    |> Enum.uniq()
  end

  defp maybe_add_bang(fns, false, _bang_fns), do: fns
  defp maybe_add_bang(fns, true, bang_fns), do: fns ++ bang_fns

  # ─────────────────────────────────────────────────────────────
  # Function Generators
  # ─────────────────────────────────────────────────────────────

  defp generate_function(:fetch, schema, resource, _resources, config, generate_bang, _filterable) do
    fn_name = :"fetch_#{resource}"
    bang_name = :"fetch_#{resource}!"
    default_opts = Macro.escape(config.default_opts)
    default_preload = Macro.escape(config.default_preload)

    base = [
      quote do
        @doc "Fetch a #{unquote(resource)} by ID. Returns `{:ok, record}` or `{:error, :not_found}`."
        @spec unquote(fn_name)(binary(), keyword()) :: {:ok, struct()} | {:error, :not_found}
        def unquote(fn_name)(id, opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          opts = Keyword.put_new(opts, :preload, unquote(default_preload))

          OmCrud.Telemetry.span(:fetch, %{schema: unquote(schema), id: id}, fn ->
            OmCrud.fetch(unquote(schema), id, opts)
          end)
        end
      end
    ]

    bang = generate_bang_function(generate_bang, fn ->
      quote do
        @doc "Fetch a #{unquote(resource)} by ID. Returns record or raises `Ecto.NoResultsError`."
        @spec unquote(bang_name)(binary(), keyword()) :: struct()
        def unquote(bang_name)(id, opts \\ []) do
          case unquote(fn_name)(id, opts) do
            {:ok, record} -> record
            {:error, :not_found} -> raise Ecto.NoResultsError, queryable: unquote(schema)
          end
        end
      end
    end)

    base ++ bang
  end

  defp generate_function(:get, schema, resource, _resources, config, _generate_bang, _filterable) do
    fn_name = :"get_#{resource}"
    default_opts = Macro.escape(config.default_opts)
    default_preload = Macro.escape(config.default_preload)

    [
      quote do
        @doc "Get a #{unquote(resource)} by ID. Returns the record or `nil`."
        @spec unquote(fn_name)(binary(), keyword()) :: struct() | nil
        def unquote(fn_name)(id, opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          opts = Keyword.put_new(opts, :preload, unquote(default_preload))

          OmCrud.Telemetry.span(:get, %{schema: unquote(schema), id: id}, fn ->
            OmCrud.get(unquote(schema), id, opts)
          end)
        end
      end
    ]
  end

  defp generate_function(:list, schema, _resource, resources, config, _generate_bang, _filterable) do
    fn_name = :"list_#{resources}"
    default_opts = Macro.escape(config.default_opts)
    default_preload = Macro.escape(config.default_preload)
    default_limit = config.default_limit
    max_limit = config.max_limit
    order_by = Macro.escape(config.order_by)
    cursor_fields = Macro.escape(config.cursor_fields)

    [
      quote do
        @doc """
        List #{unquote(resources)} with cursor pagination.

        Returns `{:ok, %OmCrud.Result{}}` with data and pagination metadata.

        ## Options

        - `:limit` - Page size (default: #{unquote(default_limit)}, max: #{unquote(max_limit)})
        - `:limit` as `:all` - Return all records (no pagination)
        - `:after` - Cursor for next page
        - `:before` - Cursor for previous page
        - `:filters` - List of filter tuples `[{field, op, value}]`
        - `:preload` - Associations to preload
        - `:order_by` - Custom ordering (overrides default)
        - `:select` - Fields to select
        - `:distinct` - Enable distinct
        - `:lock` - Row locking mode (`:for_update`, `:for_share`)
        """
        @spec unquote(fn_name)(keyword()) :: {:ok, OmCrud.Result.t()}
        def unquote(fn_name)(opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)

          filters = Keyword.get(opts, :filters, [])
          preload = Keyword.get(opts, :preload, unquote(default_preload))
          order_by = Keyword.get(opts, :order_by, unquote(order_by))
          cursor_fields = Keyword.get(opts, :cursor_fields, unquote(cursor_fields))

          limit =
            case Keyword.get(opts, :limit, unquote(default_limit)) do
              :all -> :all
              n when is_integer(n) -> min(n, unquote(max_limit))
            end

          OmCrud.Telemetry.span(:list, %{schema: unquote(schema), filters: filters, limit: limit}, fn ->
            query =
              unquote(schema)
              |> OmQuery.new()
              |> __apply_crud_filters__(filters)
              |> __apply_crud_query_opts__(opts)

            case limit do
              :all ->
                query = OmQuery.orders(query, order_by)
                records = OmQuery.all(query, opts)
                records = __preload_crud_records__(records, preload, opts)
                {:ok, OmCrud.Result.all(records)}

              limit when is_integer(limit) ->
                query =
                  query
                  |> OmQuery.paginate(:cursor,
                    cursor_fields: cursor_fields,
                    limit: limit + 1,
                    after: opts[:after],
                    before: opts[:before]
                  )
                  |> OmQuery.orders(order_by)

                records = OmQuery.all(query, opts)
                records = __preload_crud_records__(records, preload, opts)

                pagination =
                  OmCrud.Pagination.from_records(records, cursor_fields, limit,
                    fetched_extra: true,
                    has_previous: opts[:after] != nil
                  )

                records = Enum.take(records, limit)
                {:ok, OmCrud.Result.new(records, pagination)}
            end
          end)
        end
      end
    ]
  end

  defp generate_function(:filter, _schema, _resource, resources, _config, _generate_bang, true = _filterable) do
    fn_name = :"filter_#{resources}"
    list_fn = :"list_#{resources}"

    [
      quote do
        @doc """
        Filter #{unquote(resources)} with cursor pagination.

        Convenience wrapper around `#{unquote(list_fn)}/1` with filters.

        ## Examples

            #{unquote(fn_name)}([{:status, :eq, :active}])
            #{unquote(fn_name)}([{:email, :ilike, "%@corp.com"}], preload: [:account])
        """
        @spec unquote(fn_name)([tuple()], keyword()) :: {:ok, OmCrud.Result.t()}
        def unquote(fn_name)(filters, opts \\ []) when is_list(filters) do
          unquote(list_fn)(Keyword.put(opts, :filters, filters))
        end
      end
    ]
  end

  defp generate_function(:filter, _schema, _resource, _resources, _config, _generate_bang, false) do
    []
  end

  defp generate_function(:count, schema, _resource, resources, config, _generate_bang, _filterable) do
    fn_name = :"count_#{resources}"
    default_opts = Macro.escape(config.default_opts)

    [
      quote do
        @doc """
        Count #{unquote(resources)}.

        ## Options

        - `:filters` - List of filter tuples
        """
        @spec unquote(fn_name)(keyword()) :: {:ok, non_neg_integer()}
        def unquote(fn_name)(opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          filters = Keyword.get(opts, :filters, [])

          OmCrud.Telemetry.span(:count, %{schema: unquote(schema), filters: filters}, fn ->
            count =
              unquote(schema)
              |> OmQuery.new()
              |> __apply_crud_filters__(filters)
              |> OmQuery.count(opts)

            {:ok, count}
          end)
        end
      end
    ]
  end

  defp generate_function(:first, schema, resource, _resources, config, generate_bang, _filterable) do
    fn_name = :"first_#{resource}"
    bang_name = :"first_#{resource}!"
    default_opts = Macro.escape(config.default_opts)
    default_preload = Macro.escape(config.default_preload)
    order_by = Macro.escape(config.order_by)

    base = [
      quote do
        @doc "Get the first #{unquote(resource)} by default ordering. Returns `{:ok, record}` or `{:error, :not_found}`."
        @spec unquote(fn_name)(keyword()) :: {:ok, struct()} | {:error, :not_found}
        def unquote(fn_name)(opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          filters = Keyword.get(opts, :filters, [])
          preload = Keyword.get(opts, :preload, unquote(default_preload))
          order_by = Keyword.get(opts, :order_by, unquote(order_by))

          OmCrud.Telemetry.span(:first, %{schema: unquote(schema), filters: filters}, fn ->
            result =
              unquote(schema)
              |> OmQuery.new()
              |> __apply_crud_filters__(filters)
              |> OmQuery.orders(order_by)
              |> OmQuery.first(opts)

            case result do
              nil ->
                {:error, :not_found}

              record ->
                record = __preload_crud_records__([record], preload, opts) |> List.first()
                {:ok, record}
            end
          end)
        end
      end
    ]

    bang = generate_bang_function(generate_bang, fn ->
      quote do
        @doc "Get the first #{unquote(resource)} or raise."
        @spec unquote(bang_name)(keyword()) :: struct()
        def unquote(bang_name)(opts \\ []) do
          case unquote(fn_name)(opts) do
            {:ok, record} -> record
            {:error, :not_found} -> raise Ecto.NoResultsError, queryable: unquote(schema)
          end
        end
      end
    end)

    base ++ bang
  end

  defp generate_function(:last, schema, resource, _resources, config, generate_bang, _filterable) do
    fn_name = :"last_#{resource}"
    bang_name = :"last_#{resource}!"
    default_opts = Macro.escape(config.default_opts)
    default_preload = Macro.escape(config.default_preload)
    order_by = Macro.escape(config.order_by)

    base = [
      quote do
        @doc "Get the last #{unquote(resource)} by default ordering. Returns `{:ok, record}` or `{:error, :not_found}`."
        @spec unquote(fn_name)(keyword()) :: {:ok, struct()} | {:error, :not_found}
        def unquote(fn_name)(opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          filters = Keyword.get(opts, :filters, [])
          preload = Keyword.get(opts, :preload, unquote(default_preload))
          order_by = Keyword.get(opts, :order_by, unquote(order_by)) |> __reverse_crud_order__()

          OmCrud.Telemetry.span(:last, %{schema: unquote(schema), filters: filters}, fn ->
            result =
              unquote(schema)
              |> OmQuery.new()
              |> __apply_crud_filters__(filters)
              |> OmQuery.orders(order_by)
              |> OmQuery.first(opts)

            case result do
              nil ->
                {:error, :not_found}

              record ->
                record = __preload_crud_records__([record], preload, opts) |> List.first()
                {:ok, record}
            end
          end)
        end
      end
    ]

    bang = generate_bang_function(generate_bang, fn ->
      quote do
        @doc "Get the last #{unquote(resource)} or raise."
        @spec unquote(bang_name)(keyword()) :: struct()
        def unquote(bang_name)(opts \\ []) do
          case unquote(fn_name)(opts) do
            {:ok, record} -> record
            {:error, :not_found} -> raise Ecto.NoResultsError, queryable: unquote(schema)
          end
        end
      end
    end)

    base ++ bang
  end

  defp generate_function(:exists?, schema, resource, _resources, config, _generate_bang, _filterable) do
    fn_name = :"#{resource}_exists?"
    default_opts = Macro.escape(config.default_opts)

    [
      quote do
        @doc """
        Check if a #{unquote(resource)} exists.

        Accepts either an ID or a list of filters.

        ## Examples

            #{unquote(fn_name)}("uuid")
            #{unquote(fn_name)}([{:email, :eq, "test@example.com"}])
        """
        @spec unquote(fn_name)(binary() | list(), keyword()) :: boolean()
        def unquote(fn_name)(id_or_filters, opts \\ [])

        def unquote(fn_name)(id, opts) when is_binary(id) do
          opts = Keyword.merge(unquote(default_opts), opts)

          OmCrud.Telemetry.span(:exists, %{schema: unquote(schema), id: id}, fn ->
            OmCrud.exists?(unquote(schema), id, opts)
          end)
        end

        def unquote(fn_name)(filters, opts) when is_list(filters) do
          opts = Keyword.merge(unquote(default_opts), opts)

          OmCrud.Telemetry.span(:exists, %{schema: unquote(schema), filters: filters}, fn ->
            unquote(schema)
            |> OmQuery.new()
            |> __apply_crud_filters__(filters)
            |> OmQuery.exists?(opts)
          end)
        end
      end
    ]
  end

  defp generate_function(:stream, schema, _resource, resources, config, _generate_bang, _filterable) do
    fn_name = :"stream_#{resources}"
    default_opts = Macro.escape(config.default_opts)
    batch_size = config.batch_size
    order_by = Macro.escape(config.order_by)

    [
      quote do
        @doc """
        Stream #{unquote(resources)} for memory-efficient iteration.

        ## Options

        - `:batch_size` - Records per batch (default: #{unquote(batch_size)})
        - `:filters` - List of filter tuples
        - `:order_by` - Custom ordering
        """
        @spec unquote(fn_name)(keyword()) :: Enumerable.t()
        def unquote(fn_name)(opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          filters = Keyword.get(opts, :filters, [])
          order_by = Keyword.get(opts, :order_by, unquote(order_by))
          batch_size = Keyword.get(opts, :batch_size, unquote(batch_size))

          start_time = OmCrud.Telemetry.start(:stream, %{schema: unquote(schema), filters: filters})

          stream =
            unquote(schema)
            |> OmQuery.new()
            |> __apply_crud_filters__(filters)
            |> OmQuery.orders(order_by)
            |> OmQuery.stream(Keyword.put(opts, :max_rows, batch_size))

          Stream.concat([stream, []])
          |> Stream.transform(0, fn
            [], count ->
              OmCrud.Telemetry.stop(:stream, start_time, %{schema: unquote(schema), count: count})
              {:halt, count}

            item, count ->
              {[item], count + 1}
          end)
        end
      end
    ]
  end

  defp generate_function(:create, schema, resource, _resources, config, generate_bang, _filterable) do
    fn_name = :"create_#{resource}"
    bang_name = :"create_#{resource}!"
    default_opts = Macro.escape(config.default_opts)
    default_changeset = config.default_changeset
    default_preload = Macro.escape(config.default_preload)

    base = [
      quote do
        @doc """
        Create a new #{unquote(resource)}.

        Returns `{:ok, record}` or `{:error, changeset}`.

        ## Options

        - `:changeset` - Custom changeset function name
        - `:reload` - Preloads to apply after creation
        """
        @spec unquote(fn_name)(map(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
        def unquote(fn_name)(attrs, opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          opts = __maybe_add_changeset__(opts, unquote(default_changeset))

          OmCrud.Telemetry.span(:create, %{schema: unquote(schema)}, fn ->
            result = OmCrud.create(unquote(schema), attrs, opts)

            case {result, opts[:reload]} do
              {{:ok, record}, preloads} when is_list(preloads) and preloads != [] ->
                repo = OmCrud.Options.repo(opts)
                {:ok, repo.preload(record, preloads)}

              {{:ok, record}, true} ->
                repo = OmCrud.Options.repo(opts)
                {:ok, repo.preload(record, unquote(default_preload))}

              _ ->
                result
            end
          end)
        end
      end
    ]

    bang = generate_bang_function(generate_bang, fn ->
      quote do
        @doc "Create a new #{unquote(resource)} or raise."
        @spec unquote(bang_name)(map(), keyword()) :: struct()
        def unquote(bang_name)(attrs, opts \\ []) do
          case unquote(fn_name)(attrs, opts) do
            {:ok, record} ->
              record

            {:error, %Ecto.Changeset{} = changeset} ->
              raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
          end
        end
      end
    end)

    base ++ bang
  end

  defp generate_function(:update, schema, resource, _resources, config, generate_bang, _filterable) do
    fn_name = :"update_#{resource}"
    bang_name = :"update_#{resource}!"
    default_opts = Macro.escape(config.default_opts)
    default_changeset = config.default_changeset
    default_preload = Macro.escape(config.default_preload)

    base = [
      quote do
        @doc """
        Update a #{unquote(resource)}.

        Returns `{:ok, record}` or `{:error, changeset}`.

        ## Options

        - `:changeset` - Custom changeset function name
        - `:reload` - Preloads to apply after update
        - `:force` - Fields to mark as changed
        """
        @spec unquote(fn_name)(struct(), map(), keyword()) ::
                {:ok, struct()} | {:error, Ecto.Changeset.t()}
        def unquote(fn_name)(record, attrs, opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)
          opts = __maybe_add_changeset__(opts, unquote(default_changeset))

          OmCrud.Telemetry.span(:update, %{schema: unquote(schema), id: record.id}, fn ->
            result = OmCrud.update(record, attrs, opts)

            case {result, opts[:reload]} do
              {{:ok, record}, preloads} when is_list(preloads) and preloads != [] ->
                repo = OmCrud.Options.repo(opts)
                {:ok, repo.preload(record, preloads)}

              {{:ok, record}, true} ->
                repo = OmCrud.Options.repo(opts)
                {:ok, repo.preload(record, unquote(default_preload))}

              _ ->
                result
            end
          end)
        end
      end
    ]

    bang = generate_bang_function(generate_bang, fn ->
      quote do
        @doc "Update a #{unquote(resource)} or raise."
        @spec unquote(bang_name)(struct(), map(), keyword()) :: struct()
        def unquote(bang_name)(record, attrs, opts \\ []) do
          case unquote(fn_name)(record, attrs, opts) do
            {:ok, record} ->
              record

            {:error, %Ecto.Changeset{} = changeset} ->
              raise Ecto.InvalidChangesetError, action: :update, changeset: changeset
          end
        end
      end
    end)

    base ++ bang
  end

  defp generate_function(:delete, schema, resource, _resources, config, generate_bang, _filterable) do
    fn_name = :"delete_#{resource}"
    bang_name = :"delete_#{resource}!"
    default_opts = Macro.escape(config.default_opts)

    base = [
      quote do
        @doc "Delete a #{unquote(resource)}. Returns `{:ok, record}` or `{:error, changeset}`."
        @spec unquote(fn_name)(struct(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
        def unquote(fn_name)(record, opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)

          OmCrud.Telemetry.span(:delete, %{schema: unquote(schema), id: record.id}, fn ->
            OmCrud.delete(record, opts)
          end)
        end
      end
    ]

    bang = generate_bang_function(generate_bang, fn ->
      quote do
        @doc "Delete a #{unquote(resource)} or raise."
        @spec unquote(bang_name)(struct(), keyword()) :: struct()
        def unquote(bang_name)(record, opts \\ []) do
          case unquote(fn_name)(record, opts) do
            {:ok, record} ->
              record

            {:error, %Ecto.Changeset{} = changeset} ->
              raise Ecto.InvalidChangesetError, action: :delete, changeset: changeset
          end
        end
      end
    end)

    base ++ bang
  end

  defp generate_function(:create_all, schema, _resource, resources, config, _generate_bang, _filterable) do
    fn_name = :"create_all_#{resources}"
    default_opts = Macro.escape(config.default_opts)

    [
      quote do
        @doc """
        Bulk insert #{unquote(resources)}.

        Returns `{count, records}` where records is a list if `:returning` is set.

        ## Options

        - `:returning` - Fields to return or `true` for all
        - `:placeholders` - Map of reusable values
        - `:conflict_target` - Column(s) for conflict detection
        - `:on_conflict` - Action on conflict
        """
        @spec unquote(fn_name)([map()], keyword()) :: {non_neg_integer(), [struct()] | nil}
        def unquote(fn_name)(entries, opts \\ []) do
          opts = Keyword.merge(unquote(default_opts), opts)

          OmCrud.Telemetry.span(:create_all, %{schema: unquote(schema), count: length(entries)}, fn ->
            OmCrud.create_all(unquote(schema), entries, opts)
          end)
        end
      end
    ]
  end

  defp generate_function(:update_all, schema, _resource, resources, config, _generate_bang, _filterable) do
    fn_name = :"update_all_#{resources}"
    default_opts = Macro.escape(config.default_opts)

    [
      quote do
        @doc """
        Bulk update #{unquote(resources)} matching filters.

        Returns `{:ok, count}` or `{:ok, {count, records}}` with `:returning`.

        ## Arguments

        - `filters` - List of filter tuples `[{field, op, value}]`
        - `changes` - Keyword list of changes `[field: value]`

        ## Options

        - `:returning` - Fields to return or `true` for all
        """
        @spec unquote(fn_name)([tuple()], keyword(), keyword()) ::
                {:ok, non_neg_integer()} | {:ok, {non_neg_integer(), [struct()]}}
        def unquote(fn_name)(filters, changes, opts \\ [])
            when is_list(filters) and is_list(changes) do
          opts = Keyword.merge(unquote(default_opts), opts)

          OmCrud.Telemetry.span(:update_all, %{schema: unquote(schema), filters: filters}, fn ->
            query =
              unquote(schema)
              |> OmQuery.new()
              |> __apply_crud_filters__(filters)

            repo = OmCrud.Options.repo(opts)
            ecto_query = OmQuery.build!(query)

            case opts[:returning] do
              nil ->
                {count, _} = repo.update_all(ecto_query, [set: changes], opts)
                {:ok, count}

              true ->
                {count, records} =
                  repo.update_all(ecto_query, [set: changes], Keyword.put(opts, :returning, true))

                {:ok, {count, records}}

              fields when is_list(fields) ->
                {count, records} =
                  repo.update_all(ecto_query, [set: changes], Keyword.put(opts, :returning, fields))

                {:ok, {count, records}}
            end
          end)
        end
      end
    ]
  end

  defp generate_function(:delete_all, schema, _resource, resources, config, _generate_bang, _filterable) do
    fn_name = :"delete_all_#{resources}"
    default_opts = Macro.escape(config.default_opts)

    [
      quote do
        @doc """
        Bulk delete #{unquote(resources)} matching filters.

        Returns `{:ok, count}` or `{:ok, {count, records}}` with `:returning`.

        ## Arguments

        - `filters` - List of filter tuples `[{field, op, value}]`

        ## Options

        - `:returning` - Fields to return or `true` for all
        """
        @spec unquote(fn_name)([tuple()], keyword()) ::
                {:ok, non_neg_integer()} | {:ok, {non_neg_integer(), [struct()]}}
        def unquote(fn_name)(filters, opts \\ []) when is_list(filters) do
          opts = Keyword.merge(unquote(default_opts), opts)

          OmCrud.Telemetry.span(:delete_all, %{schema: unquote(schema), filters: filters}, fn ->
            query =
              unquote(schema)
              |> OmQuery.new()
              |> __apply_crud_filters__(filters)

            repo = OmCrud.Options.repo(opts)
            ecto_query = OmQuery.build!(query)

            case opts[:returning] do
              nil ->
                {count, _} = repo.delete_all(ecto_query, opts)
                {:ok, count}

              true ->
                {count, records} = repo.delete_all(ecto_query, Keyword.put(opts, :returning, true))
                {:ok, {count, records}}

              fields when is_list(fields) ->
                {count, records} =
                  repo.delete_all(ecto_query, Keyword.put(opts, :returning, fields))

                {:ok, {count, records}}
            end
          end)
        end
      end
    ]
  end

  defp generate_bang_function(false, _generator), do: []
  defp generate_bang_function(true, generator), do: [generator.()]
end
