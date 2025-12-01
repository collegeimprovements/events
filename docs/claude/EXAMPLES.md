# Real-World Examples

> **Living examples of Pipeline + AsyncResult composition.**
> Copy and adapt these patterns for your use cases.

## 1. User Registration

```elixir
defmodule MyApp.Registration do
  alias Events.{Pipeline, AsyncResult, Result}

  def register_user(params) do
    Pipeline.new(%{params: params})
    |> Pipeline.step(:validate, &validate_params/1)
    |> Pipeline.step(:check_uniqueness, fn ctx ->
      # Check email AND username in parallel
      AsyncResult.parallel([
        fn -> check_email_available(ctx.params.email) end,
        fn -> check_username_available(ctx.params.username) end
      ])
      |> Result.and_then(fn [email_ok, username_ok] ->
        case {email_ok, username_ok} do
          {true, true} -> {:ok, %{}}
          {false, _} -> {:error, :email_taken}
          {_, false} -> {:error, :username_taken}
        end
      end)
    end)
    |> Pipeline.step(:create_user, &create_user/1)
    |> Pipeline.step(:post_registration, fn ctx ->
      # Fire-and-forget parallel tasks
      AsyncResult.parallel([
        fn -> send_welcome_email(ctx.user) end,
        fn -> create_default_settings(ctx.user) end,
        fn -> notify_admin(ctx.user) end,
        fn -> track_signup_analytics(ctx.user) end
      ])
      |> Result.map(fn _ -> %{} end)
    end)
    |> Pipeline.run()
  end
end
```

---

## 2. Order Processing with Rollback

```elixir
defmodule MyApp.Orders do
  alias Events.{Pipeline, AsyncResult, Result}

  def process_order(order_params) do
    Pipeline.new(%{params: order_params})
    |> Pipeline.step(:validate_order, &validate_order/1)
    |> Pipeline.step(:check_inventory, fn ctx ->
      AsyncResult.parallel_map(ctx.params.items, fn item ->
        check_item_availability(item.sku, item.quantity)
      end)
      |> Result.map(&%{inventory_checks: &1})
    end)
    |> Pipeline.step(:reserve_inventory, &reserve_inventory/1,
        rollback: &release_inventory/1)
    |> Pipeline.step(:charge_payment, fn ctx ->
      AsyncResult.retry(
        fn -> PaymentGateway.charge(ctx.payment_method, ctx.total) end,
        max_attempts: 3,
        initial_delay: 500,
        max_delay: 5000
      )
      |> Result.map(&%{payment: &1})
    end, rollback: &refund_payment/1)
    |> Pipeline.step(:fulfill_order, &create_fulfillment/1,
        rollback: &cancel_fulfillment/1)
    |> Pipeline.step(:notify, fn ctx ->
      # Failures don't affect order
      AsyncResult.parallel_settle([
        fn -> send_confirmation_email(ctx.order) end,
        fn -> send_sms_notification(ctx.order) end,
        fn -> update_crm(ctx.order) end
      ])
      {:ok, %{}}
    end)
    |> Pipeline.run_with_rollback()
  end
end
```

---

## 3. Data Import with Progress

```elixir
defmodule MyApp.Import do
  alias Events.{Pipeline, AsyncResult, Result}

  def import_csv(file_path, opts \\ []) do
    progress_callback = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)

    Pipeline.new(%{file_path: file_path})
    |> Pipeline.step(:read_file, fn ctx ->
      case File.read(ctx.file_path) do
        {:ok, content} -> {:ok, %{content: content}}
        {:error, reason} -> {:error, {:file_error, reason}}
      end
    end)
    |> Pipeline.step(:parse_csv, fn ctx ->
      rows = NimbleCSV.RFC4180.parse_string(ctx.content, skip_headers: true)
      {:ok, %{rows: rows, total: length(rows)}}
    end)
    |> Pipeline.step(:validate_rows, fn ctx ->
      settlement = AsyncResult.parallel_map_settle(
        ctx.rows,
        &validate_row/1,
        max_concurrency: 50
      )
      case settlement.errors do
        [] -> {:ok, %{validated_rows: settlement.ok}}
        errors -> {:error, {:validation_errors, errors}}
      end
    end)
    |> Pipeline.step(:import_batches, fn ctx ->
      AsyncResult.parallel_with_progress(
        Enum.map(ctx.validated_rows, fn row -> fn -> import_row(row) end end),
        progress_callback,
        max_concurrency: 10,
        timeout: 30_000
      )
      |> Result.map(&%{imported: &1})
    end)
    |> Pipeline.run()
  end
end
```

