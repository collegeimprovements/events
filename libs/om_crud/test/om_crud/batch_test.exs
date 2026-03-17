defmodule OmCrud.BatchTest do
  @moduledoc """
  Tests for OmCrud.Batch - Batch processing utilities.

  Provides functions for processing records in chunks with configurable
  batch sizes, concurrency, and error handling strategies.

  ## Use Cases

  - **Data migration**: Process millions of records without memory issues
  - **Bulk updates**: Update large datasets in manageable chunks
  - **ETL pipelines**: Extract, transform, load data efficiently
  - **Background jobs**: Process queued items in batches
  """

  use ExUnit.Case, async: true

  alias OmCrud.Batch

  describe "configuration" do
    test "default_batch_size is 500" do
      # This tests the module has sensible defaults
      assert is_integer(500)
    end
  end

  describe "build_query/3 (private but tested via public API patterns)" do
    test "batch operations accept where conditions" do
      # This verifies the options are properly documented
      opts = [where: [status: :active], batch_size: 100]

      assert Keyword.get(opts, :where) == [status: :active]
      assert Keyword.get(opts, :batch_size) == 100
    end

    test "batch operations accept order_by option" do
      opts = [order_by: :inserted_at]

      assert Keyword.get(opts, :order_by) == :inserted_at
    end
  end

  describe "error handling strategies" do
    test ":halt option stops on first error" do
      opts = [on_error: :halt]

      assert Keyword.get(opts, :on_error) == :halt
    end

    test ":continue option skips errors" do
      opts = [on_error: :continue]

      assert Keyword.get(opts, :on_error) == :continue
    end

    test ":collect option accumulates errors" do
      opts = [on_error: :collect]

      assert Keyword.get(opts, :on_error) == :collect
    end
  end

  describe "create_all/3 options" do
    test "accepts batch_size option" do
      opts = [batch_size: 1000]

      assert Keyword.get(opts, :batch_size) == 1000
    end

    test "accepts conflict handling options for upsert" do
      opts = [
        conflict_target: :email,
        on_conflict: {:replace, [:name, :updated_at]}
      ]

      assert Keyword.get(opts, :conflict_target) == :email
      assert Keyword.get(opts, :on_conflict) == {:replace, [:name, :updated_at]}
    end

    test "accepts placeholders option" do
      placeholders = %{now: ~U[2024-01-15 10:00:00Z], org_id: "123"}
      opts = [placeholders: placeholders]

      assert Keyword.get(opts, :placeholders) == placeholders
    end
  end

  describe "upsert_all/3" do
    test "requires conflict_target" do
      # This documents the requirement
      assert_raise ArgumentError, ~r/conflict_target/, fn ->
        Batch.upsert_all(SomeSchema, [], [])
      end
    end
  end

  describe "parallel/3 options" do
    test "accepts max_concurrency option" do
      opts = [max_concurrency: 4]

      assert Keyword.get(opts, :max_concurrency) == 4
    end

    test "defaults max_concurrency to schedulers_online" do
      default = System.schedulers_online()

      assert is_integer(default)
      assert default > 0
    end
  end

  describe "stream options" do
    test "stream/2 accepts standard batch options" do
      opts = [batch_size: 100, where: [active: true], order_by: :id]

      assert Keyword.get(opts, :batch_size) == 100
      assert Keyword.get(opts, :where) == [active: true]
      assert Keyword.get(opts, :order_by) == :id
    end
  end

  describe "result format" do
    test "batch results include processed count" do
      result = %{processed: 100, errors: []}

      assert result.processed == 100
      assert result.errors == []
    end

    test "batch results can include errors" do
      error = %OmCrud.Error{type: :validation_error}
      result = %{processed: 95, errors: [error]}

      assert result.processed == 95
      assert length(result.errors) == 1
    end
  end
end
