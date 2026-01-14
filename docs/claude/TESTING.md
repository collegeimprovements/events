# Testing Functional Code

> **Testing patterns for Result types, Pipeline, and other FnTypes modules.**

## Setup

Add to your test file or `test/test_helper.exs`:

```elixir
import FnTypes.Testing
```

Or in individual test modules:

```elixir
defmodule MyApp.AccountsTest do
  use ExUnit.Case
  import FnTypes.Testing
end
```

---

## Result Assertions

### Basic Assertions

```elixir
# Assert ok and get value
test "creates user successfully" do
  user = assert_ok(Accounts.create_user(%{email: "test@example.com"}))
  assert user.email == "test@example.com"
end

# Assert specific ok value
test "returns expected value" do
  assert_ok(42, Calculator.add(20, 22))
end

# Assert error and get reason
test "fails with invalid input" do
  reason = assert_error(Accounts.create_user(%{}))
  assert reason == :validation_failed
end

# Assert specific error
test "returns not_found" do
  assert_error(:not_found, Accounts.get_user("nonexistent"))
end
```

### Pattern Matching Assertions

```elixir
# Assert ok matches pattern
test "returns user struct" do
  assert_ok_match(%User{email: "test@example.com"}, create_user())
end

# Assert error matches pattern
test "returns changeset error" do
  assert_error_match(%Ecto.Changeset{valid?: false}, create_user(%{}))
end

# Assert error type
test "returns validation error" do
  result = Accounts.create_user(%{})
  assert_error_type(:validation, result)
end
```

### Collection Assertions

```elixir
# Assert all results are ok
test "creates multiple users" do
  results = [
    Accounts.create_user(%{email: "a@test.com"}),
    Accounts.create_user(%{email: "b@test.com"})
  ]

  users = assert_all_ok(results)
  assert length(users) == 2
end

# Assert at least one error exists
test "some operations fail" do
  results = [
    {:ok, 1},
    {:error, :failed},
    {:ok, 3}
  ]

  assert_any_error(results)
end
```

---

## Pipeline Assertions

```elixir
# Assert pipeline succeeds
test "pipeline completes successfully" do
  ctx = assert_pipeline_ok(
    Pipeline.new(%{user_id: 123})
    |> Pipeline.step(:fetch, &fetch_user/1)
    |> Pipeline.step(:validate, &validate/1)
    |> Pipeline.run()
  )

  assert ctx.user != nil
  assert ctx.validated == true
end

# Assert pipeline fails at specific step
test "pipeline fails at validation" do
  reason = assert_pipeline_error(:validate,
    Pipeline.new(%{user_id: 123})
    |> Pipeline.step(:fetch, &fetch_user/1)
    |> Pipeline.step(:validate, fn _ -> {:error, :invalid} end)
    |> Pipeline.run()
  )

  assert reason == :invalid
end

# Assert pipeline fails with specific error
test "pipeline fails with expected error" do
  assert_pipeline_error(:fetch, :not_found,
    Pipeline.new(%{user_id: "nonexistent"})
    |> Pipeline.step(:fetch, fn ctx ->
      {:error, :not_found}
    end)
    |> Pipeline.run()
  )
end
```

---

## Maybe Assertions

```elixir
# Assert just value
test "finds user" do
  user = assert_just(Users.find_by_email("test@example.com"))
  assert user.email == "test@example.com"
end

# Assert nothing
test "returns nothing for deleted user" do
  assert_nothing(Users.find_by_email("deleted@example.com"))
end
```

---

## Test Helpers

### Creating Test Data

```elixir
# Wrap values in results
ok_user = wrap_ok(%User{id: 1, email: "test@example.com"})
error_result = wrap_error(:not_found)

# Extract values from mixed results
results = [
  {:ok, user1},
  {:error, :failed},
  {:ok, user2}
]

successful_users = ok_values(results)  # [user1, user2]
failures = error_reasons(results)       # [:failed]
```

### Mocking Functions

```elixir
# Always succeeds
test "handles successful fetch" do
  fetch = always_ok(%User{id: 1})
  assert {:ok, %User{}} = fetch.()
end

# Always fails
test "handles failed fetch" do
  fetch = always_error(:not_found)
  assert {:error, :not_found} = fetch.()
end
```

### Testing Retry Logic

```elixir
# Succeeds first N times, then fails
test "handles exhausted retries" do
  # Succeeds twice, then fails
  operation = flaky_fn(2, {:ok, :success}, {:error, :exhausted})

  assert {:ok, :success} = operation.()  # 1st call
  assert {:ok, :success} = operation.()  # 2nd call
  assert {:error, :exhausted} = operation.()  # 3rd call
end

# Fails first N times, then succeeds
test "retries until success" do
  # Fails twice, then succeeds
  operation = eventually_ok_fn(2, {:ok, :success}, {:error, :temporary})

  assert {:error, :temporary} = operation.()  # 1st call
  assert {:error, :temporary} = operation.()  # 2nd call
  assert {:ok, :success} = operation.()       # 3rd call
end
```

---

## Testing Patterns

### Pattern 1: Testing Result Chains

```elixir
test "chained operations succeed" do
  result =
    {:ok, %{amount: 100}}
    |> Result.and_then(&validate_amount/1)
    |> Result.and_then(&apply_discount/1)
    |> Result.map(&format_currency/1)

  assert_ok("$90.00", result)
end

test "chain stops on first error" do
  result =
    {:ok, %{amount: -10}}
    |> Result.and_then(&validate_amount/1)  # Fails here
    |> Result.and_then(&apply_discount/1)   # Skipped
    |> Result.map(&format_currency/1)       # Skipped

  assert_error(:invalid_amount, result)
end
```

### Pattern 2: Testing with Fixtures

