defmodule OmCrud.Multi do
  @moduledoc """
  Token-based transaction builder for composable CRUD operations.

  Provides a flat, expressive API for building transactions using pipelines.
  All mutations go through Multi for future audit integration.

  ## Design Principles

  - **Flat pipelines** - No nested structures, everything pipes
  - **Pattern matching** - Dispatch on struct types
  - **Explicit execution** - Tokens are data, execution is separate
  - **Composable** - Multis can be combined and nested

  ## Usage

      alias OmCrud.Multi

      # Build a transaction
      multi =
        Multi.new()
        |> Multi.create(:user, User, %{email: "test@example.com"})
        |> Multi.create(:account, Account, fn %{user: u} -> %{owner_id: u.id} end)
        |> Multi.create(:membership, Membership, fn %{user: u, account: a} ->
          %{user_id: u.id, account_id: a.id, role: :owner}
        end)

      # Execute explicitly
      {:ok, %{user: user, account: account}} = OmCrud.run(multi)

  ## Dynamic Attributes

  Attributes can be either a map or a function that receives previous results:

      Multi.create(:user, User, %{email: "test@example.com"})
      Multi.create(:account, Account, fn %{user: user} -> %{owner_id: user.id} end)
  """

  alias OmCrud.{ChangesetBuilder, Options}
  # Protocol implementations are at the end of this module

  defstruct operations: [],
            names: MapSet.new(),
            schema: nil

  @type t :: %__MODULE__{
          operations: [{name(), operation()}],
          names: MapSet.t(name()),
          schema: module() | nil
        }

  @type name :: atom()
  @type attrs :: map() | (results() -> map())
  @type results :: %{optional(name()) => any()}
  @type entity :: struct() | {module(), binary()}

  @type operation ::
          {:insert, module(), attrs(), keyword()}
          | {:update, entity() | (results() -> struct()), attrs(), keyword()}
          | {:delete, entity() | (results() -> struct()), keyword()}
          | {:insert_all, module(), [map()], keyword()}
          | {:update_all, Ecto.Query.t(), keyword(), keyword()}
          | {:delete_all, Ecto.Query.t(), keyword()}
          | {:run, (results() -> {:ok, any()} | {:error, any()})}
          | {:merge, OmQuery.Merge.t()}
          | {:embed, t()}

  # ─────────────────────────────────────────────────────────────
  # Token Creation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Create a new Multi token.

  ## Examples

      Multi.new()
      Multi.new(User)  # Sets default schema
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec new(module()) :: t()
  def new(schema) when is_atom(schema) do
    %__MODULE__{schema: schema}
  end

  # ─────────────────────────────────────────────────────────────
  # Single Record Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add a create operation to the Multi.

  ## Parameters

  - `multi` - The Multi token
  - `name` - Unique name for this operation
  - `schema` - The schema module
  - `attrs` - Attributes map or function returning attributes
  - `opts` - Options (changeset, etc.)

  ## Examples

      Multi.create(multi, :user, User, %{email: "test@example.com"})
      Multi.create(multi, :user, User, %{email: "test@example.com"}, changeset: :registration)
      Multi.create(multi, :account, Account, fn %{user: u} -> %{owner_id: u.id} end)
  """
  @spec create(t(), name(), module(), attrs(), keyword()) :: t()
  def create(%__MODULE__{} = multi, name, schema, attrs, opts \\ [])
      when is_atom(name) and is_atom(schema) do
    add_operation(multi, name, {:insert, schema, attrs, opts})
  end

  @doc """
  Add an update operation to the Multi.

  Supports updating by struct, by {schema, id}, or by function returning struct.

  ## Examples

      # Update a struct
      Multi.update(multi, :user, user, %{name: "Updated"})

      # Update by schema and id
      Multi.update(multi, :user, {User, user_id}, %{name: "Updated"})

      # Update result from previous operation
      Multi.update(multi, :confirm, fn %{user: u} -> u end, %{confirmed_at: now})
  """
  @spec update(
          t(),
          name(),
          struct() | {module(), binary()} | (results() -> struct()),
          attrs(),
          keyword()
        ) :: t()
  def update(multi, name, target, attrs, opts \\ [])

  def update(%__MODULE__{} = multi, name, %{__struct__: _} = struct, attrs, opts) do
    add_operation(multi, name, {:update, struct, attrs, opts})
  end

  def update(%__MODULE__{} = multi, name, {schema, id}, attrs, opts)
      when is_atom(schema) and is_binary(id) do
    add_operation(multi, name, {:update, {schema, id}, attrs, opts})
  end

  def update(%__MODULE__{} = multi, name, struct_fn, attrs, opts)
      when is_function(struct_fn, 1) do
    add_operation(multi, name, {:update, struct_fn, attrs, opts})
  end

  @doc """
  Add a delete operation to the Multi.

  ## Examples

      Multi.delete(multi, :user, user)
      Multi.delete(multi, :user, {User, user_id})
      Multi.delete(multi, :token, fn %{user: u} -> u.token end)
  """
  @spec delete(t(), name(), struct() | {module(), binary()} | (results() -> struct()), keyword()) ::
          t()
  def delete(multi, name, target, opts \\ [])

  def delete(%__MODULE__{} = multi, name, %{__struct__: _} = struct, opts) do
    add_operation(multi, name, {:delete, struct, opts})
  end

  def delete(%__MODULE__{} = multi, name, {schema, id}, opts)
      when is_atom(schema) and is_binary(id) do
    add_operation(multi, name, {:delete, {schema, id}, opts})
  end

  def delete(%__MODULE__{} = multi, name, struct_fn, opts)
      when is_function(struct_fn, 1) do
    add_operation(multi, name, {:delete, struct_fn, opts})
  end

  # ─────────────────────────────────────────────────────────────
  # Upsert Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add an upsert operation using ON CONFLICT.

  ## Options

  - `:conflict_target` - Column(s) to detect conflicts on
  - `:on_conflict` - Action on conflict (:nothing, :replace_all, {:replace, fields})

  ## Examples

      Multi.upsert(multi, :user, User, attrs,
        conflict_target: :email,
        on_conflict: {:replace, [:name, :updated_at]}
      )
  """
  @spec upsert(t(), name(), module(), attrs(), keyword()) :: t()
  def upsert(%__MODULE__{} = multi, name, schema, attrs, opts)
      when is_atom(name) and is_atom(schema) do
    upsert_opts = Options.upsert_opts(opts)
    merged_opts = Keyword.merge(opts, upsert_opts)
    add_operation(multi, name, {:insert, schema, attrs, merged_opts})
  end

  @doc """
  Add a MERGE operation to the Multi.

  ## Examples

      merge_token =
        User
        |> Merge.new(external_data)
        |> Merge.match_on(:external_id)
        |> Merge.when_matched(:update)
        |> Merge.when_not_matched(:insert)

      Multi.merge(multi, :sync, merge_token)
  """
  @spec merge(t(), name(), OmQuery.Merge.t()) :: t()
  def merge(%__MODULE__{} = multi, name, %OmQuery.Merge{} = merge_token) do
    add_operation(multi, name, {:merge, merge_token})
  end

  # ─────────────────────────────────────────────────────────────
  # Bulk Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add a bulk create operation using insert_all.

  ## Options

  - `:returning` - Fields to return
  - `:conflict_target` - For upsert behavior
  - `:on_conflict` - Conflict handling

  ## Examples

      Multi.create_all(multi, :users, User, [
        %{email: "a@test.com"},
        %{email: "b@test.com"}
      ])
  """
  @spec create_all(t(), name(), module(), [map()], keyword()) :: t()
  def create_all(%__MODULE__{} = multi, name, schema, list_of_attrs, opts \\ [])
      when is_atom(name) and is_atom(schema) and is_list(list_of_attrs) do
    add_operation(multi, name, {:insert_all, schema, list_of_attrs, opts})
  end

  @doc """
  Add a bulk upsert operation.

  ## Examples

      Multi.upsert_all(multi, :users, User, users_data,
        conflict_target: :email,
        on_conflict: {:replace, [:name]}
      )
  """
  @spec upsert_all(t(), name(), module(), [map()], keyword()) :: t()
  def upsert_all(%__MODULE__{} = multi, name, schema, list_of_attrs, opts)
      when is_atom(name) and is_atom(schema) and is_list(list_of_attrs) do
    insert_all_opts = Options.insert_all_opts(opts)
    add_operation(multi, name, {:insert_all, schema, list_of_attrs, insert_all_opts})
  end

  @doc """
  Add a bulk update operation.

  ## Examples

      query = from(u in User, where: u.status == :inactive)
      Multi.update_all(multi, :deactivate, query, set: [archived_at: now])
  """
  @spec update_all(t(), name(), Ecto.Query.t(), keyword(), keyword()) :: t()
  def update_all(%__MODULE__{} = multi, name, query, updates, opts \\ []) do
    add_operation(multi, name, {:update_all, query, updates, opts})
  end

  @doc """
  Add a bulk delete operation.

  ## Examples

      query = from(t in Token, where: t.expired_at < ^now)
      Multi.delete_all(multi, :cleanup, query)
  """
  @spec delete_all(t(), name(), Ecto.Query.t(), keyword()) :: t()
  def delete_all(%__MODULE__{} = multi, name, query, opts \\ []) do
    add_operation(multi, name, {:delete_all, query, opts})
  end

  @doc """
  Add a MERGE operation for bulk sync.

  ## Examples

      merge_token =
        User
        |> Merge.new(external_users)
        |> Merge.match_on(:external_id)
        |> Merge.when_matched(:update)
        |> Merge.when_not_matched(:insert)

      Multi.merge_all(multi, :sync, merge_token)
  """
  @spec merge_all(t(), name(), OmQuery.Merge.t()) :: t()
  def merge_all(%__MODULE__{} = multi, name, %OmQuery.Merge{} = merge_token) do
    add_operation(multi, name, {:merge, merge_token})
  end

  # ─────────────────────────────────────────────────────────────
  # Conditional & Dynamic Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add a custom run operation.

  The function receives all previous results and must return
  `{:ok, value}` or `{:error, reason}`.

  ## Examples

      Multi.run(multi, :validate, fn %{user: user} ->
        if valid?(user), do: {:ok, user}, else: {:error, :invalid}
      end)

      Multi.run(multi, :notify, MyModule, :send_notification, [:user_created])
  """
  @spec run(t(), name(), (results() -> {:ok, any()} | {:error, any()})) :: t()
  def run(%__MODULE__{} = multi, name, fun) when is_function(fun, 1) do
    add_operation(multi, name, {:run, fun})
  end

  @spec run(t(), name(), module(), atom(), [any()]) :: t()
  def run(%__MODULE__{} = multi, name, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    run_fn = fn results ->
      apply(mod, fun, [results | args])
    end

    add_operation(multi, name, {:run, run_fn})
  end

  @doc """
  Add an inspect operation for debugging.

  Always succeeds and returns the inspection result.

  ## Examples

      Multi.inspect_results(multi, :debug, fn results ->
        IO.inspect(results, label: "Transaction state")
      end)
  """
  @spec inspect_results(t(), name(), (results() -> any())) :: t()
  def inspect_results(%__MODULE__{} = multi, name, fun) when is_function(fun, 1) do
    run_fn = fn results ->
      {:ok, fun.(results)}
    end

    add_operation(multi, name, {:run, run_fn})
  end

  @doc """
  Add conditional operations based on previous results.

  The function receives results and returns a Multi to be embedded.

  ## Examples

      Multi.when_ok(multi, :user, fn %{user: user} ->
        if user.role == :admin do
          Multi.new()
          |> Multi.create(:admin_record, AdminRecord, %{user_id: user.id})
        else
          Multi.new()
        end
      end)
  """
  @spec when_ok(t(), name(), (results() -> t())) :: t()
  def when_ok(%__MODULE__{} = multi, name, fun) when is_function(fun, 1) do
    run_fn = fn results ->
      case fun.(results) do
        %__MODULE__{operations: []} ->
          {:ok, nil}

        %__MODULE__{} = inner_multi ->
          # This will be handled specially during execution
          {:ok, {:embed, inner_multi}}
      end
    end

    add_operation(multi, name, {:run, run_fn})
  end

  # ─────────────────────────────────────────────────────────────
  # Composition
  # ─────────────────────────────────────────────────────────────

  @doc """
  Append another Multi's operations to this one.

  Operations from multi2 are added after multi1's operations.

  ## Examples

      user_multi = Multi.new() |> Multi.create(:user, User, attrs)
      account_multi = Multi.new() |> Multi.create(:account, Account, fn %{user: u} -> ... end)

      combined = Multi.append(user_multi, account_multi)
  """
  @spec append(t(), t()) :: t()
  def append(%__MODULE__{} = multi1, %__MODULE__{} = multi2) do
    Enum.reduce(multi2.operations, multi1, fn {name, op}, acc ->
      add_operation(acc, name, op)
    end)
  end

  @doc """
  Prepend another Multi's operations to this one.

  Operations from multi2 are added before multi1's operations.
  """
  @spec prepend(t(), t()) :: t()
  def prepend(%__MODULE__{} = multi1, %__MODULE__{} = multi2) do
    append(multi2, multi1)
  end

  @doc """
  Embed another Multi's operations with a prefix.

  All operation names will be prefixed to avoid conflicts.

  ## Examples

      user_setup = Multi.new() |> Multi.create(:record, User, attrs)
      Multi.embed(multi, user_setup, prefix: :user)
      # Creates operation named :user_record
  """
  @spec embed(t(), t(), keyword()) :: t()
  def embed(%__MODULE__{} = multi1, %__MODULE__{} = multi2, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    Enum.reduce(multi2.operations, multi1, fn {name, op}, acc ->
      prefixed_name = if prefix, do: :"#{prefix}_#{name}", else: name
      add_operation(acc, prefixed_name, op)
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Introspection
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get all operation names in order.
  """
  @spec names(t()) :: [name()]
  def names(%__MODULE__{operations: ops}) do
    Enum.map(ops, &elem(&1, 0))
  end

  @doc """
  Get the number of operations.
  """
  @spec operation_count(t()) :: non_neg_integer()
  def operation_count(%__MODULE__{operations: ops}) do
    length(ops)
  end

  @doc """
  Check if an operation with the given name exists.
  """
  @spec has_operation?(t(), name()) :: boolean()
  def has_operation?(%__MODULE__{names: names}, name) do
    MapSet.member?(names, name)
  end

  @doc """
  Check if the Multi is empty.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{operations: []}), do: true
  def empty?(%__MODULE__{}), do: false

  # ─────────────────────────────────────────────────────────────
  # Conversion
  # ─────────────────────────────────────────────────────────────

  @doc """
  Convert to an Ecto.Multi for direct Repo.transaction use.

  This is useful when you need to integrate with existing code
  that uses Ecto.Multi directly.
  """
  @spec to_ecto_multi(t()) :: Ecto.Multi.t()
  def to_ecto_multi(%__MODULE__{} = multi) do
    Enum.reduce(multi.operations, Ecto.Multi.new(), fn {name, op}, ecto_multi ->
      add_to_ecto_multi(ecto_multi, name, op)
    end)
  end

  defp add_to_ecto_multi(ecto_multi, name, {:insert, schema, attrs, opts}) when is_map(attrs) do
    changeset_fn = ChangesetBuilder.resolve(schema, :create, opts)
    changeset = apply(schema, changeset_fn, [struct(schema), attrs])
    insert_opts = Options.insert_opts(opts)
    Ecto.Multi.insert(ecto_multi, name, changeset, insert_opts)
  end

  defp add_to_ecto_multi(ecto_multi, name, {:insert, schema, attrs_fn, opts})
       when is_function(attrs_fn, 1) do
    Ecto.Multi.insert(
      ecto_multi,
      name,
      fn results ->
        attrs = attrs_fn.(results)
        changeset_fn = ChangesetBuilder.resolve(schema, :create, opts)
        apply(schema, changeset_fn, [struct(schema), attrs])
      end,
      Options.insert_opts(opts)
    )
  end

  defp add_to_ecto_multi(ecto_multi, name, {:update, struct, attrs, opts})
       when is_struct(struct) and is_map(attrs) do
    schema = struct.__struct__
    changeset_fn = ChangesetBuilder.resolve(schema, :update, opts)
    changeset = apply(schema, changeset_fn, [struct, attrs])
    Ecto.Multi.update(ecto_multi, name, changeset, Options.update_opts(opts))
  end

  defp add_to_ecto_multi(ecto_multi, name, {:update, {schema, id}, attrs, opts}) do
    Ecto.Multi.run(ecto_multi, name, fn repo, _results ->
      case repo.get(schema, id) do
        nil ->
          {:error, :not_found}

        struct ->
          changeset_fn = ChangesetBuilder.resolve(schema, :update, opts)
          changeset = apply(schema, changeset_fn, [struct, attrs])
          repo.update(changeset, Options.update_opts(opts))
      end
    end)
  end

  defp add_to_ecto_multi(ecto_multi, name, {:update, struct_fn, attrs, opts})
       when is_function(struct_fn, 1) do
    Ecto.Multi.update(
      ecto_multi,
      name,
      fn results ->
        struct = struct_fn.(results)
        schema = struct.__struct__
        attrs_resolved = if is_function(attrs, 1), do: attrs.(results), else: attrs
        changeset_fn = ChangesetBuilder.resolve(schema, :update, opts)
        apply(schema, changeset_fn, [struct, attrs_resolved])
      end,
      Options.update_opts(opts)
    )
  end

  defp add_to_ecto_multi(ecto_multi, name, {:delete, struct, opts}) when is_struct(struct) do
    Ecto.Multi.delete(ecto_multi, name, struct, Options.delete_opts(opts))
  end

  defp add_to_ecto_multi(ecto_multi, name, {:delete, {schema, id}, opts}) do
    Ecto.Multi.run(ecto_multi, name, fn repo, _results ->
      case repo.get(schema, id) do
        nil -> {:error, :not_found}
        struct -> repo.delete(struct, Options.delete_opts(opts))
      end
    end)
  end

  defp add_to_ecto_multi(ecto_multi, name, {:delete, struct_fn, opts})
       when is_function(struct_fn, 1) do
    Ecto.Multi.delete(
      ecto_multi,
      name,
      fn results ->
        struct_fn.(results)
      end,
      Options.delete_opts(opts)
    )
  end

  defp add_to_ecto_multi(ecto_multi, name, {:insert_all, schema, entries, opts}) do
    Ecto.Multi.insert_all(ecto_multi, name, schema, entries, Options.insert_all_opts(opts))
  end

  defp add_to_ecto_multi(ecto_multi, name, {:update_all, query, updates, opts}) do
    Ecto.Multi.update_all(ecto_multi, name, query, updates, Options.update_all_opts(opts))
  end

  defp add_to_ecto_multi(ecto_multi, name, {:delete_all, query, opts}) do
    Ecto.Multi.delete_all(ecto_multi, name, query, Options.delete_all_opts(opts))
  end

  defp add_to_ecto_multi(ecto_multi, name, {:run, fun}) do
    Ecto.Multi.run(ecto_multi, name, fn _repo, results ->
      fun.(results)
    end)
  end

  defp add_to_ecto_multi(ecto_multi, name, {:merge, %OmQuery.Merge{} = merge}) do
    Ecto.Multi.run(ecto_multi, name, fn repo, _results ->
      # Execute the merge operation
      {sql, params} = OmQuery.Merge.to_sql(merge, repo: repo)
      repo.query(sql, params)
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp add_operation(%__MODULE__{names: names} = multi, name, operation) do
    if MapSet.member?(names, name) do
      raise ArgumentError, "operation #{inspect(name)} already exists in Multi"
    end

    %{
      multi
      | operations: multi.operations ++ [{name, operation}],
        names: MapSet.put(names, name)
    }
  end
end

# ─────────────────────────────────────────────────────────────
# Protocol Implementations
# ─────────────────────────────────────────────────────────────

defimpl OmCrud.Executable, for: OmCrud.Multi do
  alias OmCrud.Multi

  def execute(%Multi{} = multi, opts) do
    OmCrud.transaction(multi, opts)
  end
end

defimpl OmCrud.Validatable, for: OmCrud.Multi do
  alias OmCrud.Multi

  def validate(%Multi{operations: []}) do
    {:error, ["Multi has no operations"]}
  end

  def validate(%Multi{}), do: :ok
end

defimpl OmCrud.Debuggable, for: OmCrud.Multi do
  alias OmCrud.Multi

  def to_debug(%Multi{} = multi) do
    %{
      type: :multi,
      operations: Multi.names(multi),
      count: Multi.operation_count(multi)
    }
  end
end

defimpl Inspect, for: OmCrud.Multi do
  alias OmCrud.Multi

  def inspect(%Multi{operations: ops}, _opts) do
    format_multi(ops)
  end

  defp format_multi([]), do: "#OmCrud.Multi<>"
  defp format_multi([{n1, _}]), do: "#OmCrud.Multi<#{n1}>"
  defp format_multi([{n1, _}, {n2, _}]), do: "#OmCrud.Multi<#{n1}, #{n2}>"
  defp format_multi([{n1, _}, {n2, _}, {n3, _}]), do: "#OmCrud.Multi<#{n1}, #{n2}, #{n3}>"
  defp format_multi([{n1, _}, {n2, _}, {n3, _}, {n4, _}]), do: "#OmCrud.Multi<#{n1}, #{n2}, #{n3}, #{n4}>"
  defp format_multi([{n1, _}, {n2, _}, {n3, _}, {n4, _}, {n5, _}]), do: "#OmCrud.Multi<#{n1}, #{n2}, #{n3}, #{n4}, #{n5}>"

  defp format_multi(ops) do
    [{n1, _}, {n2, _}, {n3, _} | _rest] = ops
    "#OmCrud.Multi<#{n1}, #{n2}, #{n3}, ... (#{length(ops)} total)>"
  end
end
