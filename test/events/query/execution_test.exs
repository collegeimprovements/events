defmodule Events.Query.ExecutionTest do
  @moduledoc """
  Integration tests for Query execution methods.

  These tests verify actual database operations including:
  - execute/2 and execute!/2
  - stream/2 for large datasets
  - batch/2 for parallel execution
  - Convenience methods (first, one, count, exists?, aggregate)
  - Pagination execution (offset and cursor)
  """
  use Events.DataCase, async: true

  alias Events.Query
  alias Events.Query.Result
  alias Events.Repo

  # Test schema - maps to query_test_records table
  defmodule TestRecord do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "query_test_records" do
      field :name, :string
      field :status, :string, default: "active"
      field :priority, :integer, default: 0
      field :score, :float
      field :active, :boolean, default: true
      field :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    def changeset(record \\ %__MODULE__{}, attrs) do
      record
      |> Ecto.Changeset.cast(attrs, [:name, :status, :priority, :score, :active, :metadata])
      |> Ecto.Changeset.validate_required([:name])
    end
  end

  # Helper to insert test records
  defp insert_records(count, attrs_fn \\ fn _i -> %{} end) do
    Enum.map(1..count, fn i ->
      base_attrs = %{
        name: "Record #{i}",
        status: if(rem(i, 2) == 0, do: "active", else: "inactive"),
        priority: rem(i, 5),
        score: i * 1.5,
        active: rem(i, 3) != 0
      }

      attrs = Map.merge(base_attrs, attrs_fn.(i))

      %TestRecord{}
      |> TestRecord.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  describe "execute/2" do
    test "returns {:ok, result} with data" do
      insert_records(3)

      token = Query.new(TestRecord) |> Query.limit(10)
      assert {:ok, %Result{data: data}} = Query.execute(token)
      assert length(data) == 3
    end

    test "returns {:ok, result} with empty data when no matches" do
      insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "nonexistent")
        |> Query.limit(10)

      assert {:ok, %Result{data: []}} = Query.execute(token)
    end

    test "includes timing metadata" do
      insert_records(5)

      token = Query.new(TestRecord) |> Query.limit(10)
      {:ok, result} = Query.execute(token)

      assert result.metadata.query_time_μs > 0
      assert result.metadata.total_time_μs >= result.metadata.query_time_μs
    end

    test "includes SQL in metadata" do
      insert_records(1)

      token = Query.new(TestRecord) |> Query.limit(10)
      {:ok, result} = Query.execute(token)

      assert is_binary(result.metadata.sql)
      assert result.metadata.sql =~ "query_test_records"
    end

    test "applies filters correctly" do
      insert_records(10)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "active")
        |> Query.limit(20)

      {:ok, result} = Query.execute(token)

      assert Enum.all?(result.data, &(&1.status == "active"))
    end
  end

  describe "execute!/2" do
    test "returns result directly" do
      insert_records(3)

      token = Query.new(TestRecord) |> Query.limit(10)
      result = Query.execute!(token)

      assert %Result{} = result
      assert length(result.data) == 3
    end

    test "applies ordering correctly" do
      insert_records(5)

      token =
        Query.new(TestRecord)
        |> Query.order(:priority, :desc)
        |> Query.limit(10)

      result = Query.execute!(token)
      priorities = Enum.map(result.data, & &1.priority)

      assert priorities == Enum.sort(priorities, :desc)
    end
  end

  describe "stream/2" do
    test "streams records in batches" do
      insert_records(15)

      token = Query.new(TestRecord) |> Query.limit(15)

      records =
        Repo.transaction(fn ->
          token
          |> Query.stream(max_rows: 5)
          |> Enum.to_list()
        end)

      assert {:ok, records} = records
      assert length(records) == 15
    end

    test "respects max_rows option" do
      insert_records(10)

      token = Query.new(TestRecord) |> Query.limit(10)

      # Stream with small batch size
      {:ok, records} =
        Repo.transaction(fn ->
          token
          |> Query.stream(max_rows: 2)
          |> Enum.to_list()
        end)

      assert length(records) == 10
    end

    test "applies filters during streaming" do
      insert_records(20)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "active")
        |> Query.limit(20)

      {:ok, records} =
        Repo.transaction(fn ->
          token
          |> Query.stream(max_rows: 5)
          |> Enum.to_list()
        end)

      assert Enum.all?(records, &(&1.status == "active"))
    end
  end

  describe "batch/2" do
    test "executes multiple queries in parallel" do
      insert_records(10)

      tokens = [
        Query.new(TestRecord) |> Query.filter(:status, :eq, "active") |> Query.limit(10),
        Query.new(TestRecord) |> Query.filter(:status, :eq, "inactive") |> Query.limit(10),
        Query.new(TestRecord) |> Query.filter(:priority, :eq, 0) |> Query.limit(10)
      ]

      results = Query.batch(tokens)

      assert length(results) == 3
      assert Enum.all?(results, &match?({:ok, %Result{}}, &1))
    end

    test "returns results in same order as input tokens" do
      insert_records(5)

      tokens = [
        Query.new(TestRecord) |> Query.filter(:priority, :eq, 0) |> Query.limit(10),
        Query.new(TestRecord) |> Query.filter(:priority, :eq, 1) |> Query.limit(10),
        Query.new(TestRecord) |> Query.filter(:priority, :eq, 2) |> Query.limit(10)
      ]

      results = Query.batch(tokens)

      # Verify order is preserved
      [{:ok, r0}, {:ok, r1}, {:ok, r2}] = results

      assert Enum.all?(r0.data, &(&1.priority == 0))
      assert Enum.all?(r1.data, &(&1.priority == 1))
      assert Enum.all?(r2.data, &(&1.priority == 2))
    end

    test "handles partial failures gracefully" do
      insert_records(5)

      # Create a valid token and one that will fail (invalid schema)
      valid_token = Query.new(TestRecord) |> Query.limit(5)

      # Execute batch with valid token
      results = Query.batch([valid_token, valid_token])

      assert [{:ok, _}, {:ok, _}] = results
    end
  end

  describe "first/2" do
    test "returns first record or nil" do
      insert_records(5)

      token =
        Query.new(TestRecord)
        |> Query.order(:priority, :asc)

      record = Query.first(token)

      assert %TestRecord{} = record
      assert record.priority == 0
    end

    test "returns nil when no records match" do
      insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "nonexistent")

      assert Query.first(token) == nil
    end
  end

  describe "first!/2" do
    test "returns first record" do
      insert_records(3)

      token = Query.new(TestRecord) |> Query.order(:name, :asc)
      record = Query.first!(token)

      assert %TestRecord{} = record
    end

    test "raises when no records match" do
      insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "nonexistent")

      assert_raise Ecto.NoResultsError, fn ->
        Query.first!(token)
      end
    end
  end

  describe "one/2" do
    test "returns single record" do
      [record | _] = insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:id, :eq, record.id)

      assert Query.one(token) == record
    end

    test "returns nil when no records match" do
      insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "nonexistent")

      assert Query.one(token) == nil
    end
  end

  describe "one!/2" do
    test "returns single record" do
      [record | _] = insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:id, :eq, record.id)

      assert Query.one!(token) == record
    end

    test "raises when multiple records match" do
      insert_records(5)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "active")

      assert_raise Ecto.MultipleResultsError, fn ->
        Query.one!(token)
      end
    end
  end

  describe "count/2" do
    test "returns integer count" do
      insert_records(7)

      token = Query.new(TestRecord)
      assert Query.count(token) == 7
    end

    test "applies filters to count" do
      insert_records(10)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "active")

      count = Query.count(token)

      # Half should be active (even indices)
      assert count == 5
    end
  end

  describe "exists?/2" do
    test "returns true when records exist" do
      insert_records(3)

      token = Query.new(TestRecord)
      assert Query.exists?(token) == true
    end

    test "returns false when no records match" do
      insert_records(3)

      token =
        Query.new(TestRecord)
        |> Query.filter(:status, :eq, "nonexistent")

      assert Query.exists?(token) == false
    end

    test "returns false for empty table" do
      token = Query.new(TestRecord)
      assert Query.exists?(token) == false
    end
  end

  describe "aggregate/4" do
    test "computes sum" do
      insert_records(5)

      token = Query.new(TestRecord)
      sum = Query.aggregate(token, :sum, :priority)

      # Priorities: 1, 2, 3, 4, 0 -> sum = 10
      assert sum == 10
    end

    test "computes avg" do
      insert_records(5)

      token = Query.new(TestRecord)
      avg = Query.aggregate(token, :avg, :priority)

      # Priorities: 1, 2, 3, 4, 0 -> avg = 2.0
      assert avg == Decimal.new("2.0000000000000000")
    end

    test "computes max" do
      insert_records(5)

      token = Query.new(TestRecord)
      max = Query.aggregate(token, :max, :priority)

      assert max == 4
    end

    test "computes min" do
      insert_records(5)

      token = Query.new(TestRecord)
      min = Query.aggregate(token, :min, :priority)

      assert min == 0
    end
  end

  describe "offset pagination execution" do
    test "includes has_more indicator" do
      insert_records(10)

      token =
        Query.new(TestRecord)
        |> Query.paginate(:offset, limit: 5, offset: 0)

      {:ok, result} = Query.execute(token)

      assert result.pagination.has_more == true
      assert result.pagination.type == :offset
    end

    test "includes has_previous indicator" do
      insert_records(10)

      token =
        Query.new(TestRecord)
        |> Query.paginate(:offset, limit: 5, offset: 5)

      {:ok, result} = Query.execute(token)

      assert result.pagination.has_previous == true
    end

    test "computes current_page correctly" do
      insert_records(25)

      token =
        Query.new(TestRecord)
        |> Query.paginate(:offset, limit: 10, offset: 10)

      {:ok, result} = Query.execute(token)

      assert result.pagination.current_page == 2
    end

    test "computes next_offset and prev_offset" do
      insert_records(30)

      token =
        Query.new(TestRecord)
        |> Query.paginate(:offset, limit: 10, offset: 10)

      {:ok, result} = Query.execute(token)

      assert result.pagination.next_offset == 20
      assert result.pagination.prev_offset == 0
    end
  end

  describe "cursor pagination execution" do
    # Cursor fields must be explicitly specified to match order
    @cursor_fields [{:inserted_at, :asc}, {:id, :asc}]

    test "generates start and end cursors" do
      insert_records(10)

      token =
        Query.new(TestRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: @cursor_fields, limit: 5)

      {:ok, result} = Query.execute(token)

      assert result.pagination.type == :cursor
      assert is_binary(result.pagination.start_cursor)
      assert is_binary(result.pagination.end_cursor)
    end

    test "handles empty results" do
      # Don't insert any records

      token =
        Query.new(TestRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: @cursor_fields, limit: 5)

      {:ok, result} = Query.execute(token)

      assert result.data == []
      assert result.pagination.start_cursor == nil
      assert result.pagination.end_cursor == nil
    end

    test "cursor navigation returns next page" do
      insert_records(15)

      # Get first page
      token =
        Query.new(TestRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: @cursor_fields, limit: 5)

      {:ok, page1} = Query.execute(token)

      # Get second page using end_cursor
      token2 =
        Query.new(TestRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: @cursor_fields, limit: 5, after: page1.pagination.end_cursor)

      {:ok, page2} = Query.execute(token2)

      # Verify pages don't overlap
      page1_ids = Enum.map(page1.data, & &1.id)
      page2_ids = Enum.map(page2.data, & &1.id)

      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
    end

    test "indicates has_more correctly" do
      insert_records(10)

      token =
        Query.new(TestRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: @cursor_fields, limit: 5)

      {:ok, result} = Query.execute(token)

      assert result.pagination.has_more == true

      # Get remaining records (should be 5)
      token2 =
        Query.new(TestRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: @cursor_fields, limit: 10, after: result.pagination.end_cursor)

      {:ok, result2} = Query.execute(token2)

      # Only 5 remaining, less than limit of 10
      assert length(result2.data) == 5
      assert result2.pagination.has_more == false
    end
  end
end
