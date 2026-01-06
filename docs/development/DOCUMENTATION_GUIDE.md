# Documentation Enhancement Guide

This guide provides templates and best practices for enhancing ex_doc documentation across all libraries.

## Current State

Run `elixir analyze_docs.exs` from the project root to see current documentation coverage.

**As of 2025-01-05:**
- **Overall Coverage:** 79% moduledoc, 65% function docs, 34% examples
- **Completed Libraries:** om_behaviours (✅ enhanced with comprehensive examples)

## Documentation Standards

Every library should have:

1. **Module-level @moduledoc** (100% coverage target)
   - Quick Start section
   - Feature list
   - Basic usage examples
   - Configuration examples
   - Real-world examples

2. **Function-level @doc** (80% coverage target)
   - Description of what the function does
   - Parameter descriptions
   - Return value description
   - At least 2-3 examples per public function
   - Real-world usage examples where applicable

3. **Type Specifications** (80% coverage target)
   - @spec for all public functions
   - @type for custom types
   - @typedoc for complex types

4. **Examples** (50% coverage target)
   - Simple examples showing basic usage
   - Complex examples showing advanced patterns
   - Real-world examples from actual use cases

## Documentation Template

### Module-Level Documentation

```elixir
defmodule MyLib.Module do
  @moduledoc """
  One-line summary of what this module does.

  Longer description explaining the purpose, use cases, and design principles.

  ## Features

  - Feature 1 - Description
  - Feature 2 - Description
  - Feature 3 - Description

  ## Quick Start

      # Simple example showing the most common use case
      {:ok, result} = MyLib.Module.main_function(args)

  ## Configuration

      # config/config.exs
      config :my_lib,
        option1: "value",
        option2: :value

  ## Examples

      # Basic usage
      {:ok, result} = MyLib.Module.create(%{name: "example"})

      # With options
      {:ok, result} = MyLib.Module.create(%{name: "example"}, timeout: 5000)

      # Error handling
      case MyLib.Module.create(%{invalid: true}) do
        {:ok, result} -> handle_success(result)
        {:error, reason} -> handle_error(reason)
      end

  ## Real-World Usage

      # Complete example from production use case
      defmodule MyApp.Service do
        def process_data(data) do
          data
          |> MyLib.Module.validate()
          |> MyLib.Module.transform()
          |> MyLib.Module.save()
        end
      end
  """

  # Module code...
end
```

### Function-Level Documentation

```elixir
@doc """
One-line summary of what the function does.

Longer description explaining behavior, edge cases, and when to use this function.

## Parameters

- `param1` - Description of first parameter
- `param2` - Description of second parameter (optional)
- `opts` - Keyword list of options:
  - `:option1` - Description (default: `value`)
  - `:option2` - Description (required)

## Returns

- `{:ok, result}` - Success case description
- `{:error, reason}` - Error case description
  - `:invalid_input` - When input is invalid
  - `:not_found` - When resource not found

## Examples

    # Basic usage
    iex> MyLib.Module.function(arg1, arg2)
    {:ok, result}

    # With options
    iex> MyLib.Module.function(arg1, arg2, timeout: 5000)
    {:ok, result}

    # Error case
    iex> MyLib.Module.function(invalid, arg2)
    {:error, :invalid_input}

## Real-World Usage

    # Production example
    defmodule MyApp.Worker do
      def perform(job) do
        case MyLib.Module.function(job.data, job.params) do
          {:ok, result} ->
            Logger.info("Job completed: \#{result}")
            {:ok, result}

          {:error, reason} ->
            Logger.error("Job failed: \#{reason}")
            retry_job(job)
        end
      end
    end
"""
@spec function(param1 :: type1(), param2 :: type2(), opts :: keyword()) ::
        {:ok, result_type()} | {:error, atom()}
def function(param1, param2, opts \\\\ []) do
  # Implementation
end
```

### Callback Documentation

```elixir
@doc """
Callback description.

Explain when this callback is invoked, what it should return, and any side effects.

## Parameters

- `context` - Description

## Returns

Expected return value(s) and their meanings.

## Examples

    defmodule MyImpl do
      @behaviour MyBehaviour

      @impl true
      def callback_name(context) do
        # Implementation showing typical usage
        {:ok, result}
      end
    end
"""
@callback callback_name(context :: map()) :: {:ok, term()} | {:error, term()}
```

## Priority Libraries Needing Enhancement

Based on documentation analysis, prioritize these libraries:

### 1. om_credo (CRITICAL)
- **Current:** 46% moduledoc, 0% function docs, 0% examples
- **Files:** 6 check modules in `libs/om_credo/lib/om_credo/checks/`
- **Action:** Add @doc to all check modules with examples of violations and fixes

### 2. om_middleware (HIGH)
- **Current:** 33% moduledoc, 68% docs, needs more examples
- **Files:** 3 files in `libs/om_middleware/lib/`
- **Action:** Add @moduledoc to middleware implementations, add more examples

### 3. om_ttyd (HIGH)
- **Current:** 100% moduledoc, 51% docs, 6% examples
- **Files:** 4 files in `libs/om_ttyd/lib/`
- **Action:** Add examples to all public functions

