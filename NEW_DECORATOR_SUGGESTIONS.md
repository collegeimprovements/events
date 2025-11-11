# Additional Decorator Suggestions for Elixir

Based on patterns from Java (Spring/AOP), Python, Haskell, and OCaml ecosystems

## 1. **Security & Authorization Decorators**

### `@decorate role_required(roles: [:admin, :manager])`
**Inspiration**: Spring Security @PreAuthorize, Python Flask @login_required
```elixir
@decorate role_required(roles: [:admin, :manager])
def delete_user(current_user, user_id) do
  # Automatically checks current_user.role before execution
  Repo.delete(User, user_id)
end
```

### `@decorate rate_limit(max: 100, window: :minute)`
**Inspiration**: Python Flask-Limiter, Java @RateLimited
```elixir
@decorate rate_limit(max: 100, window: :minute, by: :ip)
def api_endpoint(conn, params) do
  # Automatically rate limits by IP address
end
```

### `@decorate audit_log(level: :critical, fields: [:user_id, :action])`
**Inspiration**: Java @Audited, compliance requirements
```elixir
@decorate audit_log(level: :critical, store: AuditLog)
def transfer_funds(from_account, to_account, amount) do
  # Creates immutable audit trail
end
```

## 2. **Data Transformation & Validation Decorators**

### `@decorate validate_schema(schema: UserSchema)`
**Inspiration**: Python Pydantic, OCaml PPX deriving
```elixir
@decorate validate_schema(schema: UserCreateSchema)
def create_user(params) do
  # Params automatically validated against schema
  User.create(params)
end
```

### `@decorate serialize(format: :json, only: [:id, :name])`
**Inspiration**: Python marshmallow, Java Jackson annotations
```elixir
@decorate serialize(format: :json, except: [:password, :token])
def get_user_profile(user_id) do
  Repo.get(User, user_id)
end
```

### `@decorate coerce_types(args: [id: :integer, active: :boolean])`
**Inspiration**: Python type hints with runtime checking
```elixir
@decorate coerce_types(args: [age: :integer, price: :float])
def process_input(age, price) do
  # String "25" becomes integer 25 automatically
end
```

## 3. **Lazy Evaluation & Memoization Decorators**

### `@decorate lazy()`
**Inspiration**: Haskell's lazy evaluation by default
```elixir
@decorate lazy()
def expensive_computation(data) do
  # Only computed when actually needed
  complex_calculation(data)
end
```

### `@decorate memoize_with_ttl(ttl: {1, :hour}, key_fn: &hash_args/1)`
**Inspiration**: Python functools.lru_cache with expiry
```elixir
@decorate memoize_with_ttl(ttl: {30, :minutes}, max_size: 1000)
def fetch_user_preferences(user_id) do
  # Cached with automatic expiry and size limits
end
```

### `@decorate cached_property()`
**Inspiration**: Python's @cached_property for expensive attributes
```elixir
defmodule Report do
  use Events.Decorator

  @decorate cached_property()
  def total_revenue(report) do
    # Computed once per struct instance
    calculate_revenue(report.data)
  end
end
```

## 4. **Concurrency & Parallelism Decorators**

### `@decorate async(timeout: 5000)`
**Inspiration**: Python async/await, Java CompletableFuture
```elixir
@decorate async(timeout: 5000, on_timeout: {:error, :timeout})
def fetch_external_data(url) do
  HTTPoison.get(url)
end
```

### `@decorate parallel_map(workers: 4)`
**Inspiration**: Haskell parallel strategies
```elixir
@decorate parallel_map(workers: System.schedulers_online())
def process_items(items) do
  Enum.map(items, &expensive_operation/1)
end
```

### `@decorate stm_transaction()`
**Inspiration**: Haskell STM (Software Transactional Memory)
```elixir
@decorate stm_transaction(retries: 3)
def transfer_atomically(from, to, amount) do
  # Ensures atomic execution with automatic retry on conflicts
end
```

## 5. **Contract & Property-Based Testing Decorators**

### `@decorate contract(pre: &valid_input?/1, post: &valid_output?/2)`
**Inspiration**: Eiffel Design by Contract, OCaml's contracts
```elixir
@decorate contract(
  pre: fn x -> x > 0 end,
  post: fn _input, output -> output >= 0 end,
  invariant: fn state -> state.balance >= 0 end
)
def square_root(x) do
  :math.sqrt(x)
end
```

### `@decorate property_test(generators: [integer(), string()])`
**Inspiration**: Haskell QuickCheck, Python Hypothesis
```elixir
@decorate property_test(
  generators: [non_empty_list(integer())],
  property: fn input, output -> length(output) == length(input) end
)
def sort_list(list) do
  Enum.sort(list)
end
```

## 6. **Reactive & Event-Driven Decorators**

### `@decorate publish_event(topic: :user_events)`
**Inspiration**: Spring @EventListener, event sourcing patterns
```elixir
@decorate publish_event(topic: :user_events, event: :user_created)
def create_user(attrs) do
  {:ok, user} = User.create(attrs)
  user  # Event automatically published
end
```

### `@decorate subscribe_to(events: [:order_placed, :order_cancelled])`
**Inspiration**: Event-driven architecture patterns
```elixir
@decorate subscribe_to(events: [:payment_completed], async: true)
def handle_payment_completed(event) do
  # Automatically subscribed and called when event occurs
end
```

## 7. **Database & Persistence Decorators**