---

## 4. Search with Cache Racing

```elixir
defmodule MyApp.Search do
  alias Events.{Pipeline, AsyncResult, Result}

  def search(query, opts \\ []) do
    Pipeline.new(%{query: query, opts: opts})
    |> Pipeline.step(:fetch_from_fastest_cache, fn ctx ->
      AsyncResult.race([
        fn -> L1Cache.get(ctx.query) end,
        fn -> L2Cache.get(ctx.query) end,
        fn -> RedisCache.get(ctx.query) end
      ])
      |> case do
        {:ok, results} -> {:ok, %{results: results, source: :cache}}
        {:error, _} -> {:ok, %{cache_miss: true}}
      end
    end)
    |> Pipeline.step_if(:search_backends,
        fn ctx -> Map.get(ctx, :cache_miss, false) end,
        fn ctx ->
          AsyncResult.parallel([
            fn -> search_elasticsearch(ctx.query) end,
            fn -> search_postgresql(ctx.query) end,
            fn -> search_external_api(ctx.query) end
          ], timeout: 5000)
          |> Result.map(fn [es, pg, api] ->
            merged = merge_and_rank_results(es, pg, api)
            %{results: merged, source: :backends}
          end)
        end)
    |> Pipeline.step(:cache_results, fn ctx ->
      if ctx.source == :backends do
        Task.start(fn -> populate_caches(ctx.query, ctx.results) end)
      end
      {:ok, %{}}
    end)
    |> Pipeline.run()
  end
end
```

---

## 5. External API with Fallbacks

```elixir
defmodule MyApp.ExternalAPIs do
  alias Events.{Pipeline, AsyncResult, Result}

  def get_user_profile(user_id) do
    Pipeline.new(%{user_id: user_id})
    |> Pipeline.step(:fetch_core_data, fn ctx ->
      AsyncResult.retry(
        fn -> CoreAPI.get_user(ctx.user_id) end,
        max_attempts: 3,
        initial_delay: 100
      )
      |> Result.map(&%{user: &1})
    end)
    |> Pipeline.step(:enrich_profile, fn ctx ->
      AsyncResult.parallel([
        fn ->
          AsyncResult.race_with_fallback(
            [fn -> SocialAPI.get_connections(ctx.user_id) end],
            fn -> {:ok, []} end
          )
        end,
        fn ->
          AsyncResult.with_timeout(
            fn -> ActivityAPI.get_recent(ctx.user_id) end,
            2000
          )
          |> Result.or_else(fn _ -> {:ok, []} end)
        end,
        fn ->
          AsyncResult.first_ok([
            fn -> PrefsCache.get(ctx.user_id) end,
            fn -> PrefsAPI.get(ctx.user_id) end,
            fn -> {:ok, default_preferences()} end
          ])
        end
      ])
      |> Result.map(fn [social, activity, prefs] ->
        %{social: social, activity: activity, preferences: prefs}
      end)
    end)
    |> Pipeline.step(:build_response, fn ctx ->
      {:ok, %{profile: Map.take(ctx, [:user, :social, :activity, :preferences])}}
    end)
    |> Pipeline.run()
  end
end
```

---

## 6. Webhook Delivery with Dead Letter

```elixir
defmodule MyApp.Webhooks do
  alias Events.{Pipeline, AsyncResult, Result}

  def deliver_webhooks(event, subscribers) do
    Pipeline.new(%{event: event, subscribers: subscribers})
    |> Pipeline.step(:prepare_payloads, fn ctx ->
      payloads = Enum.map(ctx.subscribers, fn sub ->
        %{subscriber: sub, payload: build_payload(ctx.event, sub)}
      end)
      {:ok, %{payloads: payloads}}
    end)
    |> Pipeline.step(:deliver_all, fn ctx ->
      results = AsyncResult.parallel_map_settle(
        ctx.payloads,
        fn delivery ->
          AsyncResult.retry(
            fn -> deliver_single(delivery) end,
            max_attempts: 3,
            initial_delay: 1000,
            max_delay: 10_000
          )
        end,
        max_concurrency: 20,
        timeout: 30_000
      )
      {:ok, %{delivered: results.ok, failed: results.errors}}
    end)
    |> Pipeline.step(:handle_failures, fn ctx ->
      case ctx.failed do
        [] -> {:ok, %{}}
        failures ->
          AsyncResult.parallel_map(failures, fn failure ->
            DeadLetterQueue.enqueue(ctx.event, failure)
          end)
          |> Result.map(fn _ -> %{dead_lettered: length(failures)} end)
      end
    end)
    |> Pipeline.run()
  end
end
```

