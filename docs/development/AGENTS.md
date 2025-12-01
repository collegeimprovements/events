This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

## Codebase Conventions

### Control Flow & Pattern Matching

- **Prefer `case` and `cond` over `if..else`**. Ideally our codebase should have **zero `if...else`** statements
- **Pattern matching is our default**. This is what we love. This is what makes our Elixir code elegant, easy to debug, and easy to follow. This is what makes our code flat
  - **Always** use pattern matching whenever possible for function heads, case statements, and destructuring
  - Pattern matching makes our code self-documenting and reduces nesting
- **Avoid macros, favor pattern matching and functions**
  - Macros add complexity and make code harder to debug
  - Use pattern matching, multiple function clauses, and higher-order functions instead
  - Only use macros when absolutely necessary (like building DSLs or compile-time optimizations)
  - If you're considering a macro, first explore: pattern matching, function composition, protocols, or behaviours

#### Pattern Matching Examples

**Preferred - Multiple function clauses:**
```elixir
def process_result({:ok, value}), do: transform(value)
def process_result({:error, reason}), do: log_error(reason)
def process_result(nil), do: :no_data
```

**Avoid - Nested conditionals:**
```elixir
def process_result(result) do
  if result do
    case result do
      {:ok, value} -> transform(value)
      {:error, reason} -> log_error(reason)
    end
  else
    :no_data
  end
end
```

**Preferred - Guard clauses:**
```elixir
def calculate_discount(%{type: :premium, total: total}) when total > 1000, do: total * 0.20
def calculate_discount(%{type: :premium, total: total}), do: total * 0.10
def calculate_discount(%{type: :regular, total: total}) when total > 1000, do: total * 0.10
def calculate_discount(%{type: :regular, total: total}), do: total * 0.05
def calculate_discount(_), do: 0
```

**Avoid - Nested if statements:**
```elixir
def calculate_discount(order) do
  if order.type == :premium do
    if order.total > 1000, do: order.total * 0.20, else: order.total * 0.10
  else
    if order.total > 1000, do: order.total * 0.10, else: order.total * 0.05
  end
end
```

**Preferred - Destructuring in function heads:**
```elixir
def render_user(%User{name: name, email: email, role: :admin}) do
  "Admin: #{name} (#{email})"
end

def render_user(%User{name: name, email: email}) do
  "User: #{name} (#{email})"
end
```

#### Macros vs Pattern Matching

**Avoid macros - Use pattern matching and functions instead:**

```elixir
# ❌ AVOID - Using macro for simple conditional logic
defmacro if_admin(user, do: block) do
  quote do
    if unquote(user).role == :admin do
      unquote(block)
    end
  end
end

# ✅ PREFER - Pattern matching in function
def execute_if_admin(%User{role: :admin}, fun), do: fun.()
def execute_if_admin(%User{}, _fun), do: :ok

# ❌ AVOID - Macro for data transformation
defmacro transform_data(data, transform_type) do
  quote do
    case unquote(transform_type) do
      :upcase -> String.upcase(unquote(data))
      :downcase -> String.downcase(unquote(data))
    end
  end
end

# ✅ PREFER - Pattern matching with multiple function clauses
def transform_data(data, :upcase), do: String.upcase(data)
def transform_data(data, :downcase), do: String.downcase(data)
def transform_data(data, :capitalize), do: String.capitalize(data)

# ❌ AVOID - Macro for repeating similar code
defmacro define_getter(name) do
  quote do
    def unquote(name)(struct), do: Map.get(struct, unquote(name))
  end
end

# ✅ PREFER - Simple function or just use Map.get directly
def get_field(struct, field), do: Map.get(struct, field)
# Or even better: struct.field or pattern matching
```

**When macros ARE acceptable:**
- Building DSLs (like Phoenix routes, Ecto schemas)
- Compile-time optimizations that can't be done at runtime
- Code generation from external sources (like GraphQL schemas)
- Library-level abstractions (like our decorator system)

**For application code, prefer:**
1. Pattern matching in function clauses
2. Higher-order functions
3. Protocols for polymorphism
4. Behaviours for contracts
5. Plain functions with clear logic

### Date & Time Handling

