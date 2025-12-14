# ==============================================================================
# Events Test Helper
# ==============================================================================
#
# This file configures the test environment, including:
# - ExUnit configuration
# - Mocking setup (Mimic)
# - Data generation (Faker)
# - Database sandbox
# - Test exclusions
#
# Run tests with: mix test
# Run specific categories:
#   mix test.unit        - Fast unit tests only
#   mix test.integration - Integration tests
#   mix test.external    - External API tests
#   mix test.properties  - Property-based tests
# ==============================================================================

# ------------------------------------------------------------------------------
# Application Setup
# ------------------------------------------------------------------------------

# Start Faker for test data generation
Faker.start()

# ------------------------------------------------------------------------------
# Mimic Setup - Module Mocking
# ------------------------------------------------------------------------------

# Copy modules that may need to be mocked in tests.
# These modules can then use `expect/3` and `stub/3` in tests.

mockable_modules = [
  # External services
  Events.Services.S3,
  Events.Services.S3.Client,
  Events.Core.Cache,

  # External libraries (only if loaded)
  Redix,
  Req,
  Hammer
]

for module <- mockable_modules do
  if Code.ensure_loaded?(module) do
    Mimic.copy(module)
  end
end

# ------------------------------------------------------------------------------
# ExUnit Configuration
# ------------------------------------------------------------------------------

# Default exclusions - these tests require special setup or are slow
default_exclusions = [
  # Tests that require external network
  :external,
  # Slow tests (> 1 second)
  :slow,
  # Integration tests requiring full app setup
  :integration,
  # Tests that are work-in-progress
  :wip,
  # Pending tests that aren't ready
  :pending
]

# Include all tests in CI, exclude in normal dev
alias FnTypes.Config, as: Cfg
ci? = Cfg.boolean("CI", false)

exclusions =
  if ci? do
    # In CI, only exclude truly broken tests
    [:wip, :pending]
  else
    default_exclusions
  end

ExUnit.configure(
  exclude: exclusions,
  formatters: [ExUnit.CLIFormatter],
  # Fail fast on first failure in CI
  max_failures: if(ci?, do: 10, else: :infinity),
  # Timeout for individual tests (30 seconds)
  timeout: 30_000,
  # Enable colors
  colors: [enabled: true],
  # Show slowest tests
  slowest: if(ci?, do: 10, else: 0),
  # Capture logs by default - only shown on test failure
  # Override per-test with @tag capture_log: false
  capture_log: true
)

ExUnit.start()

# ------------------------------------------------------------------------------
# Database Sandbox
# ------------------------------------------------------------------------------

Ecto.Adapters.SQL.Sandbox.mode(Events.Core.Repo, :manual)

# ------------------------------------------------------------------------------
# Global Test Setup
# ------------------------------------------------------------------------------

# Ensure test environment is properly configured
unless Mix.env() == :test do
  raise "Tests must be run in test environment. Use: MIX_ENV=test mix test"
end