---

## 7. Report Generation with Checkpoints

```elixir
defmodule MyApp.Reports do
  alias Events.{Pipeline, AsyncResult, Result}

  def generate_monthly_report(year, month) do
    Pipeline.new(%{year: year, month: month})
    |> Pipeline.step(:fetch_raw_data, fn ctx ->
      AsyncResult.parallel([
        fn -> fetch_sales_data(ctx.year, ctx.month) end,
        fn -> fetch_expense_data(ctx.year, ctx.month) end,
        fn -> fetch_inventory_data(ctx.year, ctx.month) end,
        fn -> fetch_customer_data(ctx.year, ctx.month) end
      ], timeout: 60_000)
      |> Result.map(fn [sales, expenses, inventory, customers] ->
        %{sales: sales, expenses: expenses, inventory: inventory, customers: customers}
      end)
    end)
    |> Pipeline.checkpoint(:data_fetched)
    |> Pipeline.step(:calculate_metrics, fn ctx ->
      AsyncResult.parallel([
        fn -> calculate_revenue_metrics(ctx.sales) end,
        fn -> calculate_cost_metrics(ctx.expenses) end,
        fn -> calculate_inventory_metrics(ctx.inventory) end,
        fn -> calculate_customer_metrics(ctx.customers) end
      ])
      |> Result.map(fn [revenue, costs, inv, cust] ->
        %{metrics: %{revenue: revenue, costs: costs, inventory: inv, customers: cust}}
      end)
    end)
    |> Pipeline.checkpoint(:metrics_calculated)
    |> Pipeline.step(:generate_charts, fn ctx ->
      AsyncResult.parallel_map(
        [:revenue_chart, :expense_chart, :trend_chart, :comparison_chart],
        fn chart_type -> generate_chart(chart_type, ctx.metrics) end
      )
      |> Result.map(&%{charts: &1})
    end)
    |> Pipeline.step(:compile_pdf, &compile_report_pdf/1)
    |> Pipeline.step(:distribute, fn ctx ->
      AsyncResult.parallel_settle([
        fn -> email_report(ctx.pdf, "executives@company.com") end,
        fn -> upload_to_sharepoint(ctx.pdf) end,
        fn -> notify_slack_channel(ctx.report_url) end
      ])
      {:ok, %{distributed: true}}
    end)
    |> Pipeline.run()
  end
end
```

---

## 8. Data Sync with Branching

```elixir
defmodule MyApp.Sync do
  alias Events.{Pipeline, AsyncResult, Result}

  def sync_user_data(user_id) do
    Pipeline.new(%{user_id: user_id})
    |> Pipeline.step(:fetch_all_sources, fn ctx ->
      AsyncResult.parallel([
        fn -> fetch_local_db(ctx.user_id) end,
        fn -> fetch_cloud_storage(ctx.user_id) end,
        fn -> fetch_mobile_cache(ctx.user_id) end
      ], timeout: 10_000)
      |> Result.map(fn [local, cloud, mobile] ->
        %{sources: %{local: local, cloud: cloud, mobile: mobile}}
      end)
    end)
    |> Pipeline.step(:detect_conflicts, fn ctx ->
      conflicts = find_conflicts(ctx.sources)
      {:ok, %{conflicts: conflicts, has_conflicts: length(conflicts) > 0}}
    end)
    |> Pipeline.branch(:has_conflicts, %{
      true: fn pipeline ->
        pipeline
        |> Pipeline.step(:resolve_conflicts, fn ctx ->
          AsyncResult.parallel_map(ctx.conflicts, &resolve_conflict/1)
          |> Result.map(&%{resolutions: &1})
        end)
      end,
      false: fn pipeline ->
        Pipeline.assign(pipeline, :resolutions, [])
      end
    })
    |> Pipeline.step(:merge_data, &merge_all_sources/1)
    |> Pipeline.step(:propagate_changes, fn ctx ->
      AsyncResult.parallel([
        fn -> update_local_db(ctx.merged_data) end,
        fn -> update_cloud_storage(ctx.merged_data) end,
        fn -> invalidate_mobile_cache(ctx.user_id) end
      ])
      |> Result.map(fn _ -> %{synced: true} end)
    end)
    |> Pipeline.run()
  end
end
```

