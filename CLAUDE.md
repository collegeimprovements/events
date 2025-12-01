# Claude Code Instructions for Events Project

## Required Reading

**IMPORTANT:** Before working on this codebase, you MUST follow these guidelines:

1. **`docs/development/AGENTS.md`** - Project conventions, code style, and patterns (READ FIRST)
2. **`docs/EVENTS_REFERENCE.md`** - Schema, Migration, and Decorator macro reference

The AGENTS.md file contains critical guidelines including:
- Pattern matching over conditionals (no `if...else`)
- Result tuples (`{:ok, result} | {:error, reason}`) for all fallible functions
- Token pattern for pipelines
- Soft delete conventions
- Phoenix/LiveView best practices
- Type decorators usage
- **Functional data structures** (Result, Maybe, Pipeline, AsyncResult, Guards)

---

## Schema and Migration Guidelines

**IMPORTANT:** This project has custom Schema and Migration macro systems that extend Ecto. Always use these instead of raw Ecto when available.

### Reference Documentation

Before creating or modifying schemas, migrations, or adding decorators, review:
- `docs/EVENTS_REFERENCE.md` - Complete reference with examples for Schema, Migration, and Decorator systems

### Schema Rules

1. **Always use `Events.Schema` instead of `Ecto.Schema`:**
   ```elixir
   # CORRECT
   use Events.Schema

   # WRONG - Don't use raw Ecto.Schema
   use Ecto.Schema
   ```

2. **Use field group macros for standard fields:**
   ```elixir
   schema "users" do
     # Custom fields first
     field :name, :string, required: true

     # Then field groups
     type_fields()
     status_fields(values: [:active, :inactive], default: :active)
     audit_fields()
     timestamps()
   end
   ```

3. **Use presets for common field patterns:**
   ```elixir
   import Events.Schema.Presets

   field :email, :string, email()
   field :username, :string, username()
   field :password, :string, password()
   ```

4. **Use validation options directly on fields:**
   ```elixir
   field :age, :integer, required: true, positive: true, max: 150
   field :email, :string, required: true, format: :email, mappers: [:trim, :downcase]
   ```

5. **Use `base_changeset/3` instead of manual cast/validate_required:**
   ```elixir
   def changeset(user, attrs) do
     user
     |> base_changeset(attrs)
     |> unique_constraints([{:email, []}])
   end
   ```

### Migration Rules

1. **Always use `Events.Migration` instead of `Ecto.Migration`:**
   ```elixir
   # CORRECT
   use Events.Migration

   # WRONG - Don't use raw Ecto.Migration
   use Ecto.Migration
   ```

2. **Use the pipeline pattern for table creation:**
   ```elixir
   def change do
     create_table(:users)
     |> with_uuid_primary_key()
     |> with_identity(:name, :email)
     |> with_audit()
     |> with_soft_delete()
     |> with_timestamps()
     |> execute()
   end
   ```

3. **Use DSL Enhanced macros inside create blocks:**
   ```elixir
   create table(:products, primary_key: false) do
     uuid_primary_key()
     type_fields()
     status_fields()
     metadata_field()
     timestamps(type: :utc_datetime_usec)
   end
   ```

4. **Use field builder helpers:**
   - `with_uuid_primary_key()` - UUIDv7 primary key
   - `with_type_fields()` - Type/subtype classification
   - `with_status_fields()` - Status tracking
   - `with_audit()` - Audit fields (created_by, updated_by)
   - `with_soft_delete()` - Soft delete support
   - `with_timestamps()` - inserted_at/updated_at
   - `with_metadata()` - JSONB metadata field

### When to Fall Back to Raw Ecto

Only use raw Ecto functions when:
1. The Events macros don't support a specific feature
2. You need very custom behavior not covered by the system
3. You're working with legacy code that hasn't been migrated

Even then, prefer extending the Events system over bypassing it.

### Quick Reference

**Schema Presets:** `email()`, `username()`, `password()`, `phone()`, `url()`, `slug()`, `money()`, `percentage()`, `age()`, `rating()`, `latitude()`, `longitude()`

**Field Groups:** `type_fields()`, `status_fields()`, `audit_fields()`, `timestamps()`, `metadata_field()`, `soft_delete_field()`, `standard_fields()`

