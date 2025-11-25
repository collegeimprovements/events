# Query Performance Benchmarks
#
# Run with: mix run bench/query_bench.exs
#
# These benchmarks measure:
# - Token building overhead (1, 5, 10, 20 operations)
# - Query execution with varying record counts
# - Cursor pagination traversal
# - Batch query execution

alias Events.Query
alias Events.Repo

# Ensure app is started
Application.ensure_all_started(:events)

# Test schema for benchmarks - same as execution tests
defmodule BenchRecord do
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

# Setup: Insert test records if needed
defmodule BenchSetup do
  def ensure_records(count) do
    existing = Repo.aggregate(BenchRecord, :count)

    if existing < count do
      IO.puts("Inserting #{count - existing} benchmark records...")

      (existing + 1)..count
      |> Enum.chunk_every(1000)
      |> Enum.each(fn chunk ->
        records =
          Enum.map(chunk, fn i ->
            now = DateTime.utc_now()

            %{
              name: "Bench Record #{i}",
              status: if(rem(i, 2) == 0, do: "active", else: "inactive"),
              priority: rem(i, 5),
              score: i * 1.5,
              active: rem(i, 3) != 0,
              metadata: %{},
              inserted_at: now,
              updated_at: now
            }
          end)

        Repo.insert_all(BenchRecord, records)
        IO.write(".")
      end)

      IO.puts("\nDone!")
    else
      IO.puts("#{existing} records already exist, skipping setup.")
    end
  end

  def cleanup do
    IO.puts("Cleaning up benchmark records...")
    Repo.delete_all(BenchRecord)
    IO.puts("Done!")
  end
end

# Ensure we have enough records for benchmarking
BenchSetup.ensure_records(10_000)

IO.puts("\n=== Query Token Building Benchmarks ===\n")

Benchee.run(
  %{
    "token_1_operation" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:active, :eq, true)
    end,
    "token_5_operations" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:active, :eq, true)
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:priority, :gte, 2)
      |> Query.order(:inserted_at, :desc)
      |> Query.limit(20)
    end,
    "token_10_operations" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:active, :eq, true)
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:priority, :gte, 2)
      |> Query.filter(:score, :lt, 500.0)
      |> Query.filter(:name, :like, "%Bench%")
      |> Query.order(:priority, :desc)
      |> Query.order(:inserted_at, :desc)
      |> Query.order(:id, :asc)
      |> Query.paginate(:cursor, cursor_fields: [{:priority, :desc}, {:inserted_at, :desc}, {:id, :asc}], limit: 20)
      |> Query.select([:id, :name, :status, :priority])
    end,
    "token_20_operations" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:active, :eq, true)
      |> Query.filter(:status, :eq, "active")
      |> Query.filter(:priority, :gte, 0)
      |> Query.filter(:priority, :lte, 4)
      |> Query.filter(:score, :gt, 0.0)
      |> Query.filter(:score, :lt, 15000.0)
      |> Query.filter(:name, :like, "%Bench%")
      |> Query.filter(:name, :not_nil, true)
      |> Query.filter(:metadata, :eq, %{})
      |> Query.filter(:id, :not_nil, true)
      |> Query.order(:priority, :desc)
      |> Query.order(:score, :desc)
      |> Query.order(:inserted_at, :desc)
      |> Query.order(:id, :asc)
      |> Query.paginate(:cursor, cursor_fields: [{:priority, :desc}, {:score, :desc}, {:inserted_at, :desc}, {:id, :asc}], limit: 50)
      |> Query.select([:id, :name, :status, :priority, :score, :active])
      |> Query.limit(100)
      |> Query.distinct(true)
      |> Query.group_by(:status)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("\n=== Query Execution Benchmarks ===\n")

Benchee.run(
  %{
    "execute_100_records" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:priority, :eq, 0)
      |> Query.limit(100)
      |> Query.execute!()
    end,
    "execute_500_records" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:active, :eq, true)
      |> Query.limit(500)
      |> Query.execute!()
    end,
    "execute_1000_records" => fn ->
      Query.new(BenchRecord)
      |> Query.limit(1000)
      |> Query.execute!()
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("\n=== Cursor Pagination Benchmarks ===\n")

cursor_fields = [{:inserted_at, :asc}, {:id, :asc}]

Benchee.run(
  %{
    "cursor_first_page" => fn ->
      Query.new(BenchRecord)
      |> Query.order(:inserted_at, :asc)
      |> Query.order(:id, :asc)
      |> Query.paginate(:cursor, cursor_fields: cursor_fields, limit: 20)
      |> Query.execute!()
    end,
    "cursor_with_after" => fn ->
      # First get a cursor
      result =
        Query.new(BenchRecord)
        |> Query.order(:inserted_at, :asc)
        |> Query.order(:id, :asc)
        |> Query.paginate(:cursor, cursor_fields: cursor_fields, limit: 20)
        |> Query.execute!()

      # Then use it
      Query.new(BenchRecord)
      |> Query.order(:inserted_at, :asc)
      |> Query.order(:id, :asc)
      |> Query.paginate(:cursor, cursor_fields: cursor_fields, limit: 20, after: result.pagination.end_cursor)
      |> Query.execute!()
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("\n=== Batch Execution Benchmarks ===\n")

Benchee.run(
  %{
    "batch_3_queries" => fn ->
      tokens = [
        Query.new(BenchRecord) |> Query.filter(:priority, :eq, 0) |> Query.limit(100),
        Query.new(BenchRecord) |> Query.filter(:priority, :eq, 1) |> Query.limit(100),
        Query.new(BenchRecord) |> Query.filter(:priority, :eq, 2) |> Query.limit(100)
      ]

      Query.batch(tokens)
    end,
    "batch_5_queries" => fn ->
      tokens =
        0..4
        |> Enum.map(fn i ->
          Query.new(BenchRecord)
          |> Query.filter(:priority, :eq, i)
          |> Query.limit(100)
        end)

      Query.batch(tokens)
    end,
    "batch_10_queries" => fn ->
      tokens =
        0..9
        |> Enum.map(fn i ->
          Query.new(BenchRecord)
          |> Query.filter(:priority, :eq, rem(i, 5))
          |> Query.filter(:status, :eq, if(rem(i, 2) == 0, do: "active", else: "inactive"))
          |> Query.limit(100)
        end)

      Query.batch(tokens)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("\n=== Convenience Method Benchmarks ===\n")

Benchee.run(
  %{
    "count" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:status, :eq, "active")
      |> Query.count()
    end,
    "exists?" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:priority, :eq, 3)
      |> Query.exists?()
    end,
    "first" => fn ->
      Query.new(BenchRecord)
      |> Query.order(:inserted_at, :desc)
      |> Query.first()
    end,
    "aggregate_sum" => fn ->
      Query.new(BenchRecord)
      |> Query.filter(:status, :eq, "active")
      |> Query.aggregate(:sum, :priority)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)

IO.puts("\nBenchmarks complete!")
IO.puts("Note: Records are preserved for future benchmark runs.")
IO.puts("To clean up, uncomment and run: BenchSetup.cleanup()")
