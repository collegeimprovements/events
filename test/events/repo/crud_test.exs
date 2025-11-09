defmodule Events.Repo.CrudTest do
  use Events.DataCase, async: true

  alias Events.Repo
  alias Events.Repo.Crud
  alias Events.Repo.SqlScope.Scope
  alias Events.Repo.SoftDelete

  # Test schema
  defmodule TestProduct do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "test_products" do
      field :name, :string
      field :slug, :string
      field :description, :string
      field :price, :decimal
      field :status, :string, default: "draft"
      field :type, :string
      field :subtype, :string
      field :metadata, :map

      field :created_by_urm_id, :binary_id
      field :updated_by_urm_id, :binary_id
      field :deleted_at, :utc_datetime_usec
      field :deleted_by_urm_id, :binary_id

      timestamps()
    end
  end

  @user_id "01234567-89ab-cdef-0123-456789abcdef"

  setup do
    # Create test table
    :ok =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        CREATE TABLE IF NOT EXISTS test_products (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          name text NOT NULL,
          slug text,
          description text,
          price decimal,
          status text DEFAULT 'draft',
          type text,
          subtype text,
          metadata jsonb,
          created_by_urm_id uuid,
          updated_by_urm_id uuid,
          deleted_at timestamp,
          deleted_by_urm_id uuid,
          inserted_at timestamp NOT NULL DEFAULT NOW(),
          updated_at timestamp NOT NULL DEFAULT NOW()
        )
        """,
        []
      )

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(Repo, "DROP TABLE IF EXISTS test_products", [])
    end)

    :ok
  end

  describe "insert/3" do
    test "inserts a single record with audit fields" do
      attrs = %{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("9.99")
      }

      assert {:ok, product} =
               Crud.new(TestProduct)
               |> Crud.insert(attrs, created_by: @user_id)
               |> Crud.execute()

      assert product.name == "Test Product"
      assert product.slug == "test-product"
      assert Decimal.eq?(product.price, Decimal.new("9.99"))
      assert product.created_by_urm_id == @user_id
      assert product.updated_by_urm_id == @user_id
      assert product.deleted_at == nil
    end

    test "inserts with metadata" do
      attrs = %{
        name: "Featured Product",
        metadata: %{featured: true, color: "blue"}
      }

      assert {:ok, product} =
               Crud.new(TestProduct)
               |> Crud.insert(attrs, created_by: @user_id)
               |> Crud.execute()

      assert product.metadata["featured"] == true
      assert product.metadata["color"] == "blue"
    end
  end

  describe "insert_all/3" do
    test "inserts multiple records" do
      attrs_list = [
        %{name: "Product 1", slug: "product-1", price: Decimal.new("9.99")},
        %{name: "Product 2", slug: "product-2", price: Decimal.new("19.99")},
        %{name: "Product 3", slug: "product-3", price: Decimal.new("29.99")}
      ]

      assert {:ok, %{count: count, records: records}} =
               Crud.new(TestProduct)
               |> Crud.insert_all(attrs_list, created_by: @user_id)
               |> Crud.execute()

      assert count == 3
      assert length(records) == 3
      assert Enum.all?(records, &(&1.created_by_urm_id == @user_id))
    end
  end

  describe "select/1" do
    setup do
      # Insert test data
      {:ok, p1} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Active Product", status: "active"}, created_by: @user_id)
        |> Crud.execute()

      {:ok, p2} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Draft Product", status: "draft"}, created_by: @user_id)
        |> Crud.execute()

      {:ok, p3} =
        Crud.new(TestProduct)
        |> Crud.insert(
          %{name: "Deleted Product", status: "active"},
          created_by: @user_id
        )
        |> Crud.execute()

      SoftDelete.soft_delete(p3, deleted_by: @user_id)

      %{active: p1, draft: p2, deleted: p3}
    end

    test "selects all records with scope" do
      assert {:ok, products} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.status(scope, "active") end)
               |> Crud.select()
               |> Crud.execute()

      # Should find 2: active (not deleted) + deleted (which is also active status)
      assert length(products) == 2
    end

    test "selects only non-deleted active records" do
      assert {:ok, products} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope ->
                 scope
                 |> Scope.active()
               end)
               |> Crud.select()
               |> Crud.execute()

      # Should find only 1: active status AND not deleted
      assert length(products) == 1
      assert hd(products).name == "Active Product"
    end
  end

  describe "select_one/1" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Single Product", slug: "single"}, created_by: @user_id)
        |> Crud.execute()

      %{product: product}
    end

    test "selects a single record by scope", %{product: product} do
      assert {:ok, found} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
               |> Crud.select_one()
               |> Crud.execute()

      assert found.id == product.id
      assert found.name == "Single Product"
    end

    test "returns nil when no record found" do
      assert {:ok, nil} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "slug", "nonexistent") end)
               |> Crud.select_one()
               |> Crud.execute()
    end
  end

  describe "update/3" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(
          %{name: "Original Name", price: Decimal.new("9.99")},
          created_by: @user_id
        )
        |> Crud.execute()

      %{product: product}
    end

    test "updates a record by scope", %{product: product} do
      new_user_id = "11111111-1111-1111-1111-111111111111"

      assert {:ok, updated} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
               |> Crud.update(%{name: "Updated Name"}, updated_by: new_user_id)
               |> Crud.execute()

      assert updated.name == "Updated Name"
      assert updated.updated_by_urm_id == new_user_id
      assert updated.created_by_urm_id == @user_id
    end

    test "updates a struct directly", %{product: product} do
      assert {:ok, updated} =
               Crud.new(TestProduct)
               |> Crud.update(product, %{price: Decimal.new("19.99")}, updated_by: @user_id)
               |> Crud.execute()

      assert Decimal.eq?(updated.price, Decimal.new("19.99"))
    end
  end

  describe "update_all/3" do
    setup do
      # Create multiple products
      Crud.new(TestProduct)
      |> Crud.insert_all(
        [
          %{name: "Draft 1", status: "draft"},
          %{name: "Draft 2", status: "draft"},
          %{name: "Active 1", status: "active"}
        ],
        created_by: @user_id
      )
      |> Crud.execute()

      :ok
    end

    test "updates all matching records" do
      assert {:ok, %{count: count}} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.status(scope, "draft") end)
               |> Crud.update_all(%{status: "published"}, updated_by: @user_id)
               |> Crud.execute()

      assert count == 2

      # Verify updates
      {:ok, published} =
        Crud.new(TestProduct)
        |> Crud.where(fn scope -> Scope.status(scope, "published") end)
        |> Crud.select()
        |> Crud.execute()

      assert length(published) == 2
    end
  end

  describe "delete/2 (soft delete)" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "To Be Deleted"}, created_by: @user_id)
        |> Crud.execute()

      %{product: product}
    end

    test "soft deletes a record", %{product: product} do
      assert {:ok, %{count: count}} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
               |> Crud.delete(deleted_by: @user_id)
               |> Crud.execute()

      assert count == 1

      # Verify soft delete
      {:ok, deleted} =
        Crud.new(TestProduct)
        |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
        |> Crud.select_one()
        |> Crud.execute()

      assert deleted.deleted_at != nil
      assert deleted.deleted_by_urm_id == @user_id
    end

    test "hard deletes a record permanently", %{product: product} do
      assert {:ok, %{count: count}} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
               |> Crud.delete(hard: true)
               |> Crud.execute()

      assert count == 1

      # Verify hard delete
      {:ok, found} =
        Crud.new(TestProduct)
        |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
        |> Crud.select_one()
        |> Crud.execute()

      assert found == nil
    end
  end

  describe "restore/1" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "To Be Restored"}, created_by: @user_id)
        |> Crud.execute()

      # Soft delete it
      Crud.new(TestProduct)
      |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
      |> Crud.delete(deleted_by: @user_id)
      |> Crud.execute()

      %{product: product}
    end

    test "restores a soft-deleted record", %{product: product} do
      assert {:ok, %{count: count}} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
               |> Crud.restore()
               |> Crud.execute()

      assert count == 1

      # Verify restoration
      {:ok, restored} =
        Crud.new(TestProduct)
        |> Crud.where(fn scope -> Scope.eq(scope, "id", product.id) end)
        |> Crud.select_one()
        |> Crud.execute()

      assert restored.deleted_at == nil
      assert restored.deleted_by_urm_id == nil
    end
  end

  describe "count/1" do
    setup do
      Crud.new(TestProduct)
      |> Crud.insert_all(
        [
          %{name: "Product 1", status: "active"},
          %{name: "Product 2", status: "active"},
          %{name: "Product 3", status: "draft"}
        ],
        created_by: @user_id
      )
      |> Crud.execute()

      :ok
    end

    test "counts records matching scope" do
      assert {:ok, count} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.status(scope, "active") end)
               |> Crud.count()
               |> Crud.execute()

      assert count == 2
    end

    test "counts all records when no scope" do
      assert {:ok, count} =
               Crud.new(TestProduct)
               |> Crud.count()
               |> Crud.execute()

      assert count == 3
    end
  end

  describe "exists?/1" do
    setup do
      {:ok, _} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Existing Product", slug: "existing"}, created_by: @user_id)
        |> Crud.execute()

      :ok
    end

    test "returns true when record exists" do
      assert {:ok, true} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "slug", "existing") end)
               |> Crud.exists?()
               |> Crud.execute()
    end

    test "returns false when record does not exist" do
      assert {:ok, false} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope -> Scope.eq(scope, "slug", "nonexistent") end)
               |> Crud.exists?()
               |> Crud.execute()
    end
  end

  describe "complex scopes" do
    setup do
      Crud.new(TestProduct)
      |> Crud.insert_all(
        [
          %{
            name: "Cheap Widget",
            type: "widget",
            price: Decimal.new("5.99"),
            status: "active"
          },
          %{
            name: "Expensive Widget",
            type: "widget",
            price: Decimal.new("99.99"),
            status: "active"
          },
          %{
            name: "Gadget",
            type: "gadget",
            price: Decimal.new("29.99"),
            status: "active"
          },
          %{
            name: "Featured Widget",
            type: "widget",
            price: Decimal.new("49.99"),
            status: "active",
            metadata: %{featured: true}
          }
        ],
        created_by: @user_id
      )
      |> Crud.execute()

      :ok
    end

    test "filters with multiple conditions" do
      assert {:ok, products} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope ->
                 scope
                 |> Scope.active()
                 |> Scope.type("widget")
                 |> Scope.gte("price", Decimal.new("10.00"))
                 |> Scope.lte("price", Decimal.new("50.00"))
               end)
               |> Crud.select()
               |> Crud.execute()

      # Should find "Featured Widget" ($49.99)
      assert length(products) == 1
      assert hd(products).name == "Featured Widget"
    end

    test "filters with JSONB conditions" do
      assert {:ok, products} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope ->
                 scope
                 |> Scope.type("widget")
                 |> Scope.jsonb_eq("metadata", ["featured"], true)
               end)
               |> Crud.select()
               |> Crud.execute()

      assert length(products) == 1
      assert hd(products).name == "Featured Widget"
    end

    test "filters with OR conditions" do
      assert {:ok, products} =
               Crud.new(TestProduct)
               |> Crud.where(fn scope ->
                 scope
                 |> Scope.or_where(fn or_scope ->
                   or_scope
                   |> Scope.type("gadget")
                   |> Scope.jsonb_eq("metadata", ["featured"], true)
                 end)
               end)
               |> Crud.select()
               |> Crud.execute()

      # Should find "Gadget" and "Featured Widget"
      assert length(products) == 2
    end
  end
end
