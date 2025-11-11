# Events Decorator System - Detailed Usage Examples

## Table of Contents
1. [Caching Examples](#caching-examples)
2. [Telemetry & Observability Examples](#telemetry--observability-examples)
3. [Debugging Examples](#debugging-examples)
4. [Purity Examples](#purity-examples)
5. [Pipeline & Composition Examples](#pipeline--composition-examples)
6. [Testing Examples](#testing-examples)
7. [Tracing Examples](#tracing-examples)
8. [Real-World Scenarios](#real-world-scenarios)

---

## Caching Examples

### Basic Caching with TTL
```elixir
defmodule UserService do
  use Events.Decorator

  # Simple caching with 5-minute TTL
  @decorate cacheable(cache: RedisCache, ttl: 300_000)
  def get_user(id) do
    Repo.get!(User, id)
  end

  # Custom key generation
  @decorate cacheable(
    cache: RedisCache,
    key: {:user, id, include_deleted?},
    ttl: 600_000
  )
  def find_user(id, include_deleted?) do
    query = if include_deleted?, do: User, else: User.active()
    Repo.get(query, id)
  end

  # Conditional caching - only cache successful results
  @decorate cacheable(
    cache: MemoryCache,
    match: fn result -> match?({:ok, _}, result) end
  )
  def fetch_external_user(external_id) do
    ExternalAPI.get_user(external_id)
  end
end
```

### Cache Invalidation Patterns
```elixir
defmodule ProductService do
  use Events.Decorator

  # Evict before deletion
  @decorate cache_evict(
    cache: ProductCache,
    keys: [{:product, id}],
    before_invocation: true
  )
  def delete_product(id) do
    Repo.delete(Repo.get!(Product, id))
  end

  # Update cache after successful update
  @decorate cache_put(
    cache: ProductCache,
    keys: [{:product, product.id}],
    match: fn result -> match?({:ok, _}, result) end
  )
  def update_product(product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  # Clear entire cache category
  @decorate cache_evict(
    cache: ProductCache,
    all_entries: true
  )
  def reindex_all_products do
    # Bulk reindexing operation
  end
end
```

---

## Telemetry & Observability Examples

### Comprehensive Monitoring Setup
```elixir
defmodule PaymentProcessor do
  use Events.Decorator

  # Full observability stack
  @decorate compose([
    {:telemetry_span, [[:payments, :process]]},
    {:otel_span, ["payment.process", include: [:amount, :currency]]},
    {:log_call, [level: :info, metadata: %{service: "payments"}]},
    {:log_if_slow, [threshold: 3000, level: :warn]},
    {:capture_errors, [reporter: Sentry]}
  ])
  def process_payment(user_id, amount, currency, payment_method) do
    with {:ok, user} <- get_user(user_id),
         {:ok, validated} <- validate_payment(amount, currency),
         {:ok, result} <- charge_payment_method(payment_method, validated) do
      {:ok, result}
    end
  end

  # Context propagation for distributed tracing
  @decorate log_context([:transaction_id, :user_id])
  def handle_payment_webhook(transaction_id, user_id, payload) do
    Logger.info("Processing webhook")  # Includes transaction_id and user_id
    process_webhook_payload(payload)
  end
end
```

### Performance Monitoring
```elixir
defmodule ReportGenerator do
  use Events.Decorator

  # Benchmark with statistical analysis
  @decorate benchmark(
    iterations: 100,
    warmup: 10,
    format: :statistical,
    memory: true
  )
  def generate_simple_report(data) do
    # Will output:
    # Average: 15.3ms, Min: 12.1ms, Max: 23.5ms
    # Std Dev: 2.3ms, Memory: 5.2MB
  end

  # Simple measurement
  @decorate measure(unit: :microsecond, label: "CSV Export")
  def export_to_csv(records) do
    # Will output: "[CSV Export] Execution time: 1523μs"
  end

  # Memory tracking
  @decorate track_memory(threshold: 50_000_000)  # 50MB
  def memory_intensive_aggregation(large_dataset) do
    # Warns if memory usage exceeds 50MB
  end
end
```

### Database Query Monitoring
```elixir
defmodule Analytics do
  use Events.Decorator

  @decorate log_query(
    slow_threshold: 1000,
    level: :debug,
    slow_level: :error,
    include_query: true
  )
  def complex_aggregation(start_date, end_date) do
    from(e in Event,
      where: e.occurred_at >= ^start_date,
      where: e.occurred_at <= ^end_date,
      group_by: [e.type, fragment("date_trunc('day', ?)", e.occurred_at)],
      select: %{
        type: e.type,
        date: fragment("date_trunc('day', ?)", e.occurred_at),
        count: count(e.id)
      }
    )
    |> Repo.all()
  end
end
```

---

## Debugging Examples

### Interactive Debugging
```elixir
defmodule ComplexCalculator do
  use Events.Decorator

  # Debug with IEx.Helpers.dbg/2 - shows execution trace
  @decorate debug(label: "Tax Calculation")
  def calculate_tax(income, deductions) do
    income
    |> subtract_deductions(deductions)
    |> apply_tax_brackets()
    |> calculate_effective_rate()
  end

  # Conditional breakpoint
  @decorate pry(
    condition: fn result -> result < 0 end,
    after: true
  )
  def risky_calculation(a, b, c) do
    result = (a * b) - c
    # Breaks into IEx.pry if result is negative
    result
  end

  # Inspect specific parts
  @decorate inspect(
    what: :args,
    opts: [pretty: true, width: 120, limit: :infinity]
  )
  def process_complex_structure(nested_map, options) do
    # Shows formatted input before processing
    deep_transformation(nested_map, options)
  end
end
```

### Step-by-Step Debugging
```elixir
defmodule DataPipeline do
  use Events.Decorator

  # Inspect at each stage
  @decorate inspect(what: :all, label: "Pipeline Stage")
  def transform_data(raw_data) do
    raw_data
    |> parse_json()      # Inspected
    |> validate_schema() # Inspected
    |> enrich_data()     # Inspected
    |> store_results()   # Inspected
  end

  # Trace variable values (compile-time warning)
  @decorate trace_vars(vars: [:total, :average, :median])
  def calculate_statistics(numbers) do
    total = Enum.sum(numbers)
    average = total / length(numbers)
    median = calculate_median(numbers)
    %{total: total, average: average, median: median}
  end
end
```

---

## Purity Examples

### Pure Function Verification
```elixir
defmodule MathUtils do
  use Events.Decorator

  # Pure function with verification
  @decorate pure(verify: true, strict: true, samples: 5)
  def fibonacci(n) when n < 2, do: n
  def fibonacci(n) do
    fibonacci(n - 1) + fibonacci(n - 2)
  end

  # Allow IO for logging but verify purity otherwise
  @decorate pure(verify: true, allow_io: true)
  def calculate_with_logging(x, y) do
    Logger.debug("Calculating #{x} + #{y}")
    x + y  # Still pure despite logging
  end
end
```

### Determinism and Idempotency
```elixir
defmodule DataProcessor do
  use Events.Decorator

  # Verify deterministic output
  @decorate deterministic(samples: 10, on_failure: :raise)
  def hash_data(input) do
    :crypto.hash(:sha256, input)
    |> Base.encode64()
  end

  # Verify idempotent operations
  @decorate idempotent(calls: 3, compare: :deep_equality)
  def normalize_user_data(user_map) do
    user_map
    |> Map.update(:email, nil, &String.downcase/1)
    |> Map.update(:name, nil, &String.trim/1)
    |> Map.put(:normalized_at, DateTime.utc_now())
  end

  # Check if safe to memoize
  @decorate memoizable(verify: true, warn_impure: true)
  def expensive_pure_calculation(matrix) do
    # Complex matrix operations
    MatrixLib.determinant(matrix)
  end
end
```

---

## Pipeline & Composition Examples

### Data Transformation Pipelines
```elixir
defmodule ETLPipeline do
  use Events.Decorator

  # Simple transformation chain
  @decorate pipe_through([
    &String.trim/1,
    &String.downcase/1,
    &Slugy.slugify/1
  ])
  def create_slug(title) do
    title
  end

  # Complex pipeline with MFA tuples
  @decorate pipe_through([
    &validate_json/1,
    {JsonParser, :parse, [:strict]},
    {DataTransformer, :transform, [:v2]},
    &persist_to_database/1
  ])
  def process_webhook(raw_payload) do
    raw_payload
  end
end
```

### Aspect-Oriented Programming
```elixir
defmodule SecureService do
  use Events.Decorator

  # Authorization wrapper
  @decorate around(&AuthWrapper.ensure_authorized/3)
  def delete_sensitive_data(user, resource_id) do
    # AuthWrapper checks permissions before calling this
    perform_deletion(resource_id)
  end

  # Retry wrapper with exponential backoff
  @decorate around(&RetryWrapper.with_backoff/2)
  def call_flaky_service(params) do
    ExternalService.unreliable_endpoint(params)
  end

  # Transaction wrapper
  @decorate around(&DBWrapper.in_transaction/2)
  def complex_multi_table_update(data) do
    # All operations wrapped in a database transaction
    update_users(data.users)
    update_organizations(data.orgs)
    update_permissions(data.perms)
  end
end
```

### Decorator Composition
```elixir
defmodule UserAPI do
  use Events.Decorator

  # Define reusable decorator combinations
  @monitoring_stack [
    {:telemetry_span, [[:api, :request]]},
    {:log_call, [level: :info]},
    {:measure, [unit: :millisecond]}
  ]

  @caching_stack [
    {:cacheable, [cache: ApiCache, ttl: 60_000]},
    {:cache_evict, [cache: ApiCache, keys: [:stale], before_invocation: true]}
  ]

  @resilience_stack [
    {:around, [&CircuitBreaker.wrap/2]},
    {:capture_errors, [reporter: Sentry]},
    {:log_if_slow, [threshold: 2000]}
  ]

  # Apply multiple stacks
  @decorate compose(@monitoring_stack ++ @caching_stack ++ @resilience_stack)
  def get_user_profile(user_id) do
    fetch_complete_profile(user_id)
  end
end
```

---

## Testing Examples

### Test Setup and Fixtures
```elixir
defmodule UserAuthorizationTest do
  use ExUnit.Case
  use Events.Decorator

  @decorate with_fixtures(fixtures: [:admin_user, :regular_user, :organization])
  def test_admin_permissions(admin_user, regular_user, organization) do
    assert can_edit?(admin_user, organization)
    refute can_edit?(regular_user, organization)
  end

  @decorate compose([
    {:with_fixtures, [fixtures: [:database_connection]]},
    {:timeout_test, [timeout: 5000, on_timeout: :return_error]}
  ])
  def test_database_operations(database_connection) do
    # Test with automatic cleanup and timeout
    result = perform_complex_query(database_connection)
    assert {:ok, _} = result
  end
end
```

### Property-Based Testing
```elixir
defmodule ValidationTest do
  use ExUnit.Case
  use Events.Decorator

  @decorate sample_data(
    generator: &Faker.Internet.email/0,
    count: 100
  )
  def test_email_validation(emails) do
    Enum.each(emails, fn email ->
      assert {:ok, _} = EmailValidator.validate(email)
    end)
  end

  @decorate sample_data(
    generator: StreamData,
    count: 1000
  )
  def test_sort_idempotency(random_lists) do
    Enum.each(random_lists, fn list ->
      once = Enum.sort(list)
      twice = Enum.sort(Enum.sort(list))
      assert once == twice
    end)
  end
end
```

---

## Tracing Examples

### Execution Flow Analysis
```elixir
defmodule OrderProcessor do
  use Events.Decorator

  # Trace all calls up to depth 3
  @decorate trace_calls(
    depth: 3,
    filter: ~r/^Elixir\.MyApp\./,
    exclude: [Logger, Ecto.Repo],
    format: :tree
  )
  def process_order(order) do
    # Output:
    # [TRACE] OrderProcessor.process_order/1
    #   ↳ OrderValidator.validate/1
    #     ↳ OrderValidator.check_inventory/1
    #       ↳ Inventory.get_stock/1
    #   ↳ PaymentProcessor.charge/2
    #     ↳ PaymentGateway.process/2
  end

  # Module dependency analysis
  @decorate trace_modules(
    filter: ~r/^Elixir\.MyApp\./,
    unique: true,
    exclude_stdlib: true
  )
  def analyze_dependencies(data) do
    # Output:
    # [MODULES] OrderProcessor.analyze_dependencies/1 called:
    #   - MyApp.Orders
    #   - MyApp.Inventory
    #   - MyApp.Shipping
  end

  # External dependency tracking
  @decorate trace_dependencies(
    type: :external,
    format: :tree
  )
  def integration_point(params) do
    # Shows all external library calls
  end
end
```

---

## Real-World Scenarios

### 1. E-Commerce Checkout Flow
```elixir
defmodule CheckoutService do
  use Events.Decorator

  @decorate compose([
    # Monitoring
    {:otel_span, ["checkout.process", include: [:order_id, :user_id]]},
    {:log_context, [[:order_id, :user_id]]},

    # Performance
    {:log_if_slow, [threshold: 5000]},
    {:measure, [label: "Checkout Complete"]},

    # Resilience
    {:around, [&TransactionWrapper.wrap/2]},
    {:capture_errors, [reporter: Sentry]},

    # Debugging (dev only)
    if Mix.env() == :dev do
      [{:trace_calls, [depth: 2]}]
    else
      []
    end
  ])
  def process_checkout(order_id, user_id, payment_info) do
    with {:ok, order} <- validate_order(order_id),
         {:ok, inventory} <- reserve_inventory(order),
         {:ok, payment} <- process_payment(payment_info),
         {:ok, confirmation} <- send_confirmation(user_id, order) do
      {:ok, %{order: order, payment: payment, confirmation: confirmation}}
    else
      {:error, :inventory} = error ->
        rollback_reservation(order_id)
        error
      error ->
        error
    end
  end
end
```

### 2. Background Job Processing
```elixir
defmodule EmailWorker do
  use Events.Decorator
  use Oban.Worker

  @decorate compose([
    # Observability
    {:telemetry_span, [[:jobs, :email, :send]]},
    {:log_call, [level: :info, metadata: %{job_type: "email"}]},

    # Error handling
    {:capture_errors, [reporter: Sentry, threshold: 3]},

    # Performance tracking
    {:track_memory, [threshold: 100_000_000]},  # 100MB
    {:timeout_test, [timeout: 30_000]},  # 30 seconds

    # Remote logging
    {:log_remote, [service: CloudwatchLogger, async: true]}
  ])
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    email_id
    |> fetch_email_data()
    |> render_template()
    |> send_via_provider()
    |> record_delivery()
  end
end
```

### 3. GraphQL Resolver
```elixir
defmodule MyAppWeb.Schema.UserResolver do
  use Events.Decorator

  @decorate compose([
    # Caching layer
    {:cacheable, [cache: GraphQLCache, ttl: 60_000, key: {:user, id}]},

    # Monitoring
    {:telemetry_span, [[:graphql, :resolver, :user]]},
    {:measure, []},

    # Authorization
    {:around, [&AuthorizationWrapper.check_permissions/2]},

    # Query optimization
    {:log_query, [slow_threshold: 100]}
  ])
  def get_user(_parent, %{id: id}, %{context: context}) do
    with :ok <- authorize_user_access(context, id),
         {:ok, user} <- Repo.get(User, id) |> Repo.preload([:profile, :preferences]) do
      {:ok, user}
    end
  end
end
```

### 4. Data Migration Task
```elixir
defmodule DataMigration do
  use Events.Decorator

  @decorate compose([
    # Progress tracking
    {:log_call, [level: :info, message: "Starting migration"]},
    {:benchmark, [iterations: 1, format: :detailed, memory: true]},

    # Safety checks
    {:pure, [verify: false]},  # Document that this modifies state
    {:around, [&BackupWrapper.with_backup/2]},

    # Debugging
    {:trace_modules, []},
    {:inspect, [what: :result, label: "Migration Complete"]}
  ])
  def migrate_user_data(batch_size \\ 1000) do
    User
    |> Repo.stream(max_rows: batch_size)
    |> Stream.chunk_every(batch_size)
    |> Stream.map(&migrate_batch/1)
    |> Stream.run()
  end
end
```

### 5. Rate-Limited API Client
```elixir
defmodule ExternalAPIClient do
  use Events.Decorator

  @decorate compose([
    # Rate limiting
    {:around, [&RateLimiter.throttle/2]},

    # Retry logic
    {:around, [&RetryHelper.with_exponential_backoff/2]},

    # Circuit breaker
    {:around, [&CircuitBreaker.call/2]},

    # Monitoring
    {:otel_span, ["external.api.call"]},
    {:log_if_slow, [threshold: 2000]},
    {:capture_errors, [reporter: Sentry]},

    # Response caching
    {:cacheable, [cache: APICache, ttl: 300_000, match: &match?({:ok, _}, &1)]}
  ])
  def fetch_data(endpoint, params) do
    HTTPoison.get(
      "#{base_url()}/#{endpoint}",
      [],
      params: params,
      timeout: 5000,
      recv_timeout: 5000
    )
    |> handle_response()
  end
end
```