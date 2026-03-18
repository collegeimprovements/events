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
          | {:dynamic, (results() -> t())}
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
      when is_atom(schema) and (is_binary(id) or is_integer(id)) do
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
      when is_atom(schema) and (is_binary(id) or is_integer(id)) do
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
        case valid?(user) do
          true -> {:ok, user}
          false -> {:error, :invalid}
        end
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
        case user.role do
          :admin ->
            Multi.new()
            |> Multi.create(:admin_record, AdminRecord, %{user_id: user.id})

          _other ->
            Multi.new()
        end
      end)
  """
  @spec when_ok(t(), name(), (results() -> t())) :: t()
  def when_ok(%__MODULE__{} = multi, name, fun) when is_function(fun, 1) do
    dynamic_fn = fn results ->
      case fun.(results) do
        %__MODULE__{} = inner_multi -> inner_multi
        _ -> new()
      end
    end

    add_operation(multi, name, {:dynamic, dynamic_fn})
  end

  # ─────────────────────────────────────────────────────────────
  # Conditional Operations
  # ─────────────────────────────────────────────────────────────

  @doc """
  Conditionally add operations based on a predicate.

  If the predicate returns true (or is truthy), the operations from
  the function are added to the Multi.

  ## Examples

      # Static condition
      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Multi.when_cond(send_welcome_email?, fn multi ->
        Multi.run(multi, :email, fn _ -> send_email() end)
      end)

      # Condition based on previous results
      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Multi.when_cond(fn %{user: user} -> user.role == :admin end, fn multi, results ->
        Multi.create(multi, :admin_settings, AdminSettings, %{user_id: results.user.id})
      end)
  """
  # Static boolean condition, function takes only multi
  def when_cond(%__MODULE__{} = multi, true, fun) when is_function(fun, 1) do
    fun.(multi)
  end

  def when_cond(%__MODULE__{} = multi, false, fun) when is_function(fun, 1) do
    _ = fun
    multi
  end

  # Static boolean condition, function takes multi and results (results ignored)
  def when_cond(%__MODULE__{} = multi, true, fun) when is_function(fun, 2) do
    fun.(multi, %{})
  end

  def when_cond(%__MODULE__{} = multi, false, fun) when is_function(fun, 2) do
    _ = fun
    multi
  end

  # Dynamic condition based on results
  def when_cond(%__MODULE__{} = multi, condition_fn, fun)
      when is_function(condition_fn, 1) and is_function(fun, 2) do
    name = generate_conditional_name()

    dynamic_fn = fn results ->
      if condition_fn.(results) do
        fun.(new(), results)
      else
        new()
      end
    end

    add_operation(multi, name, {:dynamic, dynamic_fn})
  end

  @doc """
  Conditionally skip operations based on a predicate.

  Opposite of `when/3` - adds operations when condition is false.

  ## Examples

      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Multi.unless(skip_notifications?, fn multi ->
        Multi.run(multi, :notify, fn _ -> send_notification() end)
      end)
  """
  def unless(%__MODULE__{} = multi, true, fun) when is_function(fun, 1) do
    _ = fun
    multi
  end

  def unless(%__MODULE__{} = multi, false, fun) when is_function(fun, 1) do
    fun.(multi)
  end

  def unless(%__MODULE__{} = multi, true, fun) when is_function(fun, 2) do
    _ = fun
    multi
  end

  def unless(%__MODULE__{} = multi, false, fun) when is_function(fun, 2) do
    fun.(multi, %{})
  end

  def unless(%__MODULE__{} = multi, condition_fn, fun)
      when is_function(condition_fn, 1) and is_function(fun, 2) do
    __MODULE__.when_cond(multi, fn results -> not condition_fn.(results) end, fun)
  end

  @doc """
  Branch between two different operation sets based on a condition.

  ## Examples

      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Multi.branch(
        fn %{user: user} -> user.type == :premium end,
        fn multi, results ->
          Multi.create(multi, :premium, PremiumFeatures, %{user_id: results.user.id})
        end,
        fn multi, results ->
          Multi.create(multi, :trial, TrialFeatures, %{user_id: results.user.id})
        end
      )
  """
  @spec branch(
          t(),
          (results() -> boolean()),
          (t(), results() -> t()),
          (t(), results() -> t())
        ) :: t()
  def branch(%__MODULE__{} = multi, condition_fn, if_true_fn, if_false_fn)
      when is_function(condition_fn, 1) and is_function(if_true_fn, 2) and
             is_function(if_false_fn, 2) do
    name = generate_conditional_name()

    dynamic_fn = fn results ->
      if condition_fn.(results) do
        if_true_fn.(new(), results)
      else
        if_false_fn.(new(), results)
      end
    end

    add_operation(multi, name, {:dynamic, dynamic_fn})
  end

  @doc """
  Iterate over a list and add operations for each item.

  Useful for creating multiple related records in a single transaction.

  ## Examples

      # Create tags for a post
      Multi.new()
      |> Multi.create(:post, Post, post_attrs)
      |> Multi.each(:tags, tag_names, fn multi, tag_name, index, results ->
        Multi.create(multi, {:tag, index}, Tag, %{
          name: tag_name,
          post_id: results.post.id
        })
      end)

      # With a function that returns the list
      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Multi.each(:roles, fn %{user: user} -> user.role_names end, fn multi, role, idx, results ->
        Multi.create(multi, {:role, idx}, UserRole, %{
          user_id: results.user.id,
          role: role
        })
      end)
  """
  # Static list
  def each(%__MODULE__{} = multi, _name, list, fun) when is_list(list) and is_function(fun, 4) do
    list
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {item, index}, acc ->
      fun.(acc, item, index, %{})
    end)
  end

  # Dynamic list from results
  def each(%__MODULE__{} = multi, name, list_fn, fun)
      when is_function(list_fn, 1) and is_function(fun, 4) do
    dynamic_fn = fn results ->
      list = list_fn.(results)

      list
      |> Enum.with_index()
      |> Enum.reduce(new(), fn {item, index}, acc ->
        fun.(acc, item, index, results)
      end)
    end

    add_operation(multi, name, {:dynamic, dynamic_fn})
  end

  @doc """
  Execute a function only if a previous operation returned a specific value.

  ## Examples

      Multi.new()
      |> Multi.run(:check, fn _ -> {:ok, :proceed} end)
      |> Multi.when_value(:check, :proceed, fn multi, _results ->
        Multi.create(multi, :record, Record, %{})
      end)
  """
  @spec when_value(t(), name(), term(), (t(), results() -> t())) :: t()
  def when_value(%__MODULE__{} = multi, result_name, expected_value, fun)
      when is_function(fun, 2) do
    __MODULE__.when_cond(
      multi,
      fn results -> Map.get(results, result_name) == expected_value end,
      fun
    )
  end

  @doc """
  Execute a function only if a previous operation's result matches a pattern.

  Uses a guard function to test the result.

  ## Examples

      Multi.new()
      |> Multi.run(:fetch, fn _ -> fetch_user(id) end)
      |> Multi.when_match(:fetch, &match?(%User{role: :admin}, &1), fn multi, results ->
        Multi.create(multi, :audit, AuditLog, %{user_id: results.fetch.id})
      end)
  """
  @spec when_match(t(), name(), (term() -> boolean()), (t(), results() -> t())) :: t()
  def when_match(%__MODULE__{} = multi, result_name, matcher_fn, fun)
      when is_function(matcher_fn, 1) and is_function(fun, 2) do
    __MODULE__.when_cond(
      multi,
      fn results ->
        case Map.get(results, result_name) do
          nil -> false
          value -> matcher_fn.(value)
        end
      end,
      fun
    )
  end

  defp generate_conditional_name do
    :"__conditional_#{System.unique_integer([:positive])}"
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
      prefixed_name = prefix_name(name, prefix)
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
        attrs_resolved = resolve_attrs(attrs, results)
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

  defp add_to_ecto_multi(ecto_multi, _name, {:dynamic, fun}) do
    Ecto.Multi.merge(ecto_multi, fn results ->
      case fun.(results) do
        %__MODULE__{} = inner_multi -> to_ecto_multi(inner_multi)
        _ -> Ecto.Multi.new()
      end
    end)
  end

  defp add_to_ecto_multi(ecto_multi, name, {:merge, %OmQuery.Merge{} = merge}) do
    Ecto.Multi.run(ecto_multi, name, fn repo, _results ->
      sql_opts = Options.merge_opts(merge.opts)
      {sql, params} = OmQuery.Merge.to_sql(merge, Keyword.put(sql_opts, :repo, repo))
      repo.query(sql, params, sql_opts)
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp add_operation(%__MODULE__{names: names} = multi, name, operation) do
    case MapSet.member?(names, name) do
      true ->
        raise ArgumentError, "operation #{inspect(name)} already exists in Multi"

      false ->
        %{
          multi
          | operations: multi.operations ++ [{name, operation}],
            names: MapSet.put(names, name)
        }
    end
  end

  defp prefix_name(name, nil), do: name
  defp prefix_name(name, prefix), do: :"#{prefix}_#{name}"

  defp resolve_attrs(attrs, results) when is_function(attrs, 1), do: attrs.(results)
  defp resolve_attrs(attrs, _results), do: attrs
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

  defp format_multi(ops) when length(ops) <= 5 do
    names = Enum.map_join(ops, ", ", fn {name, _} -> Atom.to_string(name) end)
    "#OmCrud.Multi<#{names}>"
  end

  defp format_multi(ops) do
    first_three = ops |> Enum.take(3) |> Enum.map_join(", ", fn {name, _} -> Atom.to_string(name) end)
    "#OmCrud.Multi<#{first_three}, ... (#{length(ops)} total)>"
  end
end
