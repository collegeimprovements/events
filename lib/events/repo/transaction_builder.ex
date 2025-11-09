defmodule Events.Repo.TransactionBuilder do
  @moduledoc """
  Builder for complex transactional operations using Ecto.Multi.

  This module provides a fluent API for building multi-step database transactions
  that integrate with the Scope DSL, CRUD operations, and soft delete support.

  ## Features

  - **Atomic Operations**: All steps succeed or all fail
  - **Dependency Management**: Steps can depend on previous results
  - **Scope Integration**: Use scopes in transactional queries
  - **Rollback Support**: Automatic rollback on any failure
  - **Result Accumulation**: Access results from previous steps

  ## Basic Usage

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:product, Product, %{name: "Widget"}, created_by: user_id)
      |> TransactionBuilder.update_all(:update_stock, Product, fn scope ->
        scope |> Scope.eq("category", "widgets")
      end, %{in_stock: true}, updated_by: user_id)
      |> TransactionBuilder.delete(:archive, Product, fn scope ->
        scope |> Scope.lt("updated_at", old_date)
      end, deleted_by: user_id)
      |> TransactionBuilder.execute()

  ## Complex Transactions

      TransactionBuilder.new()
      # Step 1: Create an order
      |> TransactionBuilder.insert(:order, Order, %{
        customer_id: customer_id,
        status: "pending"
      }, created_by: user_id)
      # Step 2: Update product stock (depends on order)
      |> TransactionBuilder.run(:update_stock, fn %{order: order} ->
        Product
        |> QueryBuilder.scope(fn s -> s |> Scope.eq("id", product_id) end)
        |> QueryBuilder.one()
        |> case do
          nil -> {:error, :product_not_found}
          product ->
            if product.stock >= order.quantity do
              product
              |> Ecto.Changeset.change(%{stock: product.stock - order.quantity})
              |> Repo.update()
            else
              {:error, :insufficient_stock}
            end
        end
      end)
      # Step 3: Create order items
      |> TransactionBuilder.insert(:order_item, OrderItem, fn %{order: order} ->
        %{
          order_id: order.id,
          product_id: product_id,
          quantity: order.quantity,
          price: order.total
        }
      end, created_by: user_id)
      # Step 4: Update order status
      |> TransactionBuilder.update(:finalize_order, fn %{order: order} ->
        order
      end, %{status: "confirmed"}, updated_by: user_id)
      |> TransactionBuilder.execute()

  ## Conditional Steps

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:user, User, user_attrs, created_by: admin_id)
      |> TransactionBuilder.run(:send_welcome_email, fn %{user: user} ->
        if user.email_verified do
          Email.send_welcome(user)
        else
          {:ok, :skipped}
        end
      end)
      |> TransactionBuilder.execute()
  """

  alias Events.Repo
  alias Events.Repo.Crud
  alias Events.Repo.QueryBuilder
  alias Events.Repo.SqlScope.Scope
  alias Events.Repo.SoftDelete
  alias Ecto.Multi

  @type t :: Multi.t()
  @type step_name :: atom()
  @type schema_module :: module()
  @type attrs :: map() | (map() -> map())
  @type scope_builder :: (Scope.t() -> Scope.t())

  ## Builder Functions

  @doc """
  Creates a new transaction builder.

  ## Examples

      TransactionBuilder.new()
  """
  @spec new() :: t()
  def new do
    Multi.new()
  end

  @doc """
  Inserts a record in the transaction.

  ## Options

  - `:created_by` - User ID for audit trail

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:product, Product, %{name: "Widget"}, created_by: user_id)

      # Dynamic attrs based on previous steps
      TransactionBuilder.new()
      |> TransactionBuilder.insert(:order, Order, %{status: "pending"}, created_by: user_id)
      |> TransactionBuilder.insert(:item, OrderItem, fn %{order: order} ->
        %{order_id: order.id, product_id: product_id}
      end, created_by: user_id)
  """
  @spec insert(t(), step_name(), schema_module(), attrs(), keyword()) :: t()
  def insert(%Multi{} = multi, name, schema, attrs, opts \\ [])

  def insert(%Multi{} = multi, name, schema, attrs, opts) when is_map(attrs) do
    Multi.run(multi, name, fn _repo, _changes ->
      Crud.new(schema)
      |> Crud.insert(attrs, opts)
      |> Crud.execute()
    end)
  end

  def insert(%Multi{} = multi, name, schema, attrs_fn, opts) when is_function(attrs_fn, 1) do
    Multi.run(multi, name, fn _repo, changes ->
      attrs = attrs_fn.(changes)

      Crud.new(schema)
      |> Crud.insert(attrs, opts)
      |> Crud.execute()
    end)
  end

  @doc """
  Inserts multiple records in the transaction.

  ## Options

  - `:created_by` - User ID for audit trail

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.insert_all(:products, Product, [
        %{name: "Widget A"},
        %{name: "Widget B"}
      ], created_by: user_id)
  """
  @spec insert_all(t(), step_name(), schema_module(), [map()] | (map() -> [map()]), keyword()) ::
          t()
  def insert_all(%Multi{} = multi, name, schema, records, opts \\ [])

  def insert_all(%Multi{} = multi, name, schema, records, opts) when is_list(records) do
    Multi.run(multi, name, fn _repo, _changes ->
      Crud.new(schema)
      |> Crud.insert_all(records, opts)
      |> Crud.execute()
    end)
  end

  def insert_all(%Multi{} = multi, name, schema, records_fn, opts)
      when is_function(records_fn, 1) do
    Multi.run(multi, name, fn _repo, changes ->
      records = records_fn.(changes)

      Crud.new(schema)
      |> Crud.insert_all(records, opts)
      |> Crud.execute()
    end)
  end

  @doc """
  Updates a record in the transaction.

  ## Options

  - `:updated_by` - User ID for audit trail

  ## Examples

      # Update by scope
      TransactionBuilder.new()
      |> TransactionBuilder.update(:update_price, Product, fn scope ->
        scope |> Scope.eq("id", product_id)
      end, %{price: 19.99}, updated_by: user_id)

      # Update a struct from previous step
      TransactionBuilder.new()
      |> TransactionBuilder.insert(:product, Product, %{name: "Widget"}, created_by: user_id)
      |> TransactionBuilder.update(:update_product, fn %{product: product} ->
        product
      end, %{status: "active"}, updated_by: user_id)
  """
  @spec update(
          t(),
          step_name(),
          schema_module() | (map() -> Ecto.Schema.t()),
          scope_builder() | map(),
          map(),
          keyword()
        ) :: t()
  def update(%Multi{} = multi, name, schema_or_fn, scope_or_attrs, attrs \\ %{}, opts \\ [])

  # Update by scope
  def update(%Multi{} = multi, name, schema, scope_builder, attrs, opts)
      when is_atom(schema) and is_function(scope_builder, 1) do
    Multi.run(multi, name, fn _repo, _changes ->
      Crud.new(schema)
      |> Crud.where(scope_builder)
      |> Crud.update(attrs, opts)
      |> Crud.execute()
    end)
  end

  # Update struct from previous step
  def update(%Multi{} = multi, name, struct_fn, attrs, _empty, opts)
      when is_function(struct_fn, 1) and is_map(attrs) do
    Multi.run(multi, name, fn _repo, changes ->
      struct = struct_fn.(changes)

      struct
      |> Ecto.Changeset.cast(attrs, Map.keys(attrs))
      |> maybe_add_updated_by(opts)
      |> Repo.update()
    end)
  end

  @doc """
  Updates all records matching a scope in the transaction.

  ## Options

  - `:updated_by` - User ID for audit trail

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.update_all(:publish_all, Product, fn scope ->
        scope |> Scope.status("draft")
      end, %{status: "published"}, updated_by: user_id)
  """
  @spec update_all(t(), step_name(), schema_module(), scope_builder(), map(), keyword()) :: t()
  def update_all(%Multi{} = multi, name, schema, scope_builder, attrs, opts \\ []) do
    Multi.run(multi, name, fn _repo, _changes ->
      Crud.new(schema)
      |> Crud.where(scope_builder)
      |> Crud.update_all(attrs, opts)
      |> Crud.execute()
    end)
  end

  @doc """
  Soft deletes records in the transaction.

  ## Options

  - `:deleted_by` - User ID for audit trail
  - `:hard` - If true, permanently deletes (default: false)

  ## Examples

      # Soft delete
      TransactionBuilder.new()
      |> TransactionBuilder.delete(:archive_product, Product, fn scope ->
        scope |> Scope.eq("id", product_id)
      end, deleted_by: user_id)

      # Hard delete
      TransactionBuilder.new()
      |> TransactionBuilder.delete(:purge_product, Product, fn scope ->
        scope |> Scope.eq("id", product_id)
      end, hard: true)
  """
  @spec delete(t(), step_name(), schema_module(), scope_builder(), keyword()) :: t()
  def delete(%Multi{} = multi, name, schema, scope_builder, opts \\ []) do
    Multi.run(multi, name, fn _repo, _changes ->
      Crud.new(schema)
      |> Crud.where(scope_builder)
      |> Crud.delete(opts)
      |> Crud.execute()
    end)
  end

  @doc """
  Restores soft-deleted records in the transaction.

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.restore(:restore_product, Product, fn scope ->
        scope |> Scope.eq("id", product_id)
      end)
  """
  @spec restore(t(), step_name(), schema_module(), scope_builder()) :: t()
  def restore(%Multi{} = multi, name, schema, scope_builder) do
    Multi.run(multi, name, fn _repo, _changes ->
      Crud.new(schema)
      |> Crud.where(scope_builder)
      |> Crud.restore()
      |> Crud.execute()
    end)
  end

  @doc """
  Runs a custom function in the transaction.

  The function receives a map of results from previous steps.

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:order, Order, %{total: 99.99}, created_by: user_id)
      |> TransactionBuilder.run(:process_payment, fn %{order: order} ->
        PaymentProcessor.charge(order.customer_id, order.total)
      end)
  """
  @spec run(t(), step_name(), (map() -> {:ok, any()} | {:error, any()})) :: t()
  def run(%Multi{} = multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn _repo, changes ->
      fun.(changes)
    end)
  end

  @doc """
  Adds a step that always succeeds (for side effects).

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:user, User, user_attrs, created_by: admin_id)
      |> TransactionBuilder.tap(:log_creation, fn %{user: user} ->
        Logger.info("Created user: #{user.id}")
      end)
  """
  @spec tap(t(), step_name(), (map() -> any())) :: t()
  def tap(%Multi{} = multi, name, fun) when is_function(fun, 1) do
    Multi.run(multi, name, fn _repo, changes ->
      fun.(changes)
      {:ok, :done}
    end)
  end

  @doc """
  Merges another Multi into this transaction.

  ## Examples

      other_multi = Multi.new()
        |> Multi.insert(:tag, Tag.changeset(%Tag{}, %{name: "featured"}))

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:product, Product, %{name: "Widget"}, created_by: user_id)
      |> TransactionBuilder.merge(other_multi)
  """
  @spec merge(t(), t()) :: t()
  def merge(%Multi{} = multi, %Multi{} = other_multi) do
    Multi.append(multi, other_multi)
  end

  @doc """
  Executes the transaction.

  Returns `{:ok, changes}` if all steps succeed, or `{:error, failed_operation, failed_value, changes_so_far}`.

  ## Examples

      case TransactionBuilder.new()
        |> TransactionBuilder.insert(:product, Product, %{name: "Widget"}, created_by: user_id)
        |> TransactionBuilder.execute() do
        {:ok, %{product: product}} ->
          IO.puts("Created product: #{product.id}")

        {:error, :product, changeset, _} ->
          IO.puts("Failed to create product: #{inspect(changeset.errors)}")
      end
  """
  @spec execute(t()) :: {:ok, map()} | {:error, atom(), any(), map()}
  def execute(%Multi{} = multi) do
    Repo.transaction(multi)
  end

  @doc """
  Executes the transaction, raising on error.

  ## Examples

      %{product: product} = TransactionBuilder.new()
        |> TransactionBuilder.insert(:product, Product, %{name: "Widget"}, created_by: user_id)
        |> TransactionBuilder.execute!()
  """
  @spec execute!(t()) :: map()
  def execute!(%Multi{} = multi) do
    case execute(multi) do
      {:ok, changes} ->
        changes

      {:error, failed_operation, failed_value, _changes_so_far} ->
        raise "Transaction failed at step #{failed_operation}: #{inspect(failed_value)}"
    end
  end

  ## Conditional Operations

  @doc """
  Conditionally adds a step to the transaction.

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:user, User, user_attrs, created_by: admin_id)
      |> TransactionBuilder.when(send_email?, fn multi ->
        TransactionBuilder.run(multi, :send_email, fn %{user: user} ->
          Email.send_welcome(user)
        end)
      end)
  """
  @spec when(t(), boolean(), (t() -> t())) :: t()
  def when(%Multi{} = multi, condition, fun) when is_function(fun, 1) do
    if condition do
      fun.(multi)
    else
      multi
    end
  end

  @doc """
  Conditionally adds a step based on previous results.

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.insert(:order, Order, %{total: 100}, created_by: user_id)
      |> TransactionBuilder.when_result(:order, fn order ->
        order.total > 50
      end, fn multi ->
        TransactionBuilder.run(multi, :apply_discount, fn %{order: order} ->
          # Apply bulk discount
          {:ok, order}
        end)
      end)
  """
  @spec when_result(t(), step_name(), (any() -> boolean()), (t() -> t())) :: t()
  def when_result(%Multi{} = multi, step_name, condition_fn, then_fn)
      when is_function(condition_fn, 1) and is_function(then_fn, 1) do
    Multi.run(multi, :"check_#{step_name}", fn _repo, changes ->
      result = Map.get(changes, step_name)

      if condition_fn.(result) do
        {:ok, :condition_met}
      else
        {:ok, :condition_not_met}
      end
    end)
    |> then(fn updated_multi ->
      Multi.run(updated_multi, :"conditional_#{step_name}", fn _repo, changes ->
        if changes[:"check_#{step_name}"] == :condition_met do
          # Execute the conditional multi
          case then_fn.(Multi.new()) |> Repo.transaction() do
            {:ok, results} -> {:ok, results}
            {:error, _step, error, _} -> {:error, error}
          end
        else
          {:ok, :skipped}
        end
      end)
    end)
  end

  ## Query Helpers

  @doc """
  Fetches records in the transaction using QueryBuilder.

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.fetch(:products, Product, fn qb ->
        qb
        |> QueryBuilder.active()
        |> QueryBuilder.scope(fn s -> s |> Scope.status("published") end)
      end)
      |> TransactionBuilder.run(:process_products, fn %{products: products} ->
        # Do something with products
        {:ok, length(products)}
      end)
  """
  @spec fetch(t(), step_name(), schema_module(), (QueryBuilder.t() -> QueryBuilder.t())) :: t()
  def fetch(%Multi{} = multi, name, schema, query_builder_fn)
      when is_function(query_builder_fn, 1) do
    Multi.run(multi, name, fn _repo, _changes ->
      results =
        QueryBuilder.new(schema)
        |> query_builder_fn.()
        |> QueryBuilder.all()

      {:ok, results}
    end)
  end

  @doc """
  Fetches a single record in the transaction using QueryBuilder.

  ## Examples

      TransactionBuilder.new()
      |> TransactionBuilder.fetch_one(:product, Product, fn qb ->
        qb |> QueryBuilder.scope(fn s -> s |> Scope.eq("id", product_id) end)
      end)
  """
  @spec fetch_one(t(), step_name(), schema_module(), (QueryBuilder.t() -> QueryBuilder.t())) ::
          t()
  def fetch_one(%Multi{} = multi, name, schema, query_builder_fn)
      when is_function(query_builder_fn, 1) do
    Multi.run(multi, name, fn _repo, _changes ->
      result =
        QueryBuilder.new(schema)
        |> query_builder_fn.()
        |> QueryBuilder.one()

      case result do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    end)
  end

  ## Private Helpers

  defp maybe_add_updated_by(changeset, opts) do
    if updated_by = Keyword.get(opts, :updated_by) do
      Ecto.Changeset.put_change(changeset, :updated_by_urm_id, updated_by)
    else
      changeset
    end
  end
end
