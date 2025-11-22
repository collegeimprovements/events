#!/usr/bin/env elixir

# Kill Switch Demonstration Script
#
# Run with: mix run lib/events/kill_switch/demo.exs
#
# This script demonstrates all kill switch features

alias Events.KillSwitch

IO.puts("\n=== Kill Switch System Demonstration ===\n")

# 1. Check initial status
IO.puts("1. Initial Service Status:")

KillSwitch.status_all()
|> Enum.each(fn {service, status} ->
  enabled_str = if status.enabled, do: "✓ ENABLED", else: "✗ DISABLED"
  IO.puts("   #{service}: #{enabled_str}")

  if status.reason do
    IO.puts("      Reason: #{status.reason}")
  end
end)

# 2. Test individual service checks
IO.puts("\n2. Individual Service Checks:")

case KillSwitch.check(:s3) do
  :enabled ->
    IO.puts("   S3: ✓ Ready for operations")

  {:disabled, reason} ->
    IO.puts("   S3: ✗ Disabled - #{reason}")
end

case KillSwitch.check(:cache) do
  :enabled ->
    IO.puts("   Cache: ✓ Ready for operations")

  {:disabled, reason} ->
    IO.puts("   Cache: ✗ Disabled - #{reason}")
end

# 3. Test runtime disable
IO.puts("\n3. Testing Runtime Disable:")
IO.puts("   Disabling S3...")
KillSwitch.disable(:s3, reason: "Demo: Testing runtime disable")

case KillSwitch.check(:s3) do
  :enabled ->
    IO.puts("   S3: ✓ Still enabled")

  {:disabled, reason} ->
    IO.puts("   S3: ✗ Successfully disabled - #{reason}")
end

# 4. Test execute pattern
IO.puts("\n4. Testing Execute Pattern:")

result =
  KillSwitch.execute(:s3, fn ->
    IO.puts("   This should not print (S3 disabled)")
    :ok
  end)

case result do
  :ok ->
    IO.puts("   Execute succeeded")

  {:error, {:service_disabled, reason}} ->
    IO.puts("   Execute blocked: #{reason}")
end

# 5. Test fallback pattern
IO.puts("\n5. Testing Fallback Pattern:")

result =
  KillSwitch.with_service(
    :s3,
    fn ->
      IO.puts("   Primary: Uploading to S3")
      :ok
    end,
    fallback: fn ->
      IO.puts("   Fallback: Saving to database instead")
      :ok
    end
  )

IO.puts("   Result: #{inspect(result)}")

# 6. Re-enable service
IO.puts("\n6. Testing Re-enable:")
IO.puts("   Re-enabling S3...")
KillSwitch.enable(:s3)

case KillSwitch.check(:s3) do
  :enabled ->
    IO.puts("   S3: ✓ Successfully re-enabled")

  {:disabled, reason} ->
    IO.puts("   S3: ✗ Still disabled - #{reason}")
end

# 7. Test with enabled service
IO.puts("\n7. Testing with Enabled Service:")

result =
  KillSwitch.execute(:s3, fn ->
    IO.puts("   S3 operation executing...")
    :ok
  end)

IO.puts("   Result: #{inspect(result)}")

# 8. Test Cache kill switch
IO.puts("\n8. Testing Cache Kill Switch:")

if KillSwitch.enabled?(:cache) do
  IO.puts("   Cache enabled - operations will execute")
else
  IO.puts("   Cache disabled - operations will no-op")
end

# 9. Show final status
IO.puts("\n9. Final Service Status:")

KillSwitch.status_all()
|> Enum.each(fn {service, status} ->
  enabled_str = if status.enabled, do: "✓", else: "✗"
  IO.puts("   #{enabled_str} #{service}: #{if status.enabled, do: "enabled", else: status.reason}")
end)

IO.puts("\n=== Demo Complete ===\n")

# Example with pattern matching
IO.puts("\n=== Pattern Matching Examples ===\n")

# Example 1: Simple pattern match
IO.puts("Example 1: Simple pattern match")

case KillSwitch.check(:s3) do
  :enabled ->
    IO.puts("  ✓ S3 is ready")

  {:disabled, reason} ->
    IO.puts("  ✗ S3 is disabled: #{reason}")
end

# Example 2: Multiple services
IO.puts("\nExample 2: Check multiple services")

[:s3, :cache, :email]
|> Enum.each(fn service ->
  status =
    case KillSwitch.check(service) do
      :enabled -> "✓"
      {:disabled, _} -> "✗"
    end

  IO.puts("  #{status} #{service}")
end)

# Example 3: Conditional execution
IO.puts("\nExample 3: Conditional execution")

if KillSwitch.enabled?(:cache) do
  IO.puts("  Caching enabled - storing in cache")
else
  IO.puts("  Caching disabled - skipping cache")
end

IO.puts("\n=== Examples Complete ===\n")