**Migration Pipelines:** `with_uuid_primary_key()`, `with_identity()`, `with_authentication()`, `with_profile()`, `with_type_fields()`, `with_status_fields()`, `with_metadata()`, `with_tags()`, `with_audit()`, `with_soft_delete()`, `with_timestamps()`

**Mappers:** `:trim`, `:downcase`, `:upcase`, `:capitalize`, `:titlecase`, `:squish`, `:slugify`, `:digits_only`, `:alphanumeric_only`

---

## Functional Programming Modules

This project provides comprehensive functional programming utilities. **Always use these modules** for error handling, optional values, and multi-step workflows.

### Reference Documentation

See `docs/functional/OVERVIEW.md` for complete documentation with real-world examples.

### Core Modules

| Module | Purpose | Returns |
|--------|---------|---------|
| `Events.Result` | Error handling for fallible operations | `{:ok, value} \| {:error, reason}` |
| `Events.Maybe` | Optional values (nil-safe) | `{:some, value} \| :none` |
| `Events.Pipeline` | Multi-step workflows with context | `{:ok, context} \| {:error, reason}` |
| `Events.AsyncResult` | Concurrent operations | `{:ok, value} \| {:error, reason}` |
| `Events.Guards` | Pattern matching guards and macros | Guards + macros |

### When to Use Each Module

**Use `Result`** for:
- Database operations
- API calls
- Any function that can fail
- Chaining fallible operations

```elixir
alias Events.Result

{:ok, user}
|> Result.and_then(&validate_user/1)
|> Result.and_then(&save_user/1)
|> Result.map(&send_welcome_email/1)
```

**Use `Maybe`** for:
- Optional configuration values
- Nullable database fields
- Safe nested access
- Default value handling

```elixir
alias Events.Maybe

user.middle_name
|> Maybe.from_nilable()
|> Maybe.map(&String.upcase/1)
|> Maybe.unwrap_or("")
```

**Use `Pipeline`** for:
- User registration flows
- Order processing
- Data import/export
- Any multi-step business process

```elixir
alias Events.Pipeline

Pipeline.new(%{params: params})
|> Pipeline.step(:validate, &validate/1)
|> Pipeline.step(:create_user, &create_user/1)
|> Pipeline.step(:send_email, &send_welcome/1)
|> Pipeline.run()
```

**Use `AsyncResult`** for:
- Parallel API calls
- Concurrent database queries
- Race conditions (first-wins)
- Retry with backoff

```elixir
alias Events.AsyncResult

AsyncResult.all([
  fn -> fetch_user(id) end,
  fn -> fetch_orders(id) end
])
```

**Use `Guards`** for:
- Pattern matching in function heads
- Cleaner case statements
- Type-safe guard clauses

```elixir
import Events.Guards

def handle(result) when is_ok(result), do: :success
def handle(result) when is_error(result), do: :failure

case result do
  ok(value) -> process(value)
  error(reason) -> handle_error(reason)
end
```

### Quick Reference

**Result functions:** `ok/1`, `error/1`, `map/2`, `and_then/2`, `or_else/2`, `unwrap!/1`, `unwrap_or/2`, `collect/1`, `traverse/2`, `try_with/1`, `wrap_error/2`

**Maybe functions:** `some/1`, `none/0`, `from_nilable/1`, `map/2`, `and_then/2`, `unwrap_or/2`, `unwrap_or_else/2`, `filter/2`, `collect/1`

**Pipeline functions:** `new/1`, `step/3`, `step/4`, `branch/4`, `parallel/3`, `checkpoint/2`, `ensure/3`, `run/1`, `run_with_ensure/1`

**AsyncResult functions:** `async/1`, `await/2`, `all/2`, `any/2`, `race/2`, `retry/2`, `map/2`, `and_then/2`

**Guards:** `is_ok/1`, `is_error/1`, `is_result/1`, `is_some/1`, `is_none/1`, `is_maybe/1`, `is_non_empty_string/1`, `is_non_empty_list/1`, `is_positive_integer/1`

**Pattern macros:** `ok/1`, `error/1`, `some/1`, `none/0`

### Pipeline + AsyncResult Composition

`Pipeline` and `AsyncResult` are designed to compose seamlessly. Pipeline handles multi-step workflows with context, while AsyncResult handles concurrent task execution. Use AsyncResult **inside** Pipeline steps for async operations.