- **Avoid `NaiveDateTime`** as long as possible. Prefer `DateTime` with UTC
- **Use the `Calendar` module** for date and time operations whenever helpful
- All timestamps should use `utc_datetime_usec` in schemas

### Error Handling & Supervision

- **Handle errors with `with`**, pattern matching, and proper logging
  - Use `with` for sequential operations that can fail
  - Pattern match on `{:ok, result}` and `{:error, reason}` tuples
- **Embrace "Let it crash"** philosophy with proper supervisor trees
- **Always return `{:ok, result}` or `{:error, reason}`** format from functions

### Logging

- **Follow OpenTelemetry style** for all logging
- Include structured metadata in logs for better observability
- Use appropriate log levels (debug, info, warning, error)

### Performance & Compilation

- **Always focus on performance** - we want faster code that compiles fast and runs fast
- **Check compilation cycles** with `xref` and follow best practices
- Avoid unnecessary compile-time dependencies
- Use runtime configuration where appropriate (see `config/runtime.exs`)

### Functional Programming Patterns

- **Embrace the Token pattern** - create a struct and pass it through a series of functions and pipelines
  - This pattern is used by Plug (`Conn` struct), Absinthe, Req, etc.
  - Example: `%MyContext{} |> step_one() |> step_two() |> step_three()`
- **Follow functional programming** principles throughout the codebase
- **Maintain consistent patterns** across the codebase so it's easy to optimize, follow, and fix issues

### Functional Data Structures

This project provides robust functional programming utilities. **Always use these modules** instead of manual pattern matching or custom implementations.

See `docs/functional/OVERVIEW.md` for comprehensive documentation with real-world examples.

#### Events.Result - Error Handling

Use `Result` for all fallible operations. Returns `{:ok, value} | {:error, reason}`.

```elixir
alias Events.Result

# Chain operations that can fail
{:ok, 5}
|> Result.map(&(&1 * 2))           # {:ok, 10}
|> Result.and_then(&validate/1)    # Chains if ok, short-circuits on error

# Safe exception handling
Result.try_with(fn -> risky_operation() end)

# Collect multiple results
Result.collect([{:ok, 1}, {:ok, 2}, {:ok, 3}])  # {:ok, [1, 2, 3]}
Result.collect([{:ok, 1}, {:error, :bad}])       # {:error, :bad}

# Add context to errors
{:error, :not_found}
|> Result.wrap_error(user_id: 123, action: :fetch)
# {:error, %{reason: :not_found, context: %{user_id: 123, action: :fetch}}}
```

#### Events.Maybe - Optional Values

Use `Maybe` for values that may or may not exist. Returns `{:some, value} | :none`.

```elixir
alias Events.Maybe

# Safe nested access
user
|> Maybe.from_nilable()
|> Maybe.and_then(&Maybe.from_nilable(&1.address))
|> Maybe.and_then(&Maybe.from_nilable(&1.city))
|> Maybe.unwrap_or("Unknown")

# Convert from nil
Maybe.from_nilable(nil)    # :none
Maybe.from_nilable("val")  # {:some, "val"}

# Provide defaults
Maybe.unwrap_or({:some, 42}, 0)  # 42
Maybe.unwrap_or(:none, 0)         # 0
```

#### Events.Pipeline - Multi-Step Workflows

Use `Pipeline` for complex multi-step operations with context accumulation.

```elixir
alias Events.Pipeline

Pipeline.new(%{input: data})
|> Pipeline.step(:validate, &validate_input/1)
|> Pipeline.step(:transform, &transform_data/1)
|> Pipeline.step(:persist, &save_to_db/1)
|> Pipeline.run()
# {:ok, %{input: data, validate: ..., transform: ..., persist: ...}}

# With cleanup handlers
Pipeline.new(%{})
|> Pipeline.step(:acquire_resource, &acquire/1)
|> Pipeline.ensure(:acquire_resource, fn _ctx, _result -> release_resource() end)
|> Pipeline.run_with_ensure()
```

#### Events.AsyncResult - Async Operations

Use `AsyncResult` for concurrent operations with proper error handling.

