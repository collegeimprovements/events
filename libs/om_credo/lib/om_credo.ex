defmodule OmCredo do
  @moduledoc """
  Reusable Credo checks for Elixir best practices.

  Provides configurable checks for:
  - Pattern matching over conditionals
  - Avoiding bang Repo operations
  - Requiring result tuple returns
  - Using enhanced Schema modules
  - Using enhanced Migration modules
  - Using decorator systems

  ## Configuration

  Configure checks in your `.credo.exs`:

      %{
        configs: [
          %{
            checks: [
              {OmCredo.Checks.PreferPatternMatching, []},
              {OmCredo.Checks.NoBangRepoOperations, [repo_modules: [:Repo, :MyApp.Repo]]},
              {OmCredo.Checks.RequireResultTuples, [paths: ["/lib/myapp/contexts/"]]},
              {OmCredo.Checks.UseEnhancedSchema, [
                enhanced_module: MyApp.Schema,
                raw_module: Ecto.Schema
              ]},
              {OmCredo.Checks.UseEnhancedMigration, [
                enhanced_module: MyApp.Migration,
                raw_module: Ecto.Migration
              ]},
              {OmCredo.Checks.UseDecorator, [
                decorator_module: MyApp.Decorator,
                paths: ["/lib/myapp/contexts/", "/lib/myapp/services/"]
              ]}
            ]
          }
        ]
      }

  ## Available Checks

  | Check | Purpose |
  |-------|---------|
  | `PreferPatternMatching` | Encourage pattern matching over if/else |
  | `NoBangRepoOperations` | Prevent Repo.insert!, etc. in app code |
  | `RequireResultTuples` | Ensure public functions have @spec with result tuples |
  | `UseEnhancedSchema` | Ensure enhanced Schema module usage |
  | `UseEnhancedMigration` | Ensure enhanced Migration module usage |
  | `UseDecorator` | Encourage decorator usage in service modules |
  """
end