#### Feature Matrix

| Feature | AsyncResult | Pipeline | How to Compose |
|---------|-------------|----------|----------------|
| Parallel execution | `parallel/2`, `parallel_map/2` | `parallel/3` | Pipeline wraps AsyncResult internally |
| Race (first wins) | `race/2`, `race_with_fallback/3` | — | Use inside step function |
| Retry with backoff | `retry/2` | `step_with_retry/4` | Both available, use appropriate one |
| Timeout | `with_timeout/2` | `run_with_timeout/2` | Both available at different levels |
| Batch processing | `batch/2` | — | Use inside step function |
| Progress tracking | `parallel_with_progress/3` | — | Use inside step function |
| Sequential fallback | `first_ok/1` | — | Use inside step function |
| Settlement (all results) | `parallel_settle/2` | — | Use inside step function |
| Context accumulation | — | `step/3`, `assign/3` | Pipeline-only feature |
| Branching | — | `branch/4` | Pipeline-only feature |
| Rollback | — | `run_with_rollback/1` | Pipeline-only feature |
| Checkpoints | — | `checkpoint/2` | Pipeline-only feature |

#### Composition Examples

**Race multiple sources inside a Pipeline step:**

```elixir
Pipeline.new(%{id: 123})
|> Pipeline.step(:fetch_data, fn ctx ->
  # Race cache vs database - first success wins
  AsyncResult.race([
    fn -> Cache.get(ctx.id) end,
    fn -> DB.get(ctx.id) end
  ])
  |> Result.map(&%{data: &1})
end)
|> Pipeline.run()
```

**Parallel enrichment inside a Pipeline step:**

```elixir
Pipeline.new(%{user: user})
|> Pipeline.step(:enrich, fn ctx ->
  AsyncResult.parallel([
    fn -> fetch_preferences(ctx.user.id) end,
    fn -> fetch_notifications(ctx.user.id) end,
    fn -> fetch_activity(ctx.user.id) end
  ])
  |> Result.map(fn [prefs, notifs, activity] ->
    %{preferences: prefs, notifications: notifs, activity: activity}
  end)
end)
|> Pipeline.run()
```

**Retry with backoff for flaky operations:**

```elixir
Pipeline.new(%{url: url})
|> Pipeline.step(:fetch_external, fn ctx ->
  AsyncResult.retry(
    fn -> HttpClient.get(ctx.url) end,
    max_attempts: 3,
    initial_delay: 100,
    max_delay: 2000
  )
  |> Result.map(&%{response: &1})
end)
|> Pipeline.run()
```

**Batch processing with rate limiting:**

```elixir
Pipeline.new(%{items: items})
|> Pipeline.step(:process_batches, fn ctx ->
  AsyncResult.batch(
    Enum.map(ctx.items, fn item -> fn -> process_item(item) end end),
    batch_size: 10,
    delay_between_batches: 1000  # Rate limit: 10 items/second
  )
  |> Result.map(&%{results: &1})
end)
|> Pipeline.run()
```

#### When to Use Which

| Scenario | Use |
|----------|-----|
| Multi-step business workflow | `Pipeline` |
| Simple parallel fetching | `AsyncResult.parallel/2` |
| Parallel steps in a workflow | `Pipeline.parallel/3` |
| Race multiple alternatives | `AsyncResult.race/2` inside Pipeline step |
| Retry flaky operation | `AsyncResult.retry/2` or `Pipeline.step_with_retry/4` |
| Batch API with rate limiting | `AsyncResult.batch/2` inside Pipeline step |
| Need context between steps | `Pipeline` |
| Need rollback on failure | `Pipeline.run_with_rollback/1` |
| Just running concurrent tasks | `AsyncResult` directly |

#### Real-World Composition Examples

**1. User Registration with Parallel Verification:**

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
      # Fire-and-forget parallel tasks after user creation
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

**2. Order Processing with Rollback:**