```elixir
alias Events.AsyncResult

# Parallel fetching
AsyncResult.parallel([
  fn -> fetch_users() end,
  fn -> fetch_orders() end,
  fn -> fetch_products() end
])
# {:ok, [users, orders, products]} or {:error, first_error}

# Race for fastest result
AsyncResult.race([
  fn -> fetch_from_cache() end,
  fn -> fetch_from_db() end
])

# Retry with backoff
AsyncResult.retry(fn -> flaky_api_call() end,
  max_attempts: 3,
  initial_delay: 100,
  max_delay: 2000
)
```

#### Pipeline + AsyncResult Composition

`Pipeline` and `AsyncResult` compose seamlessly. Use AsyncResult **inside** Pipeline steps for async operations.

**Feature Matrix:**

| Feature | AsyncResult | Pipeline | How to Compose |
|---------|-------------|----------|----------------|
| Parallel execution | `parallel/2`, `parallel_map/2` | `parallel/3` | Pipeline wraps AsyncResult internally |
| Race (first wins) | `race/2`, `race_with_fallback/3` | — | Use inside step function |
| Retry with backoff | `retry/2` | `step_with_retry/4` | Both available |
| Timeout | `with_timeout/2` | `run_with_timeout/2` | Both available at different levels |
| Batch processing | `batch/2` | — | Use inside step function |
| Progress tracking | `parallel_with_progress/3` | — | Use inside step function |
| Sequential fallback | `first_ok/1` | — | Use inside step function |
| Settlement (all results) | `parallel_settle/2` | — | Use inside step function |
| Context accumulation | — | `step/3`, `assign/3` | Pipeline-only |
| Branching | — | `branch/4` | Pipeline-only |
| Rollback | — | `run_with_rollback/1` | Pipeline-only |
| Checkpoints | — | `checkpoint/2` | Pipeline-only |

**Composition Examples:**

```elixir
# Race multiple sources inside a Pipeline step
Pipeline.new(%{id: 123})
|> Pipeline.step(:fetch_data, fn ctx ->
  AsyncResult.race([
    fn -> Cache.get(ctx.id) end,
    fn -> DB.get(ctx.id) end
  ])
  |> Result.map(&%{data: &1})
end)
|> Pipeline.run()

# Parallel enrichment inside a Pipeline step
Pipeline.new(%{user: user})
|> Pipeline.step(:enrich, fn ctx ->
  AsyncResult.parallel([
    fn -> fetch_preferences(ctx.user.id) end,
    fn -> fetch_notifications(ctx.user.id) end
  ])
  |> Result.map(fn [prefs, notifs] ->
    %{preferences: prefs, notifications: notifs}
  end)
end)
|> Pipeline.run()

# Retry with backoff for flaky operations
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

# Batch processing with rate limiting
Pipeline.new(%{items: items})
|> Pipeline.step(:process_batches, fn ctx ->
  AsyncResult.batch(
    Enum.map(ctx.items, fn item -> fn -> process_item(item) end end),
    batch_size: 10,
    delay_between_batches: 1000
  )
  |> Result.map(&%{results: &1})
end)
|> Pipeline.run()
```

**When to Use Which:**

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

#### Events.Guards - Pattern Matching Guards

Use guards in function heads for cleaner pattern matching.

```elixir
import Events.Guards

# Guards in function definitions
def handle(result) when is_ok(result), do: :success
def handle(result) when is_error(result), do: :failure

def process(maybe) when is_some(maybe), do: :present
def process(maybe) when is_none(maybe), do: :absent

# Pattern matching macros
case result do
  ok(value) -> process(value)
  error(reason) -> handle_error(reason)
end

case maybe do
  some(v) -> use(v)
  none() -> default()
end
```

#### Quick Reference

| Need | Use | Example |
|------|-----|---------|
| Fallible operation | `Result` | `Result.and_then(result, &process/1)` |
| Optional value | `Maybe` | `Maybe.from_nilable(user.email)` |
| Multi-step workflow | `Pipeline` | `Pipeline.step(p, :name, &fun/1)` |
| Concurrent tasks | `AsyncResult` | `AsyncResult.all(tasks)` |
| Guard clauses | `Guards` | `when is_ok(result)` |
| Error context | `Result.wrap_error/2` | `Result.wrap_error(err, ctx)` |
| Safe exceptions | `Result.try_with/1` | `Result.try_with(fn -> ... end)` |