```elixir
defmodule MyApp.OrdersTest do
  use ExUnit.Case
  import FnTypes.Testing

  setup do
    user = insert(:user)
    product = insert(:product, price: 100)
    {:ok, user: user, product: product}
  end

  test "creates order", %{user: user, product: product} do
    order = assert_ok(Orders.create(user, [product]))
    assert order.total == 100
    assert order.user_id == user.id
  end
end
```

### Pattern 3: Testing Async Operations

```elixir
test "parallel operations all succeed" do
  tasks = [
    fn -> {:ok, 1} end,
    fn -> {:ok, 2} end,
    fn -> {:ok, 3} end
  ]

  results = assert_ok(AsyncResult.parallel(tasks))
  assert results == [1, 2, 3]
end

test "parallel fails on first error" do
  tasks = [
    fn -> {:ok, 1} end,
    fn -> {:error, :failed} end,
    fn -> {:ok, 3} end
  ]

  assert_error(:failed, AsyncResult.parallel(tasks))
end

test "parallel with settlement collects all" do
  tasks = [
    fn -> {:ok, 1} end,
    fn -> {:error, :a} end,
    fn -> {:ok, 2} end,
    fn -> {:error, :b} end
  ]

  result = AsyncResult.parallel(tasks, settle: true)
  assert result.ok == [1, 2]
  assert result.errors == [:a, :b]
end
```

### Pattern 4: Testing Pipelines with Mocks

```elixir
test "pipeline handles external service failure" do
  # Mock the payment service to fail
  payment_step = fn _ctx ->
    {:error, :payment_declined}
  end

  result =
    Pipeline.new(%{order_id: 123, amount: 100})
    |> Pipeline.step(:validate, fn ctx -> {:ok, %{validated: true}} end)
    |> Pipeline.step(:charge, payment_step)
    |> Pipeline.step(:fulfill, fn ctx -> {:ok, %{fulfilled: true}} end)
    |> Pipeline.run()

  # Assert failure at charge step
  reason = assert_pipeline_error(:charge, result)
  assert reason == :payment_declined
end
```

### Pattern 5: Testing Error Normalization

```elixir
test "normalizes changeset errors" do
  changeset =
    %User{}
    |> User.changeset(%{email: "invalid"})

  {:error, error} =
    changeset
    |> Result.from_changeset(normalize: true)

  assert %FnTypes.Error{type: :validation} = error
  assert error.details.errors[:email] != nil
end

test "normalizes Ecto constraint errors" do
  # Insert duplicate
  insert(:user, email: "taken@example.com")

  {:error, error} =
    Accounts.create_user(%{email: "taken@example.com"})
    |> Result.normalize_error()

  assert error.type == :conflict
  assert error.code == :email_taken
end
```

---

## Testing Lazy/Streaming

```elixir
test "lazy computation defers execution" do
  executed = :counters.new(1, [:atomics])

  lazy = Lazy.defer(fn ->
    :counters.add(executed, 1, 1)
    {:ok, 42}
  end)

  # Not executed yet
  assert :counters.get(executed, 1) == 0

  # Execute
  assert_ok(42, Lazy.run(lazy))
  assert :counters.get(executed, 1) == 1
end

test "stream collects results" do
  results =
    [1, 2, 3, 4, 5]
    |> Lazy.stream(fn n ->
      if rem(n, 2) == 0, do: {:ok, n * 2}, else: {:error, :odd}
    end, on_error: :skip)
    |> Lazy.stream_collect()

  assert_ok([4, 8], results)
end

test "stream halts on error by default" do
  results =
    [1, 2, 3]
    |> Lazy.stream(fn
      2 -> {:error, :stop}
      n -> {:ok, n}
    end)
    |> Lazy.stream_collect()

  assert_error(:stop, results)
end
```

---

## Testing Side Effects

```elixir
test "function has expected side effects" do
  effects = FnTypes.SideEffects.get(MyApp.Users, :create_user, 1)
  assert :db_write in effects
  assert :email in effects
end

test "pure function has no side effects" do
  assert FnTypes.SideEffects.pure?(MyApp.Users, :format_name, 1)
end

test "finds all functions with db_write effect" do
  functions = FnTypes.SideEffects.with_effect(MyApp.Users, :db_write)
  assert {:create_user, 1} in functions
  assert {:update_user, 2} in functions
end
```

---

## Property-Based Testing

For property-based testing with StreamData:

```elixir
use ExUnitProperties

property "Result.map preserves structure" do
  check all value <- term() do
    result = {:ok, value}
    mapped = Result.map(result, &Function.identity/1)
    assert mapped == result
  end
end

property "Result.and_then composes" do
  check all a <- integer(), b <- integer() do
    result =
      {:ok, a}
      |> Result.and_then(fn x -> {:ok, x + b} end)

    assert_ok(a + b, result)
  end
end

property "error propagates through chain" do
  check all error <- atom(:alphanumeric) do
    result =
      {:error, error}
      |> Result.and_then(fn _ -> {:ok, :never_reached} end)
      |> Result.map(fn _ -> :also_never_reached end)

    assert_error(error, result)
  end
end
```

---

## Test Organization

### Recommended Structure

```
test/
├── my_app/
│   ├── accounts_test.exs      # Unit tests for Accounts context
│   └── accounts/
│       ├── user_test.exs      # Schema/changeset tests
│       └── pipelines_test.exs # Pipeline tests
├── my_app_web/
│   └── controllers/
│       └── user_controller_test.exs
├── support/
│   ├── fixtures.ex            # Test data helpers
│   └── result_helpers.ex      # Additional Result test helpers
└── test_helper.exs
```

### test_helper.exs

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(MyApp.Repo, :manual)

# Import FnTypes.Testing globally
import FnTypes.Testing
```
