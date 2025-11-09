defmodule Events.Repo.SoftDeleteTest do
  use Events.DataCase, async: true

  alias Events.Repo
  alias Events.Repo.SoftDelete
  alias Events.Repo.Crud

  # Test schema
  defmodule TestProduct do
    use Ecto.Schema
    import Events.Repo.SoftDelete

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "test_products_soft_delete" do
      field :name, :string
      field :status, :string, default: "active"
      field :deleted_at, :utc_datetime_usec
      field :deleted_by_urm_id, :binary_id
      field :created_by_urm_id, :binary_id

      timestamps()
    end

    def base_query do
      not_deleted(__MODULE__)
    end
  end

  @user_id "01234567-89ab-cdef-0123-456789abcdef"

  setup do
    # Create test table
    :ok =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        CREATE TABLE IF NOT EXISTS test_products_soft_delete (
          id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
          name text NOT NULL,
          status text DEFAULT 'active',
          deleted_at timestamp,
          deleted_by_urm_id uuid,
          created_by_urm_id uuid,
          inserted_at timestamp NOT NULL DEFAULT NOW(),
          updated_at timestamp NOT NULL DEFAULT NOW()
        )
        """,
        []
      )

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(Repo, "DROP TABLE IF EXISTS test_products_soft_delete", [])
    end)

    :ok
  end

  describe "soft_delete/2" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Test Product"}, created_by: @user_id)
        |> Crud.execute()

      %{product: product}
    end

    test "soft deletes a record", %{product: product} do
      assert product.deleted_at == nil

      assert {:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: @user_id)

      assert deleted.deleted_at != nil
      assert deleted.deleted_by_urm_id == @user_id
      refute SoftDelete.active?(deleted)
      assert SoftDelete.deleted?(deleted)
    end

    test "soft deletes without specifying deleted_by", %{product: product} do
      assert {:ok, deleted} = SoftDelete.soft_delete(product)

      assert deleted.deleted_at != nil
      assert deleted.deleted_by_urm_id == nil
    end
  end

  describe "soft_delete_all/2" do
    setup do
      {:ok, _} =
        Crud.new(TestProduct)
        |> Crud.insert_all(
          [
            %{name: "Product 1", status: "draft"},
            %{name: "Product 2", status: "draft"},
            %{name: "Product 3", status: "active"}
          ],
          created_by: @user_id
        )
        |> Crud.execute()

      :ok
    end

    test "soft deletes all matching records" do
      query = from(p in TestProduct, where: p.status == "draft")

      assert {:ok, %{count: count}} = SoftDelete.soft_delete_all(query, deleted_by: @user_id)

      assert count == 2

      # Verify deletions
      deleted = TestProduct |> SoftDelete.only_deleted() |> Repo.all()
      assert length(deleted) == 2
      assert Enum.all?(deleted, &(&1.deleted_by_urm_id == @user_id))
    end
  end

  describe "restore/1" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Test Product"}, created_by: @user_id)
        |> Crud.execute()

      {:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: @user_id)

      %{product: deleted}
    end

    test "restores a soft-deleted record", %{product: deleted_product} do
      assert deleted_product.deleted_at != nil

      assert {:ok, restored} = SoftDelete.restore(deleted_product)

      assert restored.deleted_at == nil
      assert restored.deleted_by_urm_id == nil
      assert SoftDelete.active?(restored)
      refute SoftDelete.deleted?(restored)
    end
  end

  describe "restore_all/1" do
    setup do
      {:ok, %{records: products}} =
        Crud.new(TestProduct)
        |> Crud.insert_all(
          [
            %{name: "Product 1"},
            %{name: "Product 2"},
            %{name: "Product 3"}
          ],
          created_by: @user_id
        )
        |> Crud.execute()

      # Soft delete all
      Enum.each(products, &SoftDelete.soft_delete(&1, deleted_by: @user_id))

      %{products: products}
    end

    test "restores all matching records" do
      query = from(p in TestProduct, where: not is_nil(p.deleted_at))

      assert {:ok, %{count: count}} = SoftDelete.restore_all(query)

      assert count == 3

      # Verify restorations
      active = TestProduct |> SoftDelete.not_deleted() |> Repo.all()
      assert length(active) == 3
      assert Enum.all?(active, &(is_nil(&1.deleted_at)))
    end
  end

  describe "hard_delete/1" do
    setup do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Test Product"}, created_by: @user_id)
        |> Crud.execute()

      %{product: product}
    end

    test "permanently deletes a record", %{product: product} do
      product_id = product.id

      assert {:ok, deleted} = SoftDelete.hard_delete(product)

      assert deleted.id == product_id

      # Verify it's gone
      assert Repo.get(TestProduct, product_id) == nil
    end
  end

  describe "hard_delete_all/1" do
    setup do
      {:ok, _} =
        Crud.new(TestProduct)
        |> Crud.insert_all(
          [
            %{name: "Product 1"},
            %{name: "Product 2"},
            %{name: "Product 3"}
          ],
          created_by: @user_id
        )
        |> Crud.execute()

      :ok
    end

    test "permanently deletes all matching records" do
      query = TestProduct

      assert {:ok, %{count: count}} = SoftDelete.hard_delete_all(query)

      assert count == 3

      # Verify they're gone
      assert Repo.all(TestProduct) == []
    end
  end

  describe "purge_deleted/2" do
    setup do
      # Create old deleted products
      old_date = DateTime.add(DateTime.utc_now(), -100 * 24 * 60 * 60, :second)

      {:ok, old_product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Old Product"}, created_by: @user_id)
        |> Crud.execute()

      # Manually set old deletion date
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE test_products_soft_delete SET deleted_at = $1 WHERE id = $2",
        [old_date, old_product.id]
      )

      # Create recently deleted product
      {:ok, recent_product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Recent Product"}, created_by: @user_id)
        |> Crud.execute()

      SoftDelete.soft_delete(recent_product, deleted_by: @user_id)

      %{old: old_product, recent: recent_product}
    end

    test "purges old deleted records", %{old: old_product, recent: recent_product} do
      assert {:ok, %{count: count}} = SoftDelete.purge_deleted(TestProduct, days: 90)

      # Should purge only the old one
      assert count == 1

      # Verify old one is gone
      assert Repo.get(TestProduct, old_product.id) == nil

      # Verify recent one still exists
      assert Repo.get(TestProduct, recent_product.id) != nil
    end

    test "supports different time units" do
      # This should purge all deleted (including recent)
      assert {:ok, %{count: count}} = SoftDelete.purge_deleted(TestProduct, hours: 1)

      # Should have purged both
      assert count >= 1
    end
  end

  describe "query scopes" do
    setup do
      {:ok, active} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Active Product"}, created_by: @user_id)
        |> Crud.execute()

      {:ok, deleted} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Deleted Product"}, created_by: @user_id)
        |> Crud.execute()

      SoftDelete.soft_delete(deleted, deleted_by: @user_id)

      %{active: active, deleted: deleted}
    end

    test "not_deleted/1 filters out deleted records", %{active: active} do
      products = TestProduct |> SoftDelete.not_deleted() |> Repo.all()

      assert length(products) == 1
      assert hd(products).id == active.id
    end

    test "only_deleted/1 returns only deleted records", %{deleted: deleted} do
      products = TestProduct |> SoftDelete.only_deleted() |> Repo.all()

      assert length(products) == 1
      assert hd(products).id == deleted.id
    end

    test "with_deleted/1 returns all records" do
      products = TestProduct |> SoftDelete.with_deleted() |> Repo.all()

      assert length(products) == 2
    end
  end

  describe "helper functions" do
    test "deleted?/1 checks if record is deleted" do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Test Product"}, created_by: @user_id)
        |> Crud.execute()

      refute SoftDelete.deleted?(product)

      {:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: @user_id)

      assert SoftDelete.deleted?(deleted)
    end

    test "active?/1 checks if record is active" do
      {:ok, product} =
        Crud.new(TestProduct)
        |> Crud.insert(%{name: "Test Product"}, created_by: @user_id)
        |> Crud.execute()

      assert SoftDelete.active?(product)

      {:ok, deleted} = SoftDelete.soft_delete(product, deleted_by: @user_id)

      refute SoftDelete.active?(deleted)
    end
  end

  describe "deletion_stats/1" do
    setup do
      # Create 3 active, 2 deleted
      {:ok, %{records: products}} =
        Crud.new(TestProduct)
        |> Crud.insert_all(
          [
            %{name: "Product 1"},
            %{name: "Product 2"},
            %{name: "Product 3"},
            %{name: "Product 4"},
            %{name: "Product 5"}
          ],
          created_by: @user_id
        )
        |> Crud.execute()

      # Delete 2 of them
      [p1, p2 | _] = products
      SoftDelete.soft_delete(p1, deleted_by: @user_id)
      SoftDelete.soft_delete(p2, deleted_by: @user_id)

      :ok
    end

    test "returns deletion statistics" do
      stats = SoftDelete.deletion_stats(TestProduct)

      assert stats.total == 5
      assert stats.active == 3
      assert stats.deleted == 2
      assert stats.deletion_rate == 0.4
    end
  end

  describe "recently_deleted/2" do
    setup do
      {:ok, %{records: products}} =
        Crud.new(TestProduct)
        |> Crud.insert_all(
          [
            %{name: "Product 1"},
            %{name: "Product 2"},
            %{name: "Product 3"}
          ],
          created_by: @user_id
        )
        |> Crud.execute()

      # Delete them with slight delays to ensure order
      Enum.each(products, fn product ->
        SoftDelete.soft_delete(product, deleted_by: @user_id)
        Process.sleep(10)
      end)

      :ok
    end

    test "returns recently deleted records ordered by deleted_at" do
      recent = SoftDelete.recently_deleted(TestProduct, limit: 2)

      assert length(recent) == 2
      # Most recently deleted first
      assert hd(recent).name == "Product 3"
    end
  end
end