#### Pipe Operator for Clean Transformations

**Preferred - Flat pipeline:**
```elixir
def process_data(data) do
  data
  |> validate()
  |> transform()
  |> enrich()
  |> persist()
end
```

**Avoid - Nested function calls:**
```elixir
def process_data(data) do
  persist(enrich(transform(validate(data))))
end
```

#### Early Returns with Pattern Matching

**Preferred - Early validation:**
```elixir
def process(nil), do: {:error, :nil_input}
def process(""), do: {:error, :empty_input}
def process(value) when byte_size(value) > 1000, do: {:error, :too_large}
def process(value), do: {:ok, String.upcase(value)}
```

**Avoid - Deeply nested validation:**
```elixir
def process(value) do
  if value do
    if value != "" do
      if byte_size(value) <= 1000 do
        {:ok, String.upcase(value)}
      else
        {:error, :too_large}
      end
    else
      {:error, :empty_input}
    end
  else
    {:error, :nil_input}
  end
end
```

### Function Design

- **Consider the Token pattern** when creating functions
- **Pass `context` as one of the arguments** to handle business logic nicely
- **Use keyword list as the last argument** for configuration options
  - This allows us to extend and change functions while maintaining backward compatibility
  - Example: `def create_user(attrs, context, opts \\ [])`

### Code Organization & Reusability

- **Create separate contexts for generic operations**:
  - CRUD operations
  - Pagination
  - Transactions (`Ecto.Multi`)
  - Caching
  - Other cross-cutting concerns
- **Compose and reuse** these contexts across the application

#### Module Organization

**Keep modules focused and well-organized:**

```elixir
defmodule MyApp.Users do
  @moduledoc """
  User management context.
  Handles user CRUD operations, authentication, and authorization.
  """

  # Module attributes
  @default_role :user

  # Types
  @type user_attrs :: %{
    required(:email) => String.t(),
    required(:name) => String.t(),
    optional(:role) => atom()
  }

  # Public API (exported functions)
  def create_user(attrs), do: do_create(attrs, @default_role)
  def get_user(id), do: Repo.get(User, id)

  # Private functions
  defp do_create(attrs, role) do
    # Implementation
  end
end
```

**Key principles:**
- One clear responsibility per module
- Small, focused functions (< 10 lines ideally)
- Extract complex logic into separate modules
- Always document public functions with @doc and @spec

### HTTP Layer (Req)

- **Always use `Req`** for HTTP requests
- **Configure 3 retries as default**
- **Respect proxies** when configured
- **Log HTTP requests** when required for debugging and monitoring

### S3 Layer (Events.Services.S3)

**Always use `Events.Services.S3`** for all S3 operations. Never use raw ExAws or other S3 libraries directly.

#### API Styles

**Direct API** (config as last argument):
```elixir
alias Events.Services.S3

config = S3.config(access_key_id: "...", secret_access_key: "...")
:ok = S3.put("s3://bucket/file.txt", "content", config)
{:ok, data} = S3.get("s3://bucket/file.txt", config)
:ok = S3.delete("s3://bucket/file.txt", config)
```

**Pipeline API** (chainable, config first):
```elixir
S3.new(config)
|> S3.bucket("my-bucket")
|> S3.prefix("uploads/")
|> S3.content_type("image/jpeg")
|> S3.put("photo.jpg", jpeg_data)

# From environment
S3.from_env()
|> S3.expires_in({5, :minutes})
|> S3.presign("s3://bucket/file.pdf")
```

#### S3 URIs

All operations accept `s3://bucket/key` URIs:
```elixir
"s3://my-bucket/path/to/file.txt"
"s3://my-bucket/prefix/"              # For listing
```

#### Core Operations

- `put/3-4` - Upload content
- `get/2` - Download content
- `delete/2` - Delete object
- `exists?/2` - Check existence
- `head/2` - Get metadata
- `list/2-3` - List objects (paginated)
- `list_all/3` - List all (handles pagination)
- `copy/3` - Copy within S3
- `presign/2-3` - Generate presigned URL

#### Batch Operations (with glob support)

