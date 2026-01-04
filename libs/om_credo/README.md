# OmCredo

Reusable Credo checks for enforcing Elixir best practices and project conventions.

## Installation

```elixir
def deps do
  [
    {:om_credo, "~> 0.1.0", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
  ]
end
```

## Quick Start

Add checks to your `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: [
        # Pattern matching over if/else
        {OmCredo.Checks.PreferPatternMatching, []},

        # No Repo.insert!, etc.
        {OmCredo.Checks.NoBangRepoOperations, []},

        # Result tuples in context modules
        {OmCredo.Checks.RequireResultTuples, [
          paths: ["/lib/myapp/contexts/"]
        ]},

        # Use OmSchema instead of Ecto.Schema
        {OmCredo.Checks.UseEnhancedSchema, []},

        # Use OmMigration instead of Ecto.Migration
        {OmCredo.Checks.UseEnhancedMigration, []},

        # Encourage decorator usage
        {OmCredo.Checks.UseDecorator, [
          paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"]
        ]}
      ]
    }
  ]
}
```

## Available Checks

| Check | Category | Priority | Purpose |
|-------|----------|----------|---------|
| `PreferPatternMatching` | Readability | Low | Encourage pattern matching over if/else |
| `NoBangRepoOperations` | Warning | High | Prevent Repo.insert!, update!, etc. |
| `RequireResultTuples` | Design | Normal | Ensure functions return result tuples |
| `UseEnhancedSchema` | Consistency | High | Use OmSchema instead of Ecto.Schema |
| `UseEnhancedMigration` | Consistency | High | Use OmMigration instead of Ecto.Migration |
| `UseDecorator` | Design | Normal | Encourage decorator usage |

---

## Check Details

### PreferPatternMatching

Detects if/else chains that should use pattern matching.

#### Why This Matters

Pattern matching:
- Is more declarative and readable
- Leverages Elixir's core strength
- Enables exhaustiveness checking
- Reduces nested conditionals

#### Detected Patterns

```elixir
# FLAGGED: if with elem() check
def process(result) do
  if elem(result, 0) == :ok do
    elem(result, 1)
  else
    {:error, :failed}
  end
end

# FLAGGED: Nested if/else
def check(value) do
  if value > 0 do
    :positive
  else
    if value < 0 do
      :negative
    else
      :zero
    end
  end
end
```

#### Preferred Alternatives

```elixir
# Use function clauses
def process({:ok, value}), do: value
def process({:error, _}), do: {:error, :failed}

# Use case
def process(result) do
  case result do
    {:ok, value} -> value
    {:error, _} -> {:error, :failed}
  end
end

# Use cond for multiple conditions
def check(value) do
  cond do
    value > 0 -> :positive
    value < 0 -> :negative
    true -> :zero
  end
end
```

#### Configuration

```elixir
{OmCredo.Checks.PreferPatternMatching, [
  paths: ["/lib/"]  # Only check files in these paths
]}
```

---

### NoBangRepoOperations

Prevents bang (!) Repo operations in application code.

#### Why This Matters

Bang operations raise exceptions on failure, which:
- Bypasses result tuple error handling patterns
- Makes error recovery difficult
- Can crash processes unexpectedly

#### Detected Operations

```elixir
Repo.insert!(changeset)   # Use Repo.insert
Repo.update!(changeset)   # Use Repo.update
Repo.delete!(record)      # Use Repo.delete
Repo.get!(User, id)       # Use Repo.get
Repo.get_by!(User, email: email)  # Use Repo.get_by
Repo.one!(query)          # Use Repo.one
Repo.all!(query)          # Use Repo.all
```

#### Correct Usage

```elixir
# Instead of:
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert!()
end

# Do:
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# Then handle the result:
case create_user(attrs) do
  {:ok, user} -> {:ok, user}
  {:error, changeset} -> {:error, changeset}
end
```

#### Configuration

```elixir
{OmCredo.Checks.NoBangRepoOperations, [
  # Repo module aliases to detect
  repo_modules: [[:Repo], [:MyApp, :Repo]],

  # Paths to exclude (tests, seeds, migrations)
  excluded_paths: [
    "/test/",
    "/priv/repo/seeds",
    "/priv/repo/migrations/",
    "_test.exs"
  ],

  # Paths to check
  included_paths: ["/lib/"]
]}
```

#### Exceptions

Bang operations are acceptable in:
- Test files
- Seed files
- Migration files
- Scripts
- Functions that are themselves bang functions (e.g., `get_user!`)

---

### RequireResultTuples

Ensures public functions in context/service modules have @spec with result tuples.

#### Why This Matters

Result tuples (`{:ok, value} | {:error, reason}`) provide:
- Explicit error handling
- Composable operations with `with` statements
- Clear function contracts
- Better debugging

#### What Gets Flagged

```elixir
# FLAGGED: Public function without @spec
def get_user(id) do
  Repo.get(User, id)
end

# FLAGGED: @spec without result tuple
@spec find_user(binary()) :: User.t() | nil
def find_user(id), do: Repo.get(User, id)
```

#### Correct Usage

```elixir
@spec get_user(binary()) :: {:ok, User.t()} | {:error, :not_found}
def get_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end

@spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end
```

#### Configuration

```elixir
{OmCredo.Checks.RequireResultTuples, [
  # Paths to check
  paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"],

  # File patterns to check
  path_patterns: ["_context.ex", "_service.ex"],

  # Functions to exclude
  excluded_functions: [:changeset, :base_changeset, :validate, :apply_validations],

  # Function prefixes to exclude
  excluded_prefixes: ["_", "handle_"]
]}
```

---