### 4. om_health (MEDIUM)
- **Current:** 80% moduledoc, 144% docs, 0% examples
- **Files:** 5 files in `libs/om_health/lib/`
- **Action:** Add example sections showing health check implementations

### 5. om_scheduler (MEDIUM)
- **Current:** 72% moduledoc, 58% docs, 7% examples
- **Files:** ~102 files (large library)
- **Action:** Focus on main modules first (Job, Cron, Registry, Workflow)

### 6. fn_decorator (MEDIUM)
- **Current:** 54% moduledoc, 48% docs, 28% examples
- **Files:** 67 files (very large)
- **Action:** Focus on commonly used decorators first

### 7. fn_types (MEDIUM)
- **Current:** 125% moduledoc, 54% docs, 46% examples
- **Files:** 68 files
- **Action:** Add more function-level examples to core modules (Result, Maybe, Pipeline, AsyncResult)

## Enhancement Process

For each library:

1. **Survey Current State**
   ```bash
   # Find all source files
   find libs/LIBRARY_NAME/lib -name "*.ex" | wc -l

   # Check current doc coverage
   grep -r "@doc" libs/LIBRARY_NAME/lib | wc -l
   grep -r "## Examples" libs/LIBRARY_NAME/lib | wc -l
   ```

2. **Prioritize Files**
   - Start with the main module (usually `lib/library_name.ex`)
   - Then core functionality modules
   - Then helper/utility modules
   - Test support modules last

3. **Add Documentation**
   - Follow templates above
   - Add at least 2-3 examples per public function
   - Include error cases
   - Add real-world usage examples

4. **Verify**
   ```bash
   # Re-run analysis
   elixir analyze_docs.exs

   # Generate docs locally
   cd libs/LIBRARY_NAME
   mix docs
   open doc/index.html
   ```

## Quick Wins

Start with these small libraries for quick improvement:

- **om_behaviours** ✅ (DONE - 4 files)
- **om_middleware** (3 files)
- **om_ttyd** (4 files)
- **om_google** (3 files) - already good, needs minor additions
- **om_stripe** (2 files) - already good, needs minor additions
- **om_typst** (1 file) - already excellent

## Batch Enhancement Script

Use this script to enhance multiple functions at once:

```bash
#!/bin/bash
# enhance_docs.sh

LIBRARY=$1

if [ -z "$LIBRARY" ]; then
  echo "Usage: ./enhance_docs.sh <library_name>"
  echo "Example: ./enhance_docs.sh om_middleware"
  exit 1
fi

LIB_PATH="libs/$LIBRARY"

if [ ! -d "$LIB_PATH" ]; then
  echo "Error: Library $LIBRARY not found at $LIB_PATH"
  exit 1
fi

echo "Enhancing documentation for $LIBRARY..."
echo "Files to enhance:"
find "$LIB_PATH/lib" -name "*.ex" -type f

echo ""
echo "Current coverage:"
echo "- @moduledoc: $(grep -r "@moduledoc" $LIB_PATH/lib | wc -l | tr -d ' ')"
echo "- @doc: $(grep -r "^  @doc" $LIB_PATH/lib | wc -l | tr -d ' ')"
echo "- Examples: $(grep -r "## Examples" $LIB_PATH/lib | wc -l | tr -d ' ')"
echo "- @spec: $(grep -r "@spec" $LIB_PATH/lib | wc -l | tr -d ' ')"

echo ""
echo "Next steps:"
echo "1. Open each file in your editor"
echo "2. Add @doc to functions missing documentation"
echo "3. Add '## Examples' sections with 2-3 examples"
echo "4. Add @spec for type safety"
echo "5. Re-run: elixir analyze_docs.exs"
```

## Example: Enhanced om_behaviours

The `om_behaviours` library has been enhanced as a reference example. Check these files:

- `libs/om_behaviours/lib/om_behaviours/adapter.ex` - Comprehensive adapter documentation
- `libs/om_behaviours/lib/om_behaviours/service.ex` - Service pattern examples
- `libs/om_behaviours/lib/om_behaviours/builder.ex` - Builder pattern with fluent API examples

Key improvements:
- Added detailed parameter descriptions
- Added return value documentation
- Added 2-4 examples per function showing different use cases
- Added real-world usage sections
- Added error handling examples

## Continuous Improvement

Add this to your CI/CD:

```yaml
# .github/workflows/docs.yml
name: Documentation Quality

on: [pull_request]

jobs:
  check-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      - run: elixir analyze_docs.exs
      - run: |
          # Fail if coverage drops below thresholds
          # TODO: Parse output and check percentages
```

## Resources

- [Elixir Documentation Best Practices](https://hexdocs.pm/elixir/writing-documentation.html)
- [ExDoc Documentation](https://hexdocs.pm/ex_doc/readme.html)
- [Writing Great Documentation](https://hexdocs.pm/elixir/writing-documentation.html#recommendations)

## Checklist

Before marking a library as "fully documented":

- [ ] All modules have @moduledoc with examples
- [ ] All public functions have @doc with examples
- [ ] All public functions have @spec
- [ ] At least 50% of functions have 2+ examples
- [ ] README.md is comprehensive
- [ ] Generated docs (mix docs) render correctly
- [ ] Examples are tested (or marked with `# =>` for expected output)