```elixir
S3.put_all([{"a.txt", "..."}, {"b.txt", "..."}], config, to: "s3://bucket/")
S3.get_all(["s3://bucket/*.pdf"], config)
S3.delete_all(["s3://bucket/temp/*.tmp"], config)
S3.copy_all("s3://source/*.jpg", config, to: "s3://dest/")
```

#### Configuration

```elixir
# From environment variables
S3.from_env()

# Manual
S3.config(
  access_key_id: "AKIA...",
  secret_access_key: "...",
  region: "us-east-1"
)

# LocalStack / MinIO
S3.config(
  access_key_id: "test",
  secret_access_key: "test",
  endpoint: "http://localhost:4566"
)
```

#### File Name Normalization

```elixir
S3.normalize_key("User's Photo (1).jpg")  #=> "users-photo-1.jpg"
S3.normalize_key("report.pdf", prefix: "docs", timestamp: true)
```

### Database Layer (Ecto)

- **Use Ecto** as the primary database interface
- **Use raw SQL queries** when you can generate better performance with them
- **Create database views** for common query patterns
- **Prefer `Ecto.Multi`** for complex transactions
- Always preload associations when needed (see Ecto Guidelines below)

### Type Decorators & Result Types

This project uses a comprehensive decorator system for type safety and consistency. See `TYPE_DECORATORS.md` for full documentation.

#### Always Use Result Tuples

**All functions that can fail MUST return `{:ok, result} | {:error, reason}`:**

```elixir
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
@decorate returns_result(ok: User.t(), error: Ecto.Changeset.t())
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

#### Pattern Match on Result Types

```elixir
# Preferred - clear and flat
def handle_user_creation(attrs) do
  case create_user(attrs) do
    {:ok, user} -> send_welcome_email(user)
    {:error, changeset} -> log_validation_errors(changeset)
  end
end

# Also good - using with for sequential operations
def register_user(attrs) do
  with {:ok, user} <- create_user(attrs),
       {:ok, _email} <- send_welcome_email(user),
       {:ok, _settings} <- create_default_settings(user) do
    {:ok, user}
  end
end
```

#### Use normalize_result for External Code

When wrapping external libraries or legacy code that doesn't return result tuples:

```elixir
@decorate normalize_result(
  nil_is_error: true,
  wrap_exceptions: true,
  error_mapper: &format_api_error/1
)
def fetch_user_from_api(id) do
  # External API that might return various formats
  HTTPoison.get!("https://api.example.com/users/#{id}")
end
```

#### Available Type Decorators

- `@decorate returns_result(ok: Type, error: Type)` - Standard result pattern
- `@decorate returns_maybe(Type)` - For `value | nil` returns
- `@decorate returns_bang(Type)` - Unwraps `{:ok, value}` or raises
- `@decorate returns_struct(Module)` - Validates struct returns
- `@decorate returns_list(of: Type)` - List with element validation
- `@decorate returns_union(types: [Type1, Type2])` - Multiple possible types
- `@decorate returns_pipeline(ok: Type, error: Type)` - Chainable pipeline operations
- `@decorate normalize_result()` - Converts any return to result tuple

#### Combine with @spec for Full Type Safety

```elixir
# Best practice: Both @spec (for Dialyzer) and decorator (for runtime)
@spec find_user(integer()) :: {:ok, User.t()} | {:error, :not_found}
@decorate returns_result(ok: User.t(), error: :atom, validate: Mix.env() != :prod)
def find_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end
```

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

#### JavaScript Libraries & Utilities

**Standard JavaScript Libraries:**

This project uses two primary JavaScript utility libraries that should be your go-to for common operations:

1. **[@formkit/tempo](https://tempo.formkit.com/)** - For all date and time operations
   - Date formatting and parsing
   - Timezone conversions
   - Date arithmetic (add/subtract days, months, etc.)
   - Relative time (e.g., "2 hours ago")
   - **Always prefer Tempo over native Date methods or moment.js alternatives**

2. **[es-toolkit](https://es-toolkit.dev/)** - For utility functions and data manipulation
   - Array operations (chunk, uniq, groupBy, etc.)
   - Object manipulation (pick, omit, merge, etc.)
   - String utilities (camelCase, snakeCase, etc.)
   - Type checking and validation
   - **Always prefer es-toolkit over lodash, underscore, or reinventing the wheel**

**Function Composition with es-toolkit:**

- **Always use `flow` or `pipe` from es-toolkit** for composing multiple function calls
- This creates cleaner, more readable code with better function composition
- Prefer `pipe` for left-to-right data flow (most intuitive)
- Use `flow` when you need to create reusable composed functions

**Examples:**

```javascript
import { pipe, flow } from 'es-toolkit';
import { format, addDays } from '@formkit/tempo';