---

## 9. Health Check

```elixir
defmodule MyApp.HealthCheck do
  alias Events.{Pipeline, AsyncResult, Result}

  def check_system_health do
    Pipeline.new(%{started_at: DateTime.utc_now()})
    |> Pipeline.step(:check_critical_services, fn _ctx ->
      AsyncResult.parallel([
        fn -> check_database() end,
        fn -> check_redis() end,
        fn -> check_message_queue() end
      ], timeout: 5000)
      |> Result.map(fn results ->
        %{critical: Enum.all?(results, & &1.healthy)}
      end)
    end)
    |> Pipeline.guard(:critical_healthy,
        fn ctx -> ctx.critical end,
        {:error, :critical_services_down})
    |> Pipeline.step(:check_optional_services, fn _ctx ->
      settlement = AsyncResult.parallel_settle([
        fn -> check_search_engine() end,
        fn -> check_cdn() end,
        fn -> check_analytics() end
      ], timeout: 3000)
      {:ok, %{
        optional_healthy: length(settlement.errors) == 0,
        optional_status: settlement.results
      }}
    end)
    |> Pipeline.step(:check_external_apis, fn _ctx ->
      AsyncResult.race([
        fn -> ping_primary_api() end,
        fn -> ping_backup_api() end
      ], timeout: 2000)
      |> case do
        {:ok, _} -> {:ok, %{external_reachable: true}}
        {:error, _} -> {:ok, %{external_reachable: false}}
      end
    end)
    |> Pipeline.step(:compile_status, fn ctx ->
      {:ok, %{status: %{
        healthy: ctx.critical and ctx.external_reachable,
        critical_services: ctx.critical,
        optional_services: ctx.optional_healthy,
        external_apis: ctx.external_reachable,
        duration_ms: DateTime.diff(DateTime.utc_now(), ctx.started_at, :millisecond)
      }}}
    end)
    |> Pipeline.run()
  end
end
```

---

## 10. ETL Pipeline

```elixir
defmodule MyApp.ETL do
  alias Events.{Pipeline, AsyncResult, Result}

  def run_etl(source_config, dest_config) do
    Pipeline.new(%{source: source_config, dest: dest_config})
    |> Pipeline.step(:extract, fn ctx ->
      AsyncResult.parallel_map(
        ctx.source.tables,
        fn table -> extract_table(ctx.source, table) end,
        max_concurrency: 5,
        timeout: 300_000
      )
      |> Result.map(&%{extracted: &1})
    end)
    |> Pipeline.checkpoint(:extraction_complete)
    |> Pipeline.step(:transform, fn ctx ->
      AsyncResult.parallel_map(
        ctx.extracted,
        fn dataset ->
          dataset
          |> clean_nulls()
          |> normalize_dates()
          |> apply_business_rules()
          |> validate_schema()
        end,
        max_concurrency: System.schedulers_online()
      )
      |> Result.map(&%{transformed: &1})
    end)
    |> Pipeline.checkpoint(:transformation_complete)
    |> Pipeline.step(:load, fn ctx ->
      AsyncResult.batch(
        Enum.flat_map(ctx.transformed, fn dataset ->
          Enum.map(Enum.chunk_every(dataset.rows, 1000), fn batch ->
            fn -> load_batch(ctx.dest, dataset.table, batch) end
          end)
        end),
        batch_size: 10,
        delay_between_batches: 100
      )
      |> Result.map(&%{loaded: length(&1)})
    end)
    |> Pipeline.ensure(:cleanup, fn ctx, _result ->
      close_connections(ctx.source)
      close_connections(ctx.dest)
    end)
    |> Pipeline.run_with_ensure()
  end
end
```