```elixir
defmodule MyApp.Orders do
  alias Events.{Pipeline, AsyncResult, Result}

  def process_order(order_params) do
    Pipeline.new(%{params: order_params})
    |> Pipeline.step(:validate_order, &validate_order/1)
    |> Pipeline.step(:check_inventory, fn ctx ->
      # Check all items in parallel
      AsyncResult.parallel_map(ctx.params.items, fn item ->
        check_item_availability(item.sku, item.quantity)
      end)
      |> Result.map(&%{inventory_checks: &1})
    end)
    |> Pipeline.step(:reserve_inventory, &reserve_inventory/1,
        rollback: &release_inventory/1)
    |> Pipeline.step(:charge_payment, fn ctx ->
      # Retry payment with exponential backoff
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
      # Parallel notifications (failures don't affect order)
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

**3. Data Import with Batching and Progress:**

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
      # Validate all rows in parallel, collect all errors
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
      # Import in batches with progress tracking
      AsyncResult.parallel_with_progress(
        Enum.map(ctx.validated_rows, fn row ->
          fn -> import_row(row) end
        end),
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

**4. Multi-Source Data Aggregation with Racing:**

```elixir
defmodule MyApp.Search do
  alias Events.{Pipeline, AsyncResult, Result}

  def search(query, opts \\ []) do
    Pipeline.new(%{query: query, opts: opts})
    |> Pipeline.step(:fetch_from_fastest_cache, fn ctx ->
      # Race multiple cache layers - first hit wins
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
          # Search multiple backends in parallel, merge results
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
        # Async cache population (don't wait)
        Task.start(fn -> populate_caches(ctx.query, ctx.results) end)
      end
      {:ok, %{}}
    end)
    |> Pipeline.run()
  end