// Prefer pipe for direct transformations (left-to-right)
const result = pipe(
  data,
  filterInvalid,
  sortByDate,
  formatForDisplay
);

// Use flow to create reusable compositions
const processUserData = flow(
  validateUser,
  enrichWithDefaults,
  normalizeFields
);

const processedUser = processUserData(rawUser);

// Example combining both libraries
import { uniq, sortBy } from 'es-toolkit';

const formatEventDates = pipe(
  events,
  (list) => uniq(list),
  (list) => sortBy(list, e => e.date),
  (list) => list.map(e => ({
    ...e,
    formattedDate: format(e.date, 'MMMM D, YYYY')
  }))
);
```

**Why These Libraries?**

- **Performance**: Both libraries are highly optimized and tree-shakeable
- **Type Safety**: Full TypeScript support with excellent type inference
- **Modern**: Built for modern JavaScript/ES2022+
- **Lightweight**: Small bundle sizes compared to alternatives
- **Consistency**: Using standard libraries across the codebase makes code more maintainable

**When to Use What:**

- Need to format a date? → Use `@formkit/tempo`
- Need to parse a date string? → Use `@formkit/tempo`
- Need to filter/map/reduce arrays? → Use `es-toolkit`
- Need to manipulate objects? → Use `es-toolkit`
- Need to compose multiple functions? → Use `pipe`/`flow` from `es-toolkit`
- Need to check types? → Use `es-toolkit` type guards

**Installation:**

These libraries are already installed in `assets/package.json`. To add new npm packages:

```bash
cd assets
npm install <package-name>
```

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- **Use explicit list syntax instead of sigils** for simple data lists, but prefer sigils for command-line arguments

  **Always prefer explicit list syntax for data lists**:

      # Good - explicit and clear for data
      truthy_values = ["1", "true", "yes"]
      statuses = [:pending, :active, :completed]
      error_codes = [400, 401, 403, 404]

  **Avoid sigils for simple data lists**:

      # Avoid - less explicit for data
      truthy_values = ~w(1 true yes)
      statuses = ~w(pending active completed)a

  **Prefer sigils for command-line arguments and shell commands**:

      # Good - sigils are appropriate for command-line args
      args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js)
      watchers: [
        esbuild: {Esbuild, :install_and_run, [:events, ~w(--sourcemap=inline --watch)]},
        tailwind: {Tailwind, :install_and_run, [:events, ~w(--watch)]}
      ]

      # Avoid - explicit lists make command args harder to read
      args: ["js/app.js", "--bundle", "--target=es2022", "--outdir=../priv/static/assets/js"]

  **Summary**: Use explicit list syntax `["a", "b", "c"]` or `[:a, :b, :c]` for data and configuration values. Use sigils `~w()` for command-line arguments, shell commands, and arguments that would be passed to external tools.

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct

### Ecto Schema Field Type Conventions

**Always** use these field types by default when creating new schemas or migrations:

- **citext fields** (case-insensitive text - requires `citext` extension):
  - Text classification: `name`, `type`, `subtype`, `status`, `substatus`
  - Categorization: `category`, `tag`, `subtag`
  - Identifiers: `email`, `url`, `slug`
  - Reasoning: Case-insensitive searches and comparisons without manual lowercasing

- **text fields**:
  - `description`, `summary`, `short_description`, `notes`, `content`

- **jsonb fields**:
  - `metadata`, `assets`, `assets_metadata`, `settings`, `preferences`

- **utc_datetime_usec fields** (any field ending with `_at`):
  - `inserted_at`, `updated_at`, `created_at`, `deleted_at`, `published_at`, `expires_at`

- **integer fields**:
  - `count`, `number_of_*`, `price_in_cents`, `amount_in_cents`

- **decimal fields**:
  - `price`, `amount`, `balance`, `rate`, `percentage`

- **positive_integers** (zero and greater):
  - `number_of_visitors`, `number_of_attendees`, `number_of_people`, `quantity`
  - Use custom validation or database constraints to enforce positive values

**Migration Example**:

    # Enable citext extension (in a dedicated migration)
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    # Using citext in migrations
    create table(:products) do
      add :name, :citext, null: false
      add :slug, :citext, null: false
      add :type, :citext
      add :subtype, :citext
      add :status, :citext, default: "active", null: false
      add :category, :citext

      add :description, :text
      add :metadata, :jsonb, default: fragment("'{}'"), null: false

      timestamps(type: :utc_datetime_usec)
    end

### Soft Delete Conventions

**Always use soft delete for user-facing data**. Hard deletes should be rare and limited to:
- System/internal records
- Truly sensitive data that must be removed
- Cleanup of test/temporary data

**Use the `deleted_fields/1` macro** from `Events.Repo.MigrationMacros`:

    # Migration with soft delete support
    import Events.Repo.MigrationMacros

    create table(:documents) do
      add :title, :citext, null: false
      add :content, :text

      deleted_fields()  # Adds deleted_at and deleted_by_urm_id
      timestamps()
    end

    # Essential indexes for soft delete
    create index(:documents, [:deleted_at])
    create index(:documents, [:deleted_by_urm_id])
    create index(:documents, [:status], where: "deleted_at IS NULL")

**Query conventions**:

    # ALWAYS filter deleted records in default queries
    def list_products do
      from p in Product,
        where: is_nil(p.deleted_at)
    end

    # Explicit scope functions
    def not_deleted(query \\ Product) do
      from q in query, where: is_nil(q.deleted_at)
    end

    # Admin/trash views (include deleted)
    def list_all_products_including_deleted do
      from p in Product  # No deleted_at filter
    end

**Context function patterns**:

    # Soft delete
    def delete_product(product, deleted_by_urm_id) do
      product
      |> Ecto.Changeset.change(%{
        deleted_at: DateTime.utc_now(),
        deleted_by_urm_id: deleted_by_urm_id
      })
      |> Repo.update()
    end

    # Restore
    def restore_product(product) do
      product
      |> Ecto.Changeset.change(%{
        deleted_at: nil,
        deleted_by_urm_id: nil
      })
      |> Repo.update()
    end

    # Hard delete old records (background job)
    def purge_old_deleted_products(days_old \\ 90) do
      cutoff = DateTime.utc_now() |> DateTime.add(-days_old, :day)

      from(p in Product,
        where: not is_nil(p.deleted_at),
        where: p.deleted_at < ^cutoff
      )
      |> Repo.delete_all()
    end

**deleted_fields macro options**:

    # Both fields (default)
    deleted_fields()

    # Only timestamp (no audit)
    deleted_fields(only: :deleted_at)

    # Only audit (unusual)
    deleted_fields(only: :deleted_by_urm_id)

    # No FK constraints (for early migrations)
    deleted_fields(references: false)

**Schema Example**:

    defmodule MyApp.Catalog.Product do
      use Ecto.Schema

      schema "products" do
        # citext fields map to :string in Ecto schemas
        field :name, :string
        field :slug, :string
        field :type, :string
        field :subtype, :string
        field :status, :string
        field :category, :string

        field :description, :string
        field :metadata, :map

        timestamps(type: :utc_datetime_usec)
      end
    end
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->

---

## Code Style Golden Rules

When working on this codebase, always remember:

### 1. Pattern Matching First (Avoid Macros)
- Use multiple function clauses instead of nested if/case
- Destructure in function heads
- Use guard clauses extensively
- Pattern match on result tuples
- **Avoid macros** - use pattern matching and functions instead
- Only write macros for DSLs, compile-time optimizations, or library-level abstractions
- If considering a macro, first try: pattern matching, higher-order functions, protocols, or behaviours

### 2. Keep Code Flat
- Zero `if...else` statements (use `case` or `cond`)
- Prefer `with` over nested `case`
- Early returns with pattern matching
- Pipeline operator for transformations

### 3. Result Tuples Everywhere
- All functions that can fail return `{:ok, result} | {:error, reason}`
- Use type decorators for consistency: `@decorate returns_result(...)`
- Use `normalize_result` decorator for external code
- Pattern match on errors with specific handlers

### 4. Clean and Elegant
- Small, focused functions (< 10 lines)
- One responsibility per module
- Self-documenting code through patterns
- Clear naming, obvious intent

### 5. Documentation
- Always add `@doc` and `@spec` for public functions
- Use `@moduledoc` to explain module purpose
- Include examples in documentation
- Combine `@spec` with decorators for full type safety

### Anti-Patterns to Absolutely Avoid

❌ **Using macros instead of functions**
```elixir
# NEVER do this - macro for simple logic
defmacro double(x) do
  quote do: unquote(x) * 2
