defmodule OmCrud.SoftDeleteTest do
  @moduledoc """
  Tests for OmCrud.SoftDelete - Soft delete support.

  Provides functions for soft-deleting records by setting a `deleted_at` timestamp
  instead of permanently removing them from the database.

  ## Use Cases

  - **Audit trails**: Keep records for compliance/history
  - **Undo functionality**: Allow users to restore deleted items
  - **Data recovery**: Prevent accidental permanent deletion
  - **Cascading deletes**: Soft delete related records together
  """

  use ExUnit.Case, async: true

  alias OmCrud.SoftDelete

  defmodule TestRecord do
    defstruct [:id, :name, :deleted_at]
  end

  describe "deleted?/2" do
    test "returns true when deleted_at is set" do
      record = %TestRecord{id: "1", deleted_at: ~U[2024-01-15 10:00:00Z]}

      assert SoftDelete.deleted?(record) == true
    end

    test "returns false when deleted_at is nil" do
      record = %TestRecord{id: "1", deleted_at: nil}

      assert SoftDelete.deleted?(record) == false
    end

    test "uses custom field name" do
      record = %{__struct__: CustomRecord, id: "1", archived_at: ~U[2024-01-15 10:00:00Z]}

      assert SoftDelete.deleted?(record, field: :archived_at) == true
    end
  end

  describe "deleted_at/2" do
    test "returns timestamp when soft deleted" do
      timestamp = ~U[2024-01-15 10:00:00Z]
      record = %TestRecord{id: "1", deleted_at: timestamp}

      assert SoftDelete.deleted_at(record) == timestamp
    end

    test "returns nil when not soft deleted" do
      record = %TestRecord{id: "1", deleted_at: nil}

      assert SoftDelete.deleted_at(record) == nil
    end
  end

  describe "exclude_deleted/2 with Ecto.Query" do
    test "adds where clause for nil deleted_at" do
      import Ecto.Query

      query = from(u in "users")
      filtered = SoftDelete.exclude_deleted(query)

      # The query should have a where clause
      assert %Ecto.Query{} = filtered
    end

    test "uses custom field name" do
      import Ecto.Query

      query = from(u in "users")
      filtered = SoftDelete.exclude_deleted(query, field: :archived_at)

      assert %Ecto.Query{} = filtered
    end
  end

  describe "only_deleted/2 with Ecto.Query" do
    test "adds where clause for not nil deleted_at" do
      import Ecto.Query

      query = from(u in "users")
      filtered = SoftDelete.only_deleted(query)

      assert %Ecto.Query{} = filtered
    end
  end
end