end
```

**5. External API Integration with Fallbacks:**

```elixir
defmodule MyApp.ExternalAPIs do
  alias Events.{Pipeline, AsyncResult, Result}

  def get_user_profile(user_id) do
    Pipeline.new(%{user_id: user_id})
    |> Pipeline.step(:fetch_core_data, fn ctx ->
      # Primary source with retry
      AsyncResult.retry(
        fn -> CoreAPI.get_user(ctx.user_id) end,
        max_attempts: 3,
        initial_delay: 100
      )
      |> Result.map(&%{user: &1})
    end)
    |> Pipeline.step(:enrich_profile, fn ctx ->
      # Fetch enrichment data in parallel with fallbacks
      AsyncResult.parallel([
        # Social data with fallback to empty
        fn ->
          AsyncResult.race_with_fallback(
            [
              fn -> SocialAPI.get_connections(ctx.user_id) end,
              fn -> SocialCache.get_connections(ctx.user_id) end
            ],
            fn -> {:ok, []} end  # Fallback to empty list
          )
        end,
        # Activity with timeout fallback
        fn ->
          AsyncResult.with_timeout(
            fn -> ActivityAPI.get_recent(ctx.user_id) end,
            2000
          )
          |> Result.or_else(fn _ -> {:ok, []} end)
        end,
        # Preferences - try cache first, then API
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
      profile = %{
        user: ctx.user,
        social: ctx.social,
        activity: ctx.activity,
        preferences: ctx.preferences
      }
      {:ok, %{profile: profile}}
    end)
    |> Pipeline.run()
  end
end
```

**6. Webhook Delivery with Retry and Dead Letter:**

```elixir
defmodule MyApp.Webhooks do
  alias Events.{Pipeline, AsyncResult, Result}

  def deliver_webhooks(event, subscribers) do
    Pipeline.new(%{event: event, subscribers: subscribers})
    |> Pipeline.step(:prepare_payloads, fn ctx ->
      payloads = Enum.map(ctx.subscribers, fn sub ->
        %{
          subscriber: sub,
          payload: build_payload(ctx.event, sub),
          attempts: 0
        }
      end)
      {:ok, %{payloads: payloads}}
    end)
    |> Pipeline.step(:deliver_all, fn ctx ->
      # Deliver to all subscribers in parallel with individual retry
      results = AsyncResult.parallel_map_settle(
        ctx.payloads,
        fn delivery ->
          AsyncResult.retry(
            fn -> deliver_single(delivery) end,
            max_attempts: 3,
            initial_delay: 1000,
            max_delay: 10_000,
            multiplier: 2
          )
        end,
        max_concurrency: 20,
        timeout: 30_000
      )

      {:ok, %{
        delivered: results.ok,
        failed: results.errors
      }}
    end)
    |> Pipeline.step(:handle_failures, fn ctx ->
      # Send failed deliveries to dead letter queue
      case ctx.failed do
        [] ->
          {:ok, %{}}
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

**7. Report Generation with Checkpoints:**

```elixir
defmodule MyApp.Reports do
  alias Events.{Pipeline, AsyncResult, Result}

  def generate_monthly_report(year, month) do
    Pipeline.new(%{year: year, month: month})
    |> Pipeline.step(:fetch_raw_data, fn ctx ->
      # Fetch all data sources in parallel
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
      # Heavy calculations in parallel
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
      # Generate all charts in parallel
      AsyncResult.parallel_map(
        [:revenue_chart, :expense_chart, :trend_chart, :comparison_chart],
        fn chart_type -> generate_chart(chart_type, ctx.metrics) end,
        max_concurrency: 4
      )
      |> Result.map(&%{charts: &1})
    end)
    |> Pipeline.step(:compile_pdf, &compile_report_pdf/1)
    |> Pipeline.step(:distribute, fn ctx ->
      # Distribute to all stakeholders in parallel
      AsyncResult.parallel_settle([
        fn -> email_report(ctx.pdf, "executives@company.com") end,
        fn -> upload_to_sharepoint(ctx.pdf) end,
        fn -> notify_slack_channel(ctx.report_url) end,
        fn -> archive_report(ctx.pdf) end
      ])
      {:ok, %{distributed: true}}
    end)
    |> Pipeline.run()
  end
end
```

**8. Real-time Data Sync with Conflict Resolution:**

```elixir
defmodule MyApp.Sync do
  alias Events.{Pipeline, AsyncResult, Result}

  def sync_user_data(user_id) do
    Pipeline.new(%{user_id: user_id})
    |> Pipeline.step(:fetch_all_sources, fn ctx ->
      # Fetch from all data sources simultaneously
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
          # Resolve each conflict (could involve user input or auto-resolution)
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
      # Update all sources in parallel
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

**9. Health Check Aggregator:**

```elixir
defmodule MyApp.HealthCheck do
  alias Events.{Pipeline, AsyncResult, Result}

  def check_system_health do
    Pipeline.new(%{started_at: DateTime.utc_now()})
    |> Pipeline.step(:check_critical_services, fn _ctx ->
      # Critical services - all must pass
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
      # Optional services - collect status but don't fail
      settlement = AsyncResult.parallel_settle([
        fn -> check_search_engine() end,
        fn -> check_cdn() end,
        fn -> check_analytics() end,
        fn -> check_email_service() end
      ], timeout: 3000)

      {:ok, %{
        optional_healthy: length(settlement.errors) == 0,
        optional_status: settlement.results
      }}
    end)
    |> Pipeline.step(:check_external_apis, fn _ctx ->
      # Race to check if at least one external endpoint responds
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
      status = %{
        healthy: ctx.critical and ctx.external_reachable,
        critical_services: ctx.critical,
        optional_services: ctx.optional_healthy,
        external_apis: ctx.external_reachable,
        checked_at: DateTime.utc_now(),
        duration_ms: DateTime.diff(DateTime.utc_now(), ctx.started_at, :millisecond)
      }
      {:ok, %{status: status}}
    end)
    |> Pipeline.run()
  end
end
```

**10. ETL Pipeline with Parallel Transform:**

```elixir
defmodule MyApp.ETL do
  alias Events.{Pipeline, AsyncResult, Result}

  def run_etl(source_config, dest_config) do
    Pipeline.new(%{source: source_config, dest: dest_config})
    |> Pipeline.step(:extract, fn ctx ->
      # Extract from multiple tables in parallel
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
      # Transform each dataset in parallel
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
      # Load in batches with rate limiting
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
    |> Pipeline.ensure(:cleanup, fn ctx, result ->
      close_connections(ctx.source)
      close_connections(ctx.dest)
      log_etl_result(result)
    end)
    |> Pipeline.run_with_ensure()
  end
end
```

---

## Decorator System

This project has a comprehensive decorator system for cross-cutting concerns. **Always use decorators** for type contracts, caching, telemetry, validation, and security instead of implementing these patterns manually.

See `docs/EVENTS_REFERENCE.md` for complete decorator documentation with all options and examples.

### Getting Started

```elixir
defmodule MyApp.Users do
  use Events.Decorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:my_app, :users, :get])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
```

### Decorator Best Practices

1. **Always use type decorators** - Every fallible function should declare its return type contract
2. **Stack decorators** for comprehensive behavior:
   ```elixir
   @decorate returns_result(ok: User.t(), error: :atom)
   @decorate telemetry_span([:app, :users, :create])
   @decorate validate_schema(schema: UserSchema)
   def create_user(params), do: ...
   ```
3. **Use `normalize_result/1`** for external APIs that don't follow result tuple pattern
4. **Add telemetry spans** to all public API functions
5. **Use caching decorators** instead of manual caching logic
6. **Apply security decorators** to all protected endpoints

### Quick Decorator Reference

| Category | Decorators |
|----------|-----------|
| **Types** | `returns_result`, `returns_maybe`, `returns_bang`, `returns_struct`, `returns_list`, `returns_union`, `normalize_result` |
| **Caching** | `cacheable`, `cache_put`, `cache_evict` |
| **Telemetry** | `telemetry_span`, `otel_span`, `log_call`, `log_context`, `log_if_slow`, `log_query`, `capture_errors`, `measure`, `benchmark`, `track_memory` |
| **Validation** | `validate_schema`, `coerce_types`, `serialize`, `contract` |
| **Security** | `role_required`, `rate_limit`, `audit_log` |
| **Debugging** | `debug`, `inspect`, `pry` (dev only) |
| **Purity** | `pure`, `deterministic`, `idempotent`, `memoizable` |

---

## S3 API Guidelines

**IMPORTANT:** This project has a clean, unified S3 API at `Events.Services.S3`. Always use this module instead of raw ExAws or other S3 libraries.

### Module Location

- `Events.Services.S3` - Main API (use this)
- `Events.Services.S3.Config` - Configuration
- `Events.Services.S3.Client` - Low-level HTTP client (internal)
- `Events.Services.S3.Request` - Pipeline builder (internal)
- `Events.Services.S3.URI` - URI utilities

### Two API Styles

#### 1. Direct API (config as last argument)

```elixir
alias Events.Services.S3

config = S3.config(access_key_id: "...", secret_access_key: "...")

# Basic operations
:ok = S3.put("s3://bucket/file.txt", "content", config)
{:ok, data} = S3.get("s3://bucket/file.txt", config)
:ok = S3.delete("s3://bucket/file.txt", config)
true = S3.exists?("s3://bucket/file.txt", config)

# Presigned URLs
{:ok, url} = S3.presign("s3://bucket/file.pdf", config)
{:ok, url} = S3.presign_put("s3://bucket/upload.jpg", config, expires_in: {5, :minutes})
```

#### 2. Pipeline API (chainable, config first)

```elixir
alias Events.Services.S3

# Upload with metadata
S3.new(config)
|> S3.bucket("my-bucket")
|> S3.prefix("uploads/2024/")
|> S3.content_type("image/jpeg")
|> S3.metadata(%{user_id: "123"})
|> S3.put("photo.jpg", jpeg_data)

# From environment variables
S3.from_env()
|> S3.expires_in({5, :minutes})
|> S3.presign("s3://bucket/file.pdf")

# Batch operations with concurrency
S3.new(config)
|> S3.bucket("my-bucket")
|> S3.concurrency(10)
|> S3.put_all([{"a.txt", "content"}, {"b.txt", "content"}])
```

### S3 URIs

All operations accept `s3://bucket/key` URIs:

```elixir
"s3://my-bucket/path/to/file.txt"   # Full path
"s3://my-bucket/prefix/"             # For listing
"s3://my-bucket"                     # Bucket root
```

### Configuration

```elixir
# From environment (reads AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, etc.)
S3.from_env()

# Manual configuration
S3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)

# With proxy
S3.config(
  access_key_id: "...",
  secret_access_key: "...",
  proxy: {"proxy.example.com", 8080}
)

# LocalStack / MinIO
S3.config(
  access_key_id: "test",
  secret_access_key: "test",
  endpoint: "http://localhost:4566"
)
```

### Core Operations

| Function | Description |
|----------|-------------|
| `put/3-4` | Upload content |
| `get/2` | Download content |
| `delete/2` | Delete object |
| `exists?/2` | Check existence |
| `head/2` | Get metadata |
| `list/2-3` | List objects (paginated) |
| `list_all/3` | List all objects (handles pagination) |
| `copy/3` | Copy within S3 |
| `presign/2-3` | Generate presigned URL |
| `presign_get/2-3` | Presigned download URL |
| `presign_put/2-3` | Presigned upload URL |

### Batch Operations

All batch operations support glob patterns and parallel execution:

```elixir
# Upload multiple files
S3.put_all([{"a.txt", "..."}, {"b.txt", "..."}], config, to: "s3://bucket/")

# Download with globs
S3.get_all(["s3://bucket/*.pdf"], config)

# Delete with patterns
S3.delete_all(["s3://bucket/temp/*.tmp"], config)

# Copy with glob
S3.copy_all("s3://source/*.jpg", config, to: "s3://dest/")

# Presign multiple
S3.presign_all(["s3://bucket/*.pdf"], config, expires_in: {1, :hour})
```

### File Name Normalization

```elixir
S3.normalize_key("User's Photo (1).jpg")
#=> "users-photo-1.jpg"

S3.normalize_key("report.pdf", prefix: "docs", timestamp: true)
#=> "docs/report-20240115-143022.pdf"

S3.normalize_key("file.txt", uuid: true)
#=> "file-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt"
```

### Quick Reference

**Pipeline Setters:** `bucket/2`, `prefix/2`, `content_type/2`, `metadata/2`, `acl/2`, `storage_class/2`, `expires_in/2`, `method/2`, `concurrency/2`, `timeout/2`

**Environment Variables:**
- `AWS_ACCESS_KEY_ID` - Required
- `AWS_SECRET_ACCESS_KEY` - Required
- `AWS_REGION` / `AWS_DEFAULT_REGION` - Default: "us-east-1"
- `AWS_ENDPOINT_URL_S3` / `AWS_ENDPOINT` - Custom endpoint
- `HTTP_PROXY` / `HTTPS_PROXY` - Proxy configuration
- `S3_BUCKET` - Default bucket

---

## Consistency Enforcement

This project has automated tools to ensure pattern consistency across the codebase.

### Running Consistency Checks

```bash
# Run all consistency checks
mix consistency.check

# Run with verbose output (shows violations)
mix consistency.check --verbose

# Run specific checks only
mix consistency.check --only schema_usage,migration_usage

# Output as JSON
mix consistency.check --json
```

### Custom Credo Checks

The project includes custom Credo checks that enforce project patterns:

| Check | Description |
|-------|-------------|
| `UseEventsSchema` | Ensures all schemas use `Events.Schema` |
| `UseEventsMigration` | Ensures all migrations use `Events.Migration` |
| `NoBangRepoOperations` | Prevents `Repo.insert!/update!/delete!` in app code |
| `RequireResultTuples` | Ensures public functions return result tuples |
| `PreferPatternMatching` | Encourages `case`/`with` over `if`/`else` chains |
| `UseDecorator` | Recommends decorators for context/service modules |

Run Credo with:

```bash
mix credo
mix credo --strict
```

### File Templates

Templates are available in `.claude/templates/` for creating new modules:

| Template | Usage |
|----------|-------|
| `schema.ex.template` | New Ecto schemas using `Events.Schema` |
| `migration.ex.template` | New migrations using `Events.Migration` |
| `context.ex.template` | New context modules with decorators |
| `service.ex.template` | New service modules |
| `test.ex.template` | New test modules |

### Pre-commit Checklist

Before committing code, ensure:

1. **Schemas use `Events.Schema`** - Never raw `Ecto.Schema`
2. **Migrations use `Events.Migration`** - Never raw `Ecto.Migration`
3. **No bang Repo operations** - Use `Repo.insert`, not `Repo.insert!`
4. **Result tuples everywhere** - `{:ok, _} | {:error, _}` for fallible functions
5. **@spec annotations** - All public functions should have type specs
6. **Decorators on contexts** - Use `@decorate returns_result(...)` etc.
7. **Pattern matching** - Prefer `case`/`with` over `if`/`else`

### CI Integration

Add to your CI pipeline:

```yaml
- name: Run consistency checks
  run: |
    mix credo --strict
    mix consistency.check
    mix dialyzer
```

### Adding New Patterns

To add enforcement for a new pattern:

1. Create a new Credo check in `lib/events/credo/checks/`
2. Add it to `.credo.exs` in the `enabled` section
3. Update the `mix consistency.check` task if needed
4. Document the pattern in this file