end

# ALWAYS do this - plain function
def double(x), do: x * 2

# NEVER do this - macro for conditional
defmacro when_admin(user, do: block) do
  quote do
    if unquote(user).role == :admin, do: unquote(block)
  end
end

# ALWAYS do this - pattern matching
def when_admin(%User{role: :admin}, fun), do: fun.()
def when_admin(%User{}, _fun), do: :ok
```

❌ **Nested if/else statements**
```elixir
# NEVER do this
if condition do
  if other_condition do
    # nested logic
  end
end
```

❌ **Not using pattern matching**
```elixir
# NEVER do this
def get_name(user) do
  if user && user.name, do: user.name, else: "Unknown"
end

# ALWAYS do this
def get_name(%User{name: name}) when is_binary(name), do: name
def get_name(_), do: "Unknown"
```

❌ **Returning non-result tuples from functions that can fail**
```elixir
# NEVER do this
def create_user(attrs), do: Repo.insert(User.changeset(%User{}, attrs))

# ALWAYS do this
@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

❌ **Deep nesting**
```elixir
# NEVER do this
case result do
  {:ok, value} ->
    case validate(value) do
      {:ok, validated} ->
        case process(validated) do
          {:ok, result} -> result
        end
    end
end

# ALWAYS do this
with {:ok, value} <- result,
     {:ok, validated} <- validate(value),
     {:ok, result} <- process(validated) do
  result
end
```