### `@decorate transactional(isolation: :serializable)`
**Inspiration**: Java @Transactional, Spring Data
```elixir
@decorate transactional(isolation: :repeatable_read, retry: 3)
def complex_db_operation(data) do
  # All operations wrapped in transaction
  update_accounts(data)
  create_audit_log(data)
  send_notifications(data)
end
```

### `@decorate soft_delete()`
**Inspiration**: Common ORM pattern
```elixir
@decorate soft_delete(field: :deleted_at)
def delete_user(user_id) do
  # Sets deleted_at instead of hard delete
end
```

### `@decorate paginated(default_limit: 20, max_limit: 100)`
**Inspiration**: REST API patterns
```elixir
@decorate paginated(default_limit: 25, cursor_based: true)
def list_users(params) do
  User |> Repo.all()
end
```

## 8. **ML/AI-Specific Decorators**

### `@decorate feature_flag(flag: :new_algorithm)`
**Inspiration**: A/B testing, gradual rollouts
```elixir
@decorate feature_flag(flag: :ml_model_v2, percentage: 10)
def predict_outcome(data) do
  # Conditionally uses new model for 10% of calls
end
```

### `@decorate model_version(version: "1.2.3")`
**Inspiration**: ML model versioning
```elixir
@decorate model_version(version: "2.0.0", track_metrics: true)
def classify_image(image_data) do
  # Tracks which model version was used
end
```

## 9. **Development & Documentation Decorators**

### `@decorate deprecated(message: "Use new_function/2 instead")`
**Inspiration**: Java @Deprecated, Python warnings
```elixir
@decorate deprecated(
  message: "Use UserService.fetch/1 instead",
  remove_in: "2.0.0"
)
def get_user(id) do
  UserService.fetch(id)
end
```

### `@decorate example(input: [1, 2], output: 3)`
**Inspiration**: Python doctest, documentation
```elixir
@decorate example([
  {[2, 3], 5},
  {[0, 0], 0},
  {[-1, 1], 0}
])
def add(a, b) do
  a + b
end
```

### `@decorate api_doc(summary: "Creates user", tags: [:users])`
**Inspiration**: OpenAPI/Swagger annotations
```elixir
@decorate api_doc(
  summary: "Creates a new user",
  tags: [:users, :admin],
  responses: [
    {201, "User created"},
    {400, "Invalid input"}
  ]
)
def create_user_endpoint(conn, params) do
  # Auto-generates API documentation
end
```

## 10. **Resilience & Fault Tolerance Decorators**

### `@decorate circuit_breaker(threshold: 5, timeout: 30_000)`
**Inspiration**: Hystrix, resilience patterns
```elixir
@decorate circuit_breaker(
  failure_threshold: 5,
  reset_timeout: 30_000,
  fallback: &return_cached_data/1
)
def call_flaky_service(params) do
  ExternalAPI.call(params)
end
```

### `@decorate bulkhead(max_concurrent: 10)`
**Inspiration**: Bulkhead isolation pattern
```elixir
@decorate bulkhead(max_concurrent: 10, queue_size: 100)
def process_request(request) do
  # Limits concurrent executions
end
```

### `@decorate retry_with_backoff(max_attempts: 5)`
**Inspiration**: Exponential backoff patterns
```elixir
@decorate retry_with_backoff(
  max_attempts: 5,
  initial_delay: 100,
  max_delay: 10_000,
  jitter: true
)
def unreliable_operation(data) do
  # Retries with exponential backoff and jitter
end
```

## 11. **Type System & Compile-Time Decorators**

### `@decorate typecheck(args: [String.t(), integer()])`
**Inspiration**: Python mypy, OCaml's type system
```elixir
@decorate typecheck(
  args: [%User{}, non_neg_integer()],
  return: {:ok, %Order{}} | {:error, term()}
)
def create_order(user, quantity) do
  # Runtime type checking based on specs
end
```

### `@decorate partial_application(arity: 2)`
**Inspiration**: Haskell currying, partial application
```elixir
@decorate partial_application()
def multiply(x, y, z) do
  x * y * z
end
# Can now call: multiply(2).(3).(4) => 24
```

## 12. **Workflow & Saga Decorators**

### `@decorate saga_step(compensate: &rollback_payment/1)`
**Inspiration**: Saga pattern, distributed transactions
```elixir
@decorate saga_step(
  compensate: &refund_payment/1,
  timeout: 30_000
)
def charge_payment(order) do
  # Part of larger saga with automatic compensation
end
```

### `@decorate workflow_step(name: :validate, next: :process)`
**Inspiration**: State machines, workflow engines
```elixir
@decorate workflow_step(
  name: :validation,
  on_success: :processing,
  on_failure: :rejected
)
def validate_application(application) do
  # Part of larger workflow
end
```

## Implementation Priority Suggestions

### High Priority (Most Useful)
1. **role_required** - Security is critical
2. **validate_schema** - Data validation is common
3. **rate_limit** - API protection
4. **transactional** - Database integrity
5. **circuit_breaker** - Resilience
6. **deprecated** - Code maintenance

### Medium Priority (Nice to Have)
1. **async** - Performance optimization
2. **publish_event** - Event-driven patterns
3. **contract** - Quality assurance
4. **serialize** - API responses
5. **audit_log** - Compliance

### Low Priority (Specialized)
1. **stm_transaction** - Advanced concurrency
2. **saga_step** - Distributed systems
3. **model_version** - ML specific
4. **partial_application** - FP patterns