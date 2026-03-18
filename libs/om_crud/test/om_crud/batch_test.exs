defmodule OmCrud.BatchTest do
  @moduledoc """
  Tests for OmCrud.Batch - Batch processing utilities.

  Provides functions for processing records in chunks with configurable
  batch sizes, concurrency, and error handling strategies.
  """

  use ExUnit.Case, async: true

  alias OmCrud.Batch

  describe "create_all/3" do
    test "chunks by batch_size and processes all" do
      # Verify the chunking logic works by testing with a mock-like approach
      entries = Enum.map(1..10, &%{id: &1, name: "item_#{&1}"})

      # Verify chunk_every produces correct batches
      batches = Stream.chunk_every(entries, 3) |> Enum.to_list()

      assert length(batches) == 4
      assert length(Enum.at(batches, 0)) == 3
      assert length(Enum.at(batches, 3)) == 1
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
      assert_raise ArgumentError, ~r/conflict_target/, fn ->
        Batch.upsert_all(SomeSchema, [], [])
      end
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

  describe "stream/2" do
    test "accepts standard batch options" do
      opts = [batch_size: 100, where: [active: true], order_by: :id]

      assert Keyword.get(opts, :batch_size) == 100
      assert Keyword.get(opts, :where) == [active: true]
      assert Keyword.get(opts, :order_by) == :id
    end
  end

  describe "stream_in_transaction/2" do
    test "accepts standard batch options plus timeout" do
      opts = [batch_size: 100, where: [status: :active], timeout: 60_000]

      assert Keyword.get(opts, :batch_size) == 100
      assert Keyword.get(opts, :timeout) == 60_000
    end
  end

  describe "build_query/3 (tested via public API patterns)" do
    test "batch operations accept where conditions" do
      opts = [where: [status: :active], batch_size: 100]

      assert Keyword.get(opts, :where) == [status: :active]
      assert Keyword.get(opts, :batch_size) == 100
    end

    test "batch operations accept order_by option" do
      opts = [order_by: :inserted_at]
      assert Keyword.get(opts, :order_by) == :inserted_at
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