### Quick Reference

| Scenario | Use This | Not This |
|----------|----------|----------|
| Code abstraction | Functions + pattern matching | Macros |
| Multiple conditions | `case` or `cond` | `if...else if` |
| Function variations | Multiple function clauses | Single function with nested if |
| Sequential operations | `with` | Nested `case` |
| Transformations | Pipe operator `\|>` | Nested function calls |
| Error handling | `{:ok, _} \| {:error, _}` | Mixed returns |
| External code | `@decorate normalize_result` | Manual wrapping |
| Type safety | `@spec` + decorators | Just `@spec` |
| Validation | Guard clauses | if statements inside function |
| Polymorphism | Protocols | Macros |
| Contracts | Behaviours | Macros |

---

## Summary

**This is a Phoenix web application that prioritizes:**

1. **Pattern matching** over conditionals
2. **Flat, readable code** over nested structures
3. **Result tuples** for all operations that can fail
4. **Type safety** through specs and decorators
5. **Functional patterns** like pipes and composition
6. **Performance** - fast compilation and runtime
7. **Consistency** - same patterns across the entire codebase

**Key tools and patterns:**
- `Req` for HTTP requests
- Type decorators for runtime validation
- `with` for sequential operations
- Pattern matching in function heads
- Token pattern for state transformation
- Soft deletes with `deleted_at`
- citext for case-insensitive fields
- Result tuples with `@spec` + decorators

**When in doubt:** Ask yourself "How can I make this flatter and use more pattern matching?" The answer is usually the right approach for this codebase.

For detailed documentation:
- Type system: `TYPE_DECORATORS.md`
- Dialyzer setup: `DIALYZER_SETUP.md`
- Normalize result: `NORMALIZE_RESULT_GUIDE.md`
- Compiler integration: `COMPILER_INTEGRATION.md`