### UseEnhancedSchema

Ensures schemas use OmSchema instead of raw Ecto.Schema.

#### Why This Matters

Enhanced Schema modules provide:
- UUIDv7 primary keys
- Enhanced field validation
- Field group macros (type_fields, status_fields, etc.)
- Automatic changeset helpers

#### Detected Pattern

```elixir
# FLAGGED
defmodule MyApp.User do
  use Ecto.Schema  # Should use OmSchema
end
```

#### Correct Usage

```elixir
defmodule MyApp.User do
  use OmSchema

  schema "users" do
    field :name, :string
    field :email, :string

    type_fields()      # Adds type, subtype
    status_fields()    # Adds status, substatus
    audit_fields()     # Adds created_by, updated_by
    timestamps()
  end
end
```

#### Configuration

```elixir
{OmCredo.Checks.UseEnhancedSchema, [
  # Your enhanced schema module
  enhanced_module: OmSchema,

  # The raw module to detect
  raw_module: Ecto.Schema,

  # Paths to check
  included_paths: ["/lib/"],

  # Paths to exclude (e.g., the schema module itself)
  excluded_paths: ["/lib/om_schema/"]
]}
```

---

### UseEnhancedMigration

Ensures migrations use OmMigration instead of raw Ecto.Migration.

#### Why This Matters

Enhanced Migration modules provide:
- Pipeline-based table creation
- Standard field builders (with_uuid_primary_key, with_audit, etc.)
- DSL-enhanced macros for common patterns
- Consistent index and constraint creation

#### Detected Pattern

```elixir
# FLAGGED
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration  # Should use OmMigration
end
```

#### Correct Usage

```elixir
defmodule MyApp.Repo.Migrations.CreateUsers do
  use OmMigration

  def change do
    create_table(:users)
    |> with_uuid_primary_key()
    |> with_field(:name, :string, null: false)
    |> with_field(:email, :string, null: false)
    |> with_type_fields()
    |> with_status_fields()
    |> with_audit_fields()
    |> with_timestamps()
    |> with_unique_index([:email])
    |> execute_create()
  end
end
```

#### Configuration

```elixir
{OmCredo.Checks.UseEnhancedMigration, [
  # Your enhanced migration module
  enhanced_module: OmMigration,

  # The raw module to detect
  raw_module: Ecto.Migration,

  # Migration paths to check
  migration_paths: ["/priv/repo/migrations/"]
]}
```

---

### UseDecorator

Encourages decorator usage in context and service modules.

#### Why This Matters

Decorator systems provide:
- Type contracts with `@decorate returns_result(...)`
- Automatic telemetry with `@decorate telemetry_span(...)`
- Caching with `@decorate cacheable(...)`
- Validation with `@decorate validate_schema(...)`

#### Detected Pattern

```elixir
# FLAGGED: No decorator module used
defmodule MyApp.Accounts do
  def get_user(id) do
    # No decorators - missing type contract, telemetry
  end
end
```

#### Correct Usage

```elixir
defmodule MyApp.Accounts do
  use FnDecorator

  @decorate returns_result(ok: User.t(), error: :atom)
  @decorate telemetry_span([:my_app, :accounts, :get_user])
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @decorate returns_result(ok: User.t(), error: Changeset.t())
  @decorate telemetry_span([:my_app, :accounts, :create_user])
  @decorate cacheable(cache: MyApp.Cache, key: {:user, :email, email})
  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end
end
```

#### Configuration

```elixir
{OmCredo.Checks.UseDecorator, [
  # The decorator module to look for
  decorator_module: FnDecorator,

  # Paths to check
  paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"],

  # File patterns to check
  path_patterns: ["_context.ex", "_service.ex"]
]}
```

---

## Full Configuration Example

Here's a complete `.credo.exs` configuration:

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Standard Credo checks
          {Credo.Check.Consistency.TabsOrSpaces, []},
          {Credo.Check.Readability.MaxLineLength, [max_length: 120]},

          # OmCredo checks
          {OmCredo.Checks.PreferPatternMatching, [
            paths: ["/lib/"]
          ]},

          {OmCredo.Checks.NoBangRepoOperations, [
            repo_modules: [[:Repo], [:MyApp, :Repo]],
            excluded_paths: ["/test/", "/priv/", "_test.exs"],
            included_paths: ["/lib/"]
          ]},

          {OmCredo.Checks.RequireResultTuples, [
            paths: ["/lib/my_app/"],
            path_patterns: ["_context.ex", "_service.ex"],
            excluded_functions: [:changeset, :validate],
            excluded_prefixes: ["_", "handle_"]
          ]},

          {OmCredo.Checks.UseEnhancedSchema, [
            enhanced_module: OmSchema,
            raw_module: Ecto.Schema,
            included_paths: ["/lib/"],
            excluded_paths: []
          ]},

          {OmCredo.Checks.UseEnhancedMigration, [
            enhanced_module: OmMigration,
            raw_module: Ecto.Migration,
            migration_paths: ["/priv/repo/migrations/"]
          ]},

          {OmCredo.Checks.UseDecorator, [
            decorator_module: FnDecorator,
            paths: ["/lib/my_app/contexts/", "/lib/my_app/services/"],
            path_patterns: ["_context.ex", "_service.ex"]
          ]}
        ]
      }
    }
  ]
}
```

## Running Checks

```bash
# Run all Credo checks
mix credo

# Run with strict mode
mix credo --strict

# Run specific check
mix credo --checks OmCredo.Checks.NoBangRepoOperations

# Explain a specific issue
mix credo explain OmCredo.Checks.PreferPatternMatching
```

## License

MIT
