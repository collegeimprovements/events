# AI Agent Guidelines for Events Application

> **Purpose**: This document provides coding standards and behavioral guidelines for AI assistants (like Claude) working on the Events codebase.

> **Enforcement Level**:
> - 🔴 **CRITICAL** = Security, data integrity, breaking changes - MUST follow
> - 🟡 **IMPORTANT** = Performance, maintainability, conventions - SHOULD follow
> - 🟢 **PREFERRED** = Style preferences, optimizations - NICE to follow

## Table of Contents
1. [How to Use This Guide](#how-to-use-this-guide)
2. [AI Behavioral Guidelines](#ai-behavioral-guidelines)
3. [Security Guidelines](#security-guidelines)
4. [Testing Guidelines](#testing-guidelines)
5. [Git Workflow](#git-workflow)
6. [Project Guidelines](#project-guidelines)
7. [Codebase Conventions](#codebase-conventions)
8. [Framework-Specific Guidelines](#framework-specific-guidelines)
   - [Elixir Guidelines](#elixir-guidelines)
   - [Mix Guidelines](#mix-guidelines)
   - [Phoenix Guidelines](#phoenix-guidelines)
   - [Ecto Guidelines](#ecto-guidelines)
   - [Phoenix HTML Guidelines](#phoenix-html-guidelines)
   - [Phoenix LiveView Guidelines](#phoenix-liveview-guidelines)
9. [Common Decision Trees](#common-decision-trees)
10. [Troubleshooting](#troubleshooting)
11. [Project Glossary](#project-glossary)

---

## How to Use This Guide

- AI agents should follow all guidelines unless explicitly overridden by the user
- When uncertain, ask for clarification rather than guessing
- Suggest alternatives when guidelines conflict with user requests
- Pay special attention to 🔴 CRITICAL items - these prevent bugs, security issues, and breaking changes
- 🟡 IMPORTANT items improve code quality and maintainability
- 🟢 PREFERRED items are stylistic preferences that make code more consistent

---

## AI Behavioral Guidelines

### Problem-Solving Approach

- 🔴 **Read before writing**: Always read existing code in the relevant area before making changes
- 🔴 **Understand before modifying**: Trace data flow and dependencies before refactoring
- 🔴 **Test your changes**: Run tests after modifications and fix all failures before proceeding
- 🔴 **Run precommit checks**: Always run `mix precommit` before committing and fix all issues
- 🟡 **Commit atomically**: Each commit should be a logical, working unit
- 🟡 **Follow existing patterns**: Maintain consistency with the codebase's established patterns

### Communication Guidelines

- 🟡 **Ask when ambiguous**: If requirements are unclear, ask specific questions
- 🟡 **Explain trade-offs**: When multiple approaches exist, present options with pros/cons
- 🔴 **Flag risks**: Proactively identify security, performance, or breaking change concerns
- 🟢 **Suggest improvements**: Point out code smells or better patterns when relevant

### When to Deviate from Guidelines

You may deviate from these guidelines when:
- User explicitly requests a different approach
- Guideline conflicts with project constraints (e.g., external library requirements)
- Following the guideline would introduce bugs or security issues
- **ALWAYS explain why you're deviating**

### Error Handling Workflow

- 🔴 If tests fail after changes, debug and fix before moving on
- 🔴 If compilation fails, analyze error messages carefully
- 🔴 If `mix precommit` fails, fix all errors and warnings
- 🟡 If uncertain about a fix, explain the error and ask for guidance

---

## Security Guidelines

### 🔴 Input Validation & Sanitization (CRITICAL)

- **NEVER** trust user input - validate all parameters
- **NEVER** use `String.to_atom/1` on user input (memory leak/DoS risk)
- **ALWAYS** use parameterized queries - avoid string interpolation in SQL
- **ALWAYS** validate and sanitize file uploads
- **ALWAYS** validate file paths - use `Path.safe_relative/1` to prevent path traversal

### 🔴 Common Vulnerabilities to Avoid (CRITICAL)

- ❌ **SQL Injection**: Use Ecto queries or parameterized raw SQL only - never interpolate user input into SQL
- ❌ **XSS**: Phoenix escapes by default, but be careful with `Phoenix.HTML.raw/1`
- ❌ **Command Injection**: Validate all inputs to `System.cmd/3` and shell commands
- ❌ **Path Traversal**: Validate file paths, reject `..` sequences
- ❌ **CSRF**: Ensure all forms use Phoenix's built-in CSRF protection (automatic with `<.form>`)
- ❌ **Mass Assignment**: Never include protected fields (e.g., `user_id`, `role`) in `cast/3` calls

### 🔴 Authentication & Authorization (CRITICAL)

- **Fields set programmatically** (e.g., `user_id`, `role`) must **NOT** be in `cast/3` calls
- **Always verify** current user has permission for the operation
- **Always use** `current_scope` and proper LiveView `on_mount` hooks
- **Never** expose sensitive data in logs, error messages, or responses

### 🔴 Secrets Management (CRITICAL)

- **Never** commit secrets, API keys, or credentials to version control
- **Never** commit `.env` files or `credentials.json`
- Use environment variables for configuration
- Use runtime configuration in `config/runtime.exs`

---

## Testing Guidelines

### 🔴 Test Requirements (CRITICAL)

- **ALWAYS run tests after changes**: `mix test`
- **Fix failing tests before committing**: Never commit broken tests
- **Run `mix precommit` before every commit**: This runs tests, formatter, Credo, and other checks
- Write tests for new features and bug fixes

### 🟡 Test Coverage Expectations

- Write tests for happy path AND edge cases
- Test error handling and validation
- Test authentication and authorization logic
- Test database constraints and validations

### 🟡 Test Organization

- Follow existing test file structure
- Use descriptive test names that explain the scenario
- Create test fixtures using appropriate tools
- Clean up test data appropriately
- Keep tests isolated - they should not depend on other tests

### LiveView Test Patterns

- Use `Phoenix.LiveViewTest` module and `LazyHTML` for making assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files
- **Always reference the key element IDs** you added in LiveView templates in your tests
- **Never** test against raw HTML, **always** use `element/2`, `has_element/2`, and similar
- Focus on testing outcomes rather than implementation details

### Debugging Failing Tests

- 🟡 To debug test failures, run tests in a specific file with `mix test test/my_test.exs`
- 🟡 Run all previously failed tests with `mix test --failed`
- 🟡 Add debug statements using `LazyHTML` to print actual HTML structure:

```elixir
html = render(view)
document = LazyHTML.from_fragment(html)
matches = LazyHTML.filter(document, "your-complex-selector")
IO.inspect(matches, label: "Matches")
```

---

## Git Workflow

### 🔴 Branching (CRITICAL)

- Work on feature branches prefixed with `claude/`
- Branch names should be descriptive: `claude/add-user-authentication`
- **NEVER** push to `main` or `master` directly
- Create the branch locally if it doesn't exist yet

### 🔴 Pre-Commit Checks (CRITICAL)

- **ALWAYS run `mix precommit` before committing**
- Fix all errors and warnings before pushing
- Address Credo, formatter, and test failures
- Never skip hooks or checks

### 🟡 Commit Messages

Use clear, descriptive commit messages following this format:

```
<type>: <description>

Examples:
feat: Add user registration form
fix: Resolve N+1 query in user list
refactor: Extract email validation logic
docs: Update AGENTS.md with security guidelines
test: Add tests for authentication flow
perf: Optimize product query with database view
```

### 🔴 Push Requirements (CRITICAL)

- Always use `git push -u origin <branch-name>`
- Branch must start with `claude/` and end with matching session ID
- If push fails due to network errors, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s)

### 🟡 Commit Best Practices

- Create atomic commits - each commit should be a logical, working unit
- Don't commit commented-out code
- Don't commit debugging statements (console.log, IO.inspect, etc.)
- Ensure code compiles and tests pass before committing

---

## Project Guidelines

### 🔴 Required Commands (CRITICAL)

- **Use `mix precommit` alias** when you are done with all changes and fix any pending issues
- This command runs: formatter, Credo, tests, and other quality checks

### 🟡 HTTP Client Library

- **Use the already included `:req` (`Req`) library** for HTTP requests
- **Avoid** `:httpoison`, `:tesla`, and `:httpc`
- Req is included by default and is the preferred HTTP client for Phoenix apps

---

## Codebase Conventions

### Control Flow & Pattern Matching

- 🔴 **Always return `{:ok, result}` or `{:error, reason}`** format from functions that can fail
- 🟡 **Prefer `case` and `cond` over `if..else`** for multi-branch logic (3+ branches)
- 🟢 Simple `if/else` is acceptable for binary conditions when clearer than alternatives
- 🔴 **NEVER** use nested `if/else` - always refactor to `case`, `cond`, or separate functions
- 🟡 **Pattern matching is our default**. This is what makes our Elixir code elegant, easy to debug, and easy to follow
  - **Always** use pattern matching whenever possible for function heads, case statements, and destructuring
  - Pattern matching makes our code self-documenting and reduces nesting

### Date & Time Handling

- 🟡 **Avoid `NaiveDateTime`** as long as possible. Prefer `DateTime` with UTC
- 🟡 **Use the `Calendar` module** for date and time operations whenever helpful
- 🔴 All timestamps should use `utc_datetime_usec` in schemas

### Error Handling & Supervision

- 🟡 **Handle errors with `with`**, pattern matching, and proper logging
  - Use `with` for sequential operations that can fail
  - Pattern match on `{:ok, result}` and `{:error, reason}` tuples
- 🟡 **Embrace "Let it crash"** philosophy with proper supervisor trees
- 🔴 **Always return `{:ok, result}` or `{:error, reason}`** format from functions

### Logging

- 🟡 **Follow OpenTelemetry style** for all logging
- 🟡 Include structured metadata in logs for better observability
- 🟡 Use appropriate log levels (debug, info, warning, error)
- 🔴 **Never** log sensitive data (passwords, tokens, PII)

### Performance & Compilation

- 🟡 **Always focus on performance** - we want faster code that compiles fast and runs fast
- 🟡 **Check compilation cycles** with `xref` and follow best practices
- 🟡 Avoid unnecessary compile-time dependencies
- 🟡 Use runtime configuration where appropriate (see `config/runtime.exs`)

### Functional Programming Patterns

- 🟡 **Embrace the Token pattern** - create a struct and pass it through a series of functions and pipelines
  - This pattern is used by Plug (`Conn` struct), Absinthe, Req, etc.
  - Example: `%MyContext{} |> step_one() |> step_two() |> step_three()`
- 🟡 **Follow functional programming** principles throughout the codebase
- 🟡 **Maintain consistent patterns** across the codebase so it's easy to optimize, follow, and fix issues

**Example - Token pattern for multi-step operation:**

```elixir
defmodule MyApp.OrderProcessor do
  defstruct [:order, :user, :payment, :inventory, errors: []]

  def process_order(order_id, user_id) do
    %__MODULE__{}
    |> load_order(order_id)
    |> load_user(user_id)
    |> validate_inventory()
    |> process_payment()
    |> update_inventory()
    |> send_confirmation()
    |> handle_result()
  end

  defp handle_result(%{errors: []} = ctx), do: {:ok, ctx.order}
  defp handle_result(%{errors: errors}), do: {:error, errors}

  defp load_order(ctx, order_id) do
    case Orders.get_order(order_id) do
      {:ok, order} -> %{ctx | order: order}
      {:error, reason} -> %{ctx | errors: [{:order, reason} | ctx.errors]}
    end
  end
  # ... other pipeline steps
end
```

**Avoid - Nested conditionals:**

```elixir
# BAD - hard to read and maintain
def process_order(order_id, user_id) do
  case Orders.get_order(order_id) do
    {:ok, order} ->
      case Users.get_user(user_id) do
        {:ok, user} ->
          case validate_inventory(order) do
            :ok ->
              # Even more nesting...
            {:error, reason} -> {:error, reason}
          end
        {:error, reason} -> {:error, reason}
      end
    {:error, reason} -> {:error, reason}
  end
end
```

### Function Design

- 🟡 **Consider the Token pattern** when creating functions
- 🟡 **Pass `context` as one of the arguments** to handle business logic nicely
- 🟡 **Use keyword list as the last argument** for configuration options
  - This allows us to extend and change functions while maintaining backward compatibility
  - Example: `def create_user(attrs, context, opts \\ [])`

### Code Organization & Reusability

- 🟡 **Create separate contexts for generic operations**:
  - CRUD operations
  - Pagination
  - Transactions (`Ecto.Multi`)
  - Caching
  - Other cross-cutting concerns
- 🟡 **Compose and reuse** these contexts across the application

### HTTP Layer (Req)

- 🔴 **Always use `Req`** for HTTP requests (not HTTPoison, Tesla, or httpc)
- 🟡 **Configure 3 retries as default**
- 🟡 **Respect proxies** when configured
- 🟡 **Log HTTP requests** when required for debugging and monitoring

### Database Layer (Ecto)

- 🟡 **Use Ecto** as the primary database interface
- 🟡 **Use raw SQL queries** when you can generate better performance with them
- 🟡 **Create database views** for common query patterns
- 🟡 **Prefer `Ecto.Multi`** for complex transactions
- 🔴 Always preload associations when needed (see Ecto Guidelines below)

### Performance Guidelines

#### Database Optimization

- 🟡 Use `explain: true` to analyze query plans when debugging performance
- 🔴 Add indexes for foreign keys and frequently queried fields
- 🔴 Preload associations to avoid N+1 queries
- 🟡 Use `select` to limit fields when possible for large datasets

#### Caching Strategy

- 🟡 Cache expensive computations
- 🟡 Use ETS for process-local cache
- 🟡 Consider Cachex for distributed caching
- 🟡 Set appropriate TTLs

#### When to Optimize

- ⚠️ Don't prematurely optimize - measure first
- 🟡 Profile with `:observer` or `:telemetry`
- 🟡 Focus on hot paths identified by metrics
- 🟡 Optimize database queries before application code

### Phoenix v1.8 Guidelines

- 🔴 **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- 🟡 The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- 🔴 Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- 🔴 Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- 🟡 Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- 🟡 **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available
- 🟡 If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">`), no default classes are inherited, so your custom classes must fully style the input

### JS and CSS Guidelines

- 🟡 **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces
- 🔴 Tailwind CSS v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/my_app_web";
```

- 🔴 **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- 🔴 **Never** use `@apply` when writing raw CSS
- 🟡 **Always** manually write your own Tailwind-based components instead of using daisyUI for a unique, world-class design
- 🔴 Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline `<script>custom js</script>` tags within templates**

### UI/UX & Design Guidelines

- 🟡 **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- 🟢 Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- 🟢 Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- 🟢 Focus on **delightful details** like hover effects, loading states, and smooth page transitions

---

<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Framework-Specific Guidelines

### Elixir Guidelines

- 🟢 **Use explicit list syntax instead of sigils** for simple data lists, but prefer sigils for command-line arguments

  **Always prefer explicit list syntax for data lists**:

```elixir
# Good - explicit and clear for data
truthy_values = ["1", "true", "yes"]
statuses = [:pending, :active, :completed]
error_codes = [400, 401, 403, 404]
```

  **Avoid sigils for simple data lists**:

```elixir
# Avoid - less explicit for data
truthy_values = ~w(1 true yes)
statuses = ~w(pending active completed)a
```

  **Prefer sigils for command-line arguments and shell commands**:

```elixir
# Good - sigils are appropriate for command-line args
args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js)
watchers: [
  esbuild: {Esbuild, :install_and_run, [:events, ~w(--sourcemap=inline --watch)]},
  tailwind: {Tailwind, :install_and_run, [:events, ~w(--watch)]}
]
```

  **Summary**: Use explicit list syntax `["a", "b", "c"]` or `[:a, :b, :c]` for data and configuration values. Use sigils `~w()` for command-line arguments and shell commands.

- 🔴 Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

```elixir
i = 0
mylist = ["blue", "green"]
mylist[i]  # INVALID - will raise error
```

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index-based list access:

```elixir
i = 0
mylist = ["blue", "green"]
Enum.at(mylist, i)  # Correct
```

- 🔴 Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc., you **must** bind the result of the expression to a variable if you want to use it, and you **CANNOT** rebind the result inside the expression:

```elixir
# INVALID: we are rebinding inside the `if` and the result never gets assigned
if connected?(socket) do
  socket = assign(socket, :val, val)
end

# VALID: we rebind the result of the `if` to a new variable
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  end
```

- 🔴 **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- 🔴 **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- 🟡 Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- 🔴 Don't use `String.to_atom/1` on user input (memory leak risk)
- 🟢 Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- 🟡 Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- 🟡 Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as an option

### Mix Guidelines

- 🟡 Read the docs and options before using tasks (by using `mix help task_name`)
- 🟡 To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- 🟢 `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
### Phoenix Guidelines

- 🟡 Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes

- 🟡 You **never** need to create your own `alias` for route definitions! The `scope` provides the alias:

```elixir
scope "/admin", AppWeb.Admin do
  pipe_through :browser

  live "/users", UserLive, :index
end
# The UserLive route points to AppWeb.Admin.UserLive module
```

- 🔴 `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
### Ecto Guidelines

- 🔴 **Always** preload Ecto associations in queries when they'll be accessed in templates (e.g., a message that needs to reference `message.user.email`)
- 🟡 Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- 🟡 `Ecto.Schema` fields always use the `:string` type, even for `:text` columns: `field :name, :string`
- 🟡 `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such an option is never needed
- 🔴 You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- 🔴 Fields which are set programmatically, such as `user_id`, must **not** be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct

#### Ecto Schema Field Type Conventions

**Always** use these field types by default when creating new schemas or migrations:

- 🟡 **citext fields** (case-insensitive text - requires `citext` extension):
  - Text classification: `name`, `type`, `subtype`, `status`, `substatus`
  - Categorization: `category`, `tag`, `subtag`
  - Identifiers: `email`, `url`, `slug`
  - Reasoning: Case-insensitive searches and comparisons without manual lowercasing

- 🟡 **text fields**:
  - `description`, `summary`, `short_description`, `notes`, `content`

- 🟡 **jsonb fields**:
  - `metadata`, `assets`, `assets_metadata`, `settings`, `preferences`

- 🔴 **utc_datetime_usec fields** (any field ending with `_at`):
  - `inserted_at`, `updated_at`, `created_at`, `deleted_at`, `published_at`, `expires_at`

- 🟡 **integer fields**:
  - `count`, `number_of_*`, `price_in_cents`, `amount_in_cents`

- 🟡 **decimal fields**:
  - `price`, `amount`, `balance`, `rate`, `percentage`

- 🟡 **positive_integers** (zero and greater):
  - `number_of_visitors`, `number_of_attendees`, `number_of_people`, `quantity`
  - Use custom validation or database constraints to enforce positive values

**Migration Example**:

```elixir
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
```

#### Soft Delete Conventions

**Always use soft delete for user-facing data**. Hard deletes should be rare and limited to:
- System/internal records
- Truly sensitive data that must be removed
- Cleanup of test/temporary data

**Use the `deleted_fields/1` macro** from `Events.Repo.MigrationMacros`:

```elixir
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
```

**Query conventions**:

```elixir
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
```

**Context function patterns**:

```elixir
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
```

**deleted_fields macro options**:

```elixir
# Both fields (default)
deleted_fields()

# Only timestamp (no audit)
deleted_fields(only: :deleted_at)

# Only audit (unusual)
deleted_fields(only: :deleted_by_urm_id)

# No FK constraints (for early migrations)
deleted_fields(references: false)
```

**Schema Example**:

```elixir
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

    field :deleted_at, :utc_datetime_usec
    field :deleted_by_urm_id, :id

    timestamps(type: :utc_datetime_usec)
  end
end
```
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
### Phoenix HTML Guidelines

- 🔴 Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- 🔴 **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- 🔴 When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- 🟡 **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- 🟡 For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- 🔴 Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

```elixir
<%= if condition do %>
  ...
<% else if other_condition %>
  ...
<% end %>
```

  Instead **always** do this:

```elixir
<%= cond do %>
  <% condition -> %>
    ...
  <% condition2 -> %>
    ...
  <% true -> %>
    ...
<% end %>
```

- 🟡 HEEx requires special tag annotation if you want to insert literal curly braces like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you **must** annotate the parent tag with `phx-no-curly-interpolation`:

```html
<code phx-no-curly-interpolation>
  let obj = {key: "val"}
</code>
```

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- 🟡 HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

```html
<a class={[
  "px-2 text-white",
  @some_flag && "py-5",
  if(@other_condition, do: "border-red-500", else: "border-blue-100"),
  ...
]}>Text</a>
```

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

```html
<a class={
  "px-2 text-white",
  @some_flag && "py-5"
}> ...
=> Raises compile syntax error on invalid HEEx attr syntax
```

- 🔴 **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- 🟡 HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- 🔴 HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

```html
<div id={@id}>
  {@my_assign}
  <%= if @some_block_condition do %>
    {@another_assign}
  <% end %>
</div>
```

  and **Never** do this – the program will terminate with a syntax error:

```html
<%!-- THIS IS INVALID NEVER EVER DO THIS --%>
<div id="<%= @invalid_interpolation %>">
  {if @invalid_block_construct do}
  {end}
</div>
```
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
### Phoenix LiveView Guidelines

- 🔴 **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions in LiveViews
- 🟡 **Avoid LiveComponent's** unless you have a strong, specific need for them
- 🟡 LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- 🔴 Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- 🔴 **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

#### LiveView Streams

- 🟡 **Always** use LiveView streams for collections instead of assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- 🔴 When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

```html
<div id="messages" phx-update="stream">
  <div :for={{id, msg} <- @streams.messages} id={id}>
    {msg.text}
  </div>
</div>
```

- 🔴 LiveView streams are **not** enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

```elixir
def handle_event("filter", %{"filter" => filter}, socket) do
  # re-fetch the messages based on the filter
  messages = list_messages(filter)

  {:noreply,
   socket
   |> assign(:messages_empty?, messages == [])
   # reset the stream with the new messages
   |> stream(:messages, messages, reset: true)}
end
```

- 🟡 LiveView streams **do not support counting or empty states**. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

```html
<div id="tasks" phx-update="stream">
  <div class="hidden only:block">No tasks yet</div>
  <div :for={{id, task} <- @stream.tasks} id={id}>
    {task.name}
  </div>
</div>
```

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- 🔴 **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

#### Form Handling

##### Creating a form from params

If you want to create a form based on `handle_event` params:

```elixir
def handle_event("submitted", params, socket) do
  {:noreply, assign(socket, form: to_form(params))}
end
```

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

```elixir
def handle_event("submitted", %{"user" => user_params}, socket) do
  {:noreply, assign(socket, form: to_form(user_params, as: :user))}
end
```

##### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

```elixir
defmodule MyApp.Users.User do
  use Ecto.Schema
  ...
end
```

And then you create a changeset that you pass to `to_form`:

```elixir
%MyApp.Users.User{}
|> Ecto.Changeset.change()
|> to_form()
```

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form assign can be passed to the `<.form>` function component:

```html
<.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:field]} type="text" />
</.form>
```

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

##### Avoiding form errors

🔴 **Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms like this**:

```html
<%!-- ALWAYS do this (valid) --%>
<.form for={@form} id="my-form">
  <.input field={@form[:field]} type="text" />
</.form>
```

And **never** do this:

```html
<%!-- NEVER do this (invalid) --%>
<.form for={@changeset} id="my-form">
  <.input field={@changeset[:field]} type="text" />
</.form>
```

- 🔴 You are **FORBIDDEN** from accessing the changeset in the template as it will cause errors
- 🔴 **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->

---

## Common Decision Trees

### When to use Ecto vs Raw SQL?

1. **Start with Ecto queries** (composable, safe, maintainable)
2. Profile if performance is insufficient
3. **Switch to raw SQL only if**:
   - Complex joins/aggregations that Ecto makes verbose
   - Proven performance bottleneck via profiling
   - Database-specific features needed (e.g., CTEs, window functions)
4. **Always use parameterized queries** even with raw SQL

### When to create a new Context vs extend existing?

- **New domain concept** → New context
- **Cross-cutting concern** (pagination, caching) → Separate generic context
- **Extension of existing domain** → Extend existing context
- **When uncertain** → Ask for clarification

### When to use `case` vs `cond` vs `with`?

- **`case`** - Pattern matching on a single value
- **`cond`** - Multiple boolean conditions (like if/elsif in other languages)
- **`with`** - Sequential operations that can fail, need early exit on error

```elixir
# Use `case` for pattern matching single value
case user_role do
  :admin -> handle_admin()
  :user -> handle_user()
  _ -> handle_guest()
end

# Use `cond` for multiple boolean conditions
cond do
  age < 13 -> "child"
  age < 18 -> "teen"
  age < 65 -> "adult"
  true -> "senior"
end

# Use `with` for sequential operations
with {:ok, user} <- Users.get_user(id),
     {:ok, order} <- Orders.create_order(user),
     {:ok, payment} <- Payments.process(order) do
  {:ok, order}
end
```

### When to use LiveView streams vs regular assigns?

- **Use streams** for:
  - Large collections (100+ items)
  - Collections that grow over time (chat messages, logs)
  - Real-time updates (append/prepend items)

- **Use regular assigns** for:
  - Small collections (< 100 items)
  - Static data that doesn't change frequently
  - When you need Enum operations (count, filter, map)

---

## Troubleshooting

### "No current_scope assign" error

**Cause**: Route not in proper `live_session` or missing assign

**Fix**:
1. Check route is in authenticated `live_session` block in router
2. Pass `current_scope` to `<Layouts.app>`: `<Layouts.app flash={@flash} current_scope={@current_scope}>`
3. Verify `on_mount` hook is setting `current_scope` assign

### "N+1 query detected" warning

**Cause**: Missing preload for associations accessed in template

**Fix**: Add preload to query:

```elixir
# Bad - N+1 queries
messages = Repo.all(Message)

# Good - preload associations
messages =
  from m in Message,
    preload: [:user, :attachments]
  |> Repo.all()
```

### "Changeset is not enumerable" error

**Cause**: Accessing changeset with `[]` syntax in template

**Fix**: Use `to_form/2` in LiveView and access `@form[:field]` in template:

```elixir
# LiveView
def mount(_params, _session, socket) do
  changeset = MySchema.changeset(%MySchema{}, %{})
  {:ok, assign(socket, form: to_form(changeset))}
end

# Template
<.form for={@form} id="my-form">
  <.input field={@form[:name]} type="text" />
</.form>
```

### Tests failing with "element not found"

**Cause**: Element selector doesn't match actual HTML or element not yet rendered

**Fix**:
1. Add unique `id` attributes to elements in templates
2. Use `LazyHTML` to inspect actual HTML:

```elixir
html = render(view)
document = LazyHTML.from_fragment(html)
matches = LazyHTML.filter(document, "#my-element")
IO.inspect(matches, label: "Matches")
```

3. Wait for async updates: `assert render_async(view) =~ "expected content"`

### `mix precommit` fails

**Cause**: Code doesn't meet quality standards (formatting, Credo, tests)

**Fix**:
1. Run `mix format` to fix formatting issues
2. Address Credo warnings (run `mix credo` for details)
3. Fix failing tests (run `mix test` to see failures)
4. Check compilation warnings

### Database migration fails

**Cause**: Migration has errors or conflicts with existing schema

**Fix**:
1. Check migration file for syntax errors
2. Verify table/column doesn't already exist
3. Ensure foreign key references exist
4. Rollback and fix: `mix ecto.rollback && fix migration && mix ecto.migrate`

---

## Project Glossary

- **URM**: User Role Management - system for managing user permissions and roles (see `deleted_by_urm_id` field)
- **Token Pattern**: Architectural pattern of passing a context struct through a pipeline of functions (like `Plug.Conn`, `Req`, etc.)
- **Soft Delete**: Marking records as deleted with `deleted_at` timestamp instead of removing from database
- **citext**: PostgreSQL case-insensitive text column type extension
- **HEEx**: HTML+EEx, Phoenix's HTML-aware template syntax (`.html.heex` files)
- **LiveView**: Phoenix's real-time, server-rendered framework for building interactive UIs
- **Stream**: LiveView's memory-efficient way to handle large or growing collections
- **Preload**: Eagerly loading Ecto associations to avoid N+1 queries
- **N+1 Query**: Performance anti-pattern where N additional queries are executed for N records
- **Ecto.Multi**: Composable, atomic database transactions

---

## Document Structure Notes

This file contains HTML comment markers (e.g., `<!-- phoenix:elixir-start -->`) for:
- Automated parsing by CI/CD tools
- Section extraction for context-specific prompts
- Version control of guideline changes

**Do not remove these markers.**

---

**Last Updated**: 2025-11-12
