# OmCredo Cheatsheet

> Reusable Credo checks for Elixir best practices. For full docs, see `README.md`.

## Setup (.credo.exs)

```elixir
%{configs: [%{name: "default", checks: [
  {OmCredo.Checks.PreferPatternMatching, []},
  {OmCredo.Checks.NoBangRepoOperations, []},
  {OmCredo.Checks.RequireResultTuples, [paths: ["/lib/myapp/contexts/"]]},
  {OmCredo.Checks.UseEnhancedSchema, []},
  {OmCredo.Checks.UseEnhancedMigration, []},
  {OmCredo.Checks.UseDecorator, [paths: ["/lib/myapp/contexts/"]]}
]}]}
```

---

## Available Checks

| Check | Detects | Suggests |
|-------|---------|----------|
| `PreferPatternMatching` | `if/else` chains, `elem()` checks | `case`, `with`, pattern match |
| `NoBangRepoOperations` | `Repo.insert!`, `Repo.update!` | `Repo.insert`, result tuples |
| `RequireResultTuples` | Functions not returning `{:ok, _}/{:error, _}` | Result tuple returns |
| `UseEnhancedSchema` | `use Ecto.Schema` | `use OmSchema` |
| `UseEnhancedMigration` | `use Ecto.Migration` | `use OmMigration` |
| `UseDecorator` | Missing decorator usage | `use FnDecorator` |

---

## Configuration

```elixir
# Limit to specific paths
{OmCredo.Checks.RequireResultTuples, [
  paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"]
]}

# Exclude paths
{OmCredo.Checks.NoBangRepoOperations, [
  excluded_paths: ["/lib/myapp/seeds.ex"]
]}
```

---

## Run

```bash
mix credo --strict
```
