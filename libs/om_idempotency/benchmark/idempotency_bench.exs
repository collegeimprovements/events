# Run with: mix run benchmark/idempotency_bench.exs

alias OmIdempotency

# Ensure repo is started
{:ok, _} = Application.ensure_all_started(:om_idempotency)

# Pre-create a record for cache hit benchmarks
cached_key = "cached_benchmark_key"
OmIdempotency.execute(cached_key, fn -> {:ok, "cached_result"} end)

Benchee.run(
  %{
    "generate_key (random)" => fn ->
      OmIdempotency.generate_key()
    end,
    "generate_key (deterministic)" => fn ->
      OmIdempotency.generate_key(:create_user, user_id: 123, email: "test@example.com")
    end,
    "hash_key" => fn ->
      OmIdempotency.hash_key(:process_webhook, %{
        event_id: "evt_123",
        payload: %{data: "test", amount: 1000}
      })
    end,
    "create record" => fn ->
      key = "bench_create_#{:rand.uniform(1_000_000)}"
      OmIdempotency.create(key, scope: "bench")
    end,
    "get record (miss)" => fn ->
      key = "nonexistent_#{:rand.uniform(1_000_000)}"
      OmIdempotency.get(key, "bench")
    end,
    "get record (hit)" => fn ->
      OmIdempotency.get(cached_key)
    end,
    "execute (new)" => fn ->
      key = "exec_new_#{:rand.uniform(1_000_000)}"
      OmIdempotency.execute(key, fn -> {:ok, "result"} end, scope: "bench")
    end,
    "execute (cached)" => fn ->
      OmIdempotency.execute(cached_key, fn -> {:ok, "result"} end)
    end
  },
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console, extended_statistics: true},
    {Benchee.Formatters.HTML, file: "benchmark/results.html"}
  ]
)

IO.puts("\n✓ Benchmark results saved to benchmark/results.html")
