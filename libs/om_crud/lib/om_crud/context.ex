defmodule OmCrud.Context do
  @moduledoc """
  Context-level CRUD integration for generating resource functions.

  This module provides macros to generate standard CRUD functions for schemas
  within context modules, reducing boilerplate while maintaining explicit control.

  ## Usage

      defmodule MyApp.Accounts do
        use OmCrud.Context

        # Generate all CRUD functions for User
        crud User

        # Generate only specific functions
        crud Role, only: [:create, :fetch, :update]

        # Exclude specific functions
        crud Session, except: [:delete_all]

        # Custom options for all generated functions
        crud Membership, preload: [:account, :user]
      end

  ## Generated Functions

  For each schema, the following functions are generated:

  ### Read Operations
  - `fetch_<resource>(id, opts)` - Returns `{:ok, record}` or `{:error, :not_found}`
  - `get_<resource>(id, opts)` - Returns record or `nil`
  - `list_<resources>(opts)` - Returns list of all records
  - `<resource>_exists?(id)` - Returns boolean

  ### Write Operations
  - `create_<resource>(attrs, opts)` - Creates a record
  - `update_<resource>(record, attrs, opts)` - Updates a record
  - `delete_<resource>(record, opts)` - Deletes a record

  ### Bulk Operations
  - `create_all_<resources>(entries, opts)` - Bulk insert
  - `update_all_<resources>(updates, opts)` - Bulk update
  - `delete_all_<resources>(opts)` - Bulk delete

  ## Options

  - `:only` - List of functions to generate (e.g., `[:create, :fetch, :update]`)
  - `:except` - List of functions to exclude
  - `:preload` - Default preloads for read operations
  - `:changeset` - Default changeset function for write operations
  - `:as` - Override the resource name (e.g., `as: :member` for Membership)
  - `:repo` - Default repository for all operations (e.g., `MyApp.ReadOnlyRepo`)
  - `:timeout` - Default timeout for all database operations in milliseconds
  - `:prefix` - Default schema prefix for multi-tenant setups
  - `:log` - Default logging level or `false` to disable

  ## Overriding Generated Functions

  All generated functions are marked as `defoverridable`, so you can define
  custom implementations that replace the generated ones:

      defmodule MyApp.Accounts do
        use OmCrud.Context

        crud Role

        # Override the generated create_role/2 with custom logic
        def create_role(attrs, opts \\\\ []) do
          attrs
          |> Map.put(:created_by, opts[:current_user_id])
          |> then(&OmCrud.create(Role, &1, opts))
        end

        # You can call super() to use the generated implementation
        def fetch_role(id, opts \\\\ []) do
          case super(id, opts) do
            {:ok, role} -> {:ok, enrich_role(role)}
            error -> error
          end
        end
      end
  """

  @doc """
  Use this module in a context to enable CRUD generation.

  ## Examples

      defmodule MyApp.Accounts do
        use OmCrud.Context

        crud User
        crud Role, only: [:create, :fetch]
      end
  """
  defmacro __using__(_opts) do
    quote do
      import OmCrud.Context, only: [crud: 1, crud: 2]
    end
  end

  @doc """
  Generate CRUD functions for a schema.

  ## Options

  ### Function Selection
  - `:only` - Generate only these functions
  - `:except` - Exclude these functions
  - `:as` - Override resource name derivation

  ### Operation Defaults
  - `:preload` - Default preloads for read operations
  - `:changeset` - Default changeset function for write operations

  ### Crud-level Defaults (passed to all generated functions)
  - `:repo` - Default repository module (e.g., `MyApp.ReadOnlyRepo`)
  - `:timeout` - Default timeout in milliseconds
  - `:prefix` - Default schema prefix for multi-tenant setups
  - `:log` - Default logging level (`:debug`, `:info`, etc.) or `false`

  ## Examples

      crud User
      crud Role, only: [:create, :fetch]
      crud Membership, as: :member, preload: [:user]

      # With crud-level defaults
      crud AuditLog, repo: MyApp.ReadOnlyRepo, timeout: 60_000
      crud TenantUser, prefix: "tenant_123", log: false
  """
  # Options that are passed to generated functions as defaults
  @crud_level_opts [:repo, :timeout, :prefix, :log]

  defmacro crud(schema, opts \\ []) do
    schema = Macro.expand(schema, __CALLER__)
    resource = resource_name(schema, opts)
    resources = pluralize(resource)

    functions = determine_functions(opts)
    default_preload = Keyword.get(opts, :preload, [])
    default_changeset = Keyword.get(opts, :changeset)

    # Extract crud-level defaults that get merged into every function call
    default_opts =
      opts
      |> Keyword.take(@crud_level_opts)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    # Generate the function definitions
    function_defs =
      functions
      |> Enum.flat_map(fn fun ->
        generate_function(
          fun,
          schema,
          resource,
          resources,
          default_preload,
          default_changeset,
          default_opts
        )
      end)

    # Build overridable declarations for all generated functions
    overridable_fns = build_overridable_list(functions, resource, resources)

    # Return function definitions followed by defoverridable
    function_defs ++
      [
        quote do
          defoverridable unquote(overridable_fns)
        end
      ]
  end

  # Build list of {function_name, arity} tuples for defoverridable
  defp build_overridable_list(functions, resource, resources) do
    Enum.flat_map(functions, fn
      :fetch ->
        [{:"fetch_#{resource}", 1}, {:"fetch_#{resource}", 2}]

      :get ->
        [{:"get_#{resource}", 1}, {:"get_#{resource}", 2}]

      :list ->
        [{:"list_#{resources}", 0}, {:"list_#{resources}", 1}]

      :exists? ->
        [{:"#{resource}_exists?", 1}, {:"#{resource}_exists?", 2}]

      :create ->
        [{:"create_#{resource}", 1}, {:"create_#{resource}", 2}]

      :update ->
        [{:"update_#{resource}", 2}, {:"update_#{resource}", 3}]

      :delete ->
        [{:"delete_#{resource}", 1}, {:"delete_#{resource}", 2}]

      :create_all ->
        [{:"create_all_#{resources}", 1}, {:"create_all_#{resources}", 2}]

      :update_all ->
        [
          {:"update_all_#{resources}", 1},
          {:"update_all_#{resources}", 2},
          {:"update_all_#{resources}", 3}
        ]

      :delete_all ->
        [
          {:"delete_all_#{resources}", 0},
          {:"delete_all_#{resources}", 1},
          {:"delete_all_#{resources}", 2}
        ]
    end)
  end

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
    name
    |> Atom.to_string()
    |> pluralize_string()
    |> String.to_atom()
  end

  defp pluralize_string(str) do
    cond do
      String.ends_with?(str, "y") and not String.ends_with?(str, ["ay", "ey", "iy", "oy", "uy"]) ->
        String.slice(str, 0..-2//1) <> "ies"

      String.ends_with?(str, ["s", "x", "z", "ch", "sh"]) ->
        str <> "es"

      true ->
        str <> "s"
    end
  end

  @all_functions [
    :fetch,
    :get,
    :list,
    :exists?,
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

  defp generate_function(
         :fetch,
         schema,
         resource,
         _resources,
         default_preload,
         _changeset,
         default_opts
       ) do
    fn_name = :"fetch_#{resource}"

    quote do
      @doc """
      Fetch a #{unquote(resource)} by ID.

      Returns `{:ok, record}` or `{:error, :not_found}`.
      """
      @spec unquote(fn_name)(binary(), keyword()) :: {:ok, struct()} | {:error, :not_found}
      def unquote(fn_name)(id, opts \\ []) do
        opts =
          unquote(default_opts)
          |> Keyword.merge(opts)
          |> Keyword.put_new(:preload, unquote(default_preload))

        OmCrud.fetch(unquote(schema), id, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(
         :get,
         schema,
         resource,
         _resources,
         default_preload,
         _changeset,
         default_opts
       ) do
    fn_name = :"get_#{resource}"

    quote do
      @doc """
      Get a #{unquote(resource)} by ID.

      Returns the record or `nil`.
      """
      @spec unquote(fn_name)(binary(), keyword()) :: struct() | nil
      def unquote(fn_name)(id, opts \\ []) do
        opts =
          unquote(default_opts)
          |> Keyword.merge(opts)
          |> Keyword.put_new(:preload, unquote(default_preload))

        OmCrud.get(unquote(schema), id, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(
         :list,
         schema,
         _resource,
         resources,
         default_preload,
         _changeset,
         default_opts
       ) do
    fn_name = :"list_#{resources}"

    quote do
      @doc """
      List all #{unquote(resources)}.

      Returns a list of records.
      """
      @spec unquote(fn_name)(keyword()) :: [struct()]
      def unquote(fn_name)(opts \\ []) do
        opts =
          unquote(default_opts)
          |> Keyword.merge(opts)
          |> Keyword.put_new(:preload, unquote(default_preload))

        OmCrud.fetch_all(unquote(schema), opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(:exists?, schema, resource, _resources, _preload, _changeset, default_opts) do
    fn_name = :"#{resource}_exists?"

    quote do
      @doc """
      Check if a #{unquote(resource)} exists.

      Returns `true` or `false`.
      """
      @spec unquote(fn_name)(binary(), keyword()) :: boolean()
      def unquote(fn_name)(id, opts \\ []) do
        opts = Keyword.merge(unquote(default_opts), opts)
        OmCrud.exists?(unquote(schema), id, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(:create, schema, resource, _resources, _preload, changeset, default_opts) do
    fn_name = :"create_#{resource}"

    quote do
      @doc """
      Create a new #{unquote(resource)}.

      Returns `{:ok, record}` or `{:error, changeset}`.
      """
      @spec unquote(fn_name)(map(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
      def unquote(fn_name)(attrs, opts \\ []) do
        opts =
          unquote(default_opts)
          |> Keyword.merge(opts)
          |> then(fn o ->
            if unquote(changeset) do
              Keyword.put_new(o, :changeset, unquote(changeset))
            else
              o
            end
          end)

        OmCrud.create(unquote(schema), attrs, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(:update, _schema, resource, _resources, _preload, changeset, default_opts) do
    fn_name = :"update_#{resource}"

    quote do
      @doc """
      Update a #{unquote(resource)}.

      Accepts a struct or `{schema, id}` tuple.
      Returns `{:ok, record}` or `{:error, changeset}`.
      """
      @spec unquote(fn_name)(struct(), map(), keyword()) ::
              {:ok, struct()} | {:error, Ecto.Changeset.t()}
      def unquote(fn_name)(record, attrs, opts \\ []) do
        opts =
          unquote(default_opts)
          |> Keyword.merge(opts)
          |> then(fn o ->
            if unquote(changeset) do
              Keyword.put_new(o, :changeset, unquote(changeset))
            else
              o
            end
          end)

        OmCrud.update(record, attrs, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(:delete, _schema, resource, _resources, _preload, _changeset, default_opts) do
    fn_name = :"delete_#{resource}"

    quote do
      @doc """
      Delete a #{unquote(resource)}.

      Returns `{:ok, record}` or `{:error, changeset}`.
      """
      @spec unquote(fn_name)(struct(), keyword()) :: {:ok, struct()} | {:error, Ecto.Changeset.t()}
      def unquote(fn_name)(record, opts \\ []) do
        opts = Keyword.merge(unquote(default_opts), opts)
        OmCrud.delete(record, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(
         :create_all,
         schema,
         _resource,
         resources,
         _preload,
         _changeset,
         default_opts
       ) do
    fn_name = :"create_all_#{resources}"

    quote do
      @doc """
      Bulk insert #{unquote(resources)}.

      Returns `{count, records}` where records is a list if `:returning` is set.
      """
      @spec unquote(fn_name)([map()], keyword()) :: {non_neg_integer(), [struct()] | nil}
      def unquote(fn_name)(entries, opts \\ []) do
        opts = Keyword.merge(unquote(default_opts), opts)
        OmCrud.create_all(unquote(schema), entries, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(
         :update_all,
         schema,
         _resource,
         resources,
         _preload,
         _changeset,
         default_opts
       ) do
    fn_name = :"update_all_#{resources}"

    quote do
      @doc """
      Bulk update #{unquote(resources)}.

      The query should be an Ecto.Query or Query.Token.
      Returns `{count, records}`.
      """
      @spec unquote(fn_name)(Ecto.Queryable.t(), keyword(), keyword()) ::
              {non_neg_integer(), [struct()] | nil}
      def unquote(fn_name)(query \\ unquote(schema), updates, opts \\ []) do
        opts = Keyword.merge(unquote(default_opts), opts)
        OmCrud.update_all(query, updates, opts)
      end
    end
    |> List.wrap()
  end

  defp generate_function(
         :delete_all,
         schema,
         _resource,
         resources,
         _preload,
         _changeset,
         default_opts
       ) do
    fn_name = :"delete_all_#{resources}"

    quote do
      @doc """
      Bulk delete #{unquote(resources)}.

      The query should be an Ecto.Query or Query.Token.
      Returns `{count, records}`.
      """
      @spec unquote(fn_name)(Ecto.Queryable.t(), keyword()) :: {non_neg_integer(), [struct()] | nil}
      def unquote(fn_name)(query \\ unquote(schema), opts \\ []) do
        opts = Keyword.merge(unquote(default_opts), opts)
        OmCrud.delete_all(query, opts)
      end
    end
    |> List.wrap()
  end
end
