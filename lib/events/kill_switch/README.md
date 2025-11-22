# Kill Switch System

Centralized kill switch system for gracefully handling external service outages.

## Overview

The kill switch system allows you to disable external services (S3, Cache, Email, Database) either via configuration or at runtime, enabling graceful degradation when services are unavailable.

## Supported Services

- **:s3** - AWS S3 storage
- **:cache** - Redis/Local cache
- **:database** - PostgreSQL database
- **:email** - Email service (Swoosh)

## Configuration

### Via Environment Variables

```bash
# Disable S3
S3_ENABLED=false

# Disable cache
CACHE_ENABLED=false

# Disable email
EMAIL_ENABLED=false

# Disable database (USE WITH CAUTION!)
DATABASE_ENABLED=false
```

### Via Application Config

In `config/runtime.exs`:

```elixir
config :events, Events.KillSwitch,
  s3: true,        # Enable S3
  cache: true,     # Enable cache
  database: true,  # Enable database
  email: false     # Disable email
```

## Usage Patterns

### 1. Simple Check Pattern

```elixir
if KillSwitch.enabled?(:s3) do
  S3.upload(bucket, key, content)
else
  Logger.warning("S3 disabled, skipping upload")
  {:error, :service_disabled}
end
```

### 2. Pattern Matching Pattern

```elixir
case KillSwitch.check(:s3) do
  :enabled ->
    S3.upload(bucket, key, content)

  {:disabled, reason} ->
    Logger.warning("S3 disabled: #{reason}")
    {:error, {:service_disabled, reason}}
end
```

### 3. Execute with Auto-Error Pattern

```elixir
KillSwitch.execute(:s3, fn ->
  S3.upload(bucket, key, content)
end)
# Returns :ok or {:error, {:service_disabled, reason}}
```

### 4. Fallback Pattern

```elixir
KillSwitch.with_service(:s3,
  fn -> S3.upload(bucket, key, content) end,
  fallback: fn -> DbStorage.save(key, content) end
)
```

## Service-Specific Wrappers

### S3 Kill Switch

```elixir
alias Events.KillSwitch.S3, as: S3KS

# Check if enabled
S3KS.enabled?()
#=> true or false

# List with fallback
S3KS.list("my-bucket",
  prefix: "uploads/",
  fallback: fn -> {:ok, %{files: [], next_token: nil}} end
)

# Upload with fallback
S3KS.upload("my-bucket", "photo.jpg", content,
  type: "image/jpeg",
  fallback: fn -> DbStorage.save("photo.jpg", content) end
)

# Download with fallback
S3KS.download("my-bucket", "photo.jpg",
  fallback: fn -> DbStorage.fetch("photo.jpg") end
)

# Delete with fallback
S3KS.delete("my-bucket", "old-file.txt",
  fallback: fn -> DbStorage.delete("old-file.txt") end
)

# Exists with fallback (default: false)
S3KS.exists?("my-bucket", "photo.jpg",
  fallback: fn -> DbStorage.exists?("photo.jpg") end
)

# Generate presigned URLs with fallback
S3KS.url_for_upload("my-bucket", "photo.jpg",
  expires: 300,
  fallback: fn -> {:ok, "/api/upload/photo.jpg"} end
)

S3KS.url_for_download("my-bucket", "photo.jpg",
  expires: 3600,
  fallback: fn -> {:ok, "/api/download/photo.jpg"} end
)
```

### Cache Kill Switch

```elixir
alias Events.KillSwitch.Cache, as: CacheKS

# Check if enabled
CacheKS.enabled?()
#=> true or false

# Get (returns nil if disabled)
CacheKS.get({User, 123})
#=> %User{} or nil

# Put (no-op if disabled)
CacheKS.put({User, 123}, user, ttl: :timer.hours(1))
#=> :ok

# Delete (no-op if disabled)
CacheKS.delete({User, 123})
#=> :ok

# Fetch with computation (always computes if disabled)
CacheKS.fetch({User, id}, fn ->
  Repo.get(User, id)
end, ttl: :timer.hours(1))
#=> %User{}

# Has key? (returns false if disabled)
CacheKS.has_key?({User, 123})
#=> true or false

# Get all (returns [] if disabled)
CacheKS.get_all([{User, 1}, {User, 2}])
#=> [%User{}, %User{}] or []
```

## Runtime Control

### Disable a Service

```elixir
# Disable S3 with reason
KillSwitch.disable(:s3, reason: "S3 outage detected at #{DateTime.utc_now()}")
#=> :ok

# Disable without reason
KillSwitch.disable(:cache)
#=> :ok
```

### Enable a Service

```elixir
KillSwitch.enable(:s3)
#=> :ok
```

### Check Status

```elixir
# Single service
KillSwitch.status(:s3)
#=> %{
#     enabled: false,
#     reason: "S3 outage detected",
#     disabled_at: ~U[2024-01-15 10:30:00Z]
#   }

# All services
KillSwitch.status_all()
#=> %{
#     s3: %{enabled: true, reason: nil, disabled_at: nil},
#     cache: %{enabled: false, reason: "Redis down", disabled_at: ~U[...]},
#     database: %{enabled: true, reason: nil, disabled_at: nil},
#     email: %{enabled: false, reason: "Manually disabled", disabled_at: ~U[...]}
#   }
```

## Real-World Examples

### Example 1: S3 Outage Handling

```elixir
defmodule MyApp.FileUploader do
  alias Events.KillSwitch.S3

  def upload_file(bucket, path, content) do
    S3.upload(bucket, path, content,
      type: MIME.from_path(path),
      fallback: fn ->
        # Fall back to database storage
        Logger.warning("S3 unavailable, storing in database")

        with :ok <- DbStorage.save(path, content) do
          :ok
        end
      end
    )
  end

  def get_file(bucket, path) do
    S3.download(bucket, path,
      fallback: fn ->
        Logger.info("S3 unavailable, fetching from database")
        DbStorage.fetch(path)
      end
    )
  end
end
```

### Example 2: Cache Degradation

```elixir
defmodule MyApp.UserService do
  alias Events.{Repo, KillSwitch}

  def get_user(id) do
    # Use cache if available, otherwise go straight to DB
    KillSwitch.Cache.fetch({User, id}, fn ->
      Repo.get(User, id)
    end, ttl: :timer.hours(1))
  end

  def update_user(id, attrs) do
    with {:ok, user} <- Repo.update(User, id, attrs) do
      # Invalidate cache (no-op if cache disabled)
      KillSwitch.Cache.delete({User, id})
      {:ok, user}
    end
  end
end
```

### Example 3: Email Fallback

```elixir
defmodule MyApp.Notifier do
  alias Events.KillSwitch

  def send_notification(user, message) do
    KillSwitch.with_service(:email,
      fn ->
        email = build_email(user, message)
        Mailer.deliver(email)
      end,
      fallback: fn ->
        # Log to database for manual review
        Logger.warning("Email service disabled, logging notification")

        NotificationLog.create(%{
          user_id: user.id,
          message: message,
          sent_at: nil,
          status: :pending
        })

        :ok
      end
    )
  end
end
```

### Example 4: Health Check Integration

```elixir
defmodule MyApp.HealthCheck do
  alias Events.KillSwitch

  def check_services do
    KillSwitch.status_all()
    |> Enum.map(fn {service, status} ->
      health =
        case status do
          %{enabled: true} -> :healthy
          %{enabled: false, reason: reason} -> {:degraded, reason}
        end

      {service, health}
    end)
    |> Map.new()
  end

  def overall_health do
    statuses = check_services()

    cond do
      all_enabled?(statuses) -> :healthy
      database_disabled?(statuses) -> :unhealthy
      true -> :degraded
    end
  end

  defp all_enabled?(statuses) do
    Enum.all?(statuses, fn {_service, health} -> health == :healthy end)
  end

  defp database_disabled?(statuses) do
    case statuses[:database] do
      {:degraded, _} -> true
      _ -> false
    end
  end
end
```

### Example 5: Automatic Circuit Breaker

```elixir
defmodule MyApp.CircuitBreaker do
  alias Events.KillSwitch
  require Logger

  def monitor_s3 do
    case check_s3_health() do
      :ok ->
        # S3 is healthy, ensure it's enabled
        if not KillSwitch.enabled?(:s3) do
          Logger.info("S3 recovered, re-enabling")
          KillSwitch.enable(:s3)
        end

      {:error, reason} ->
        # S3 is down, disable it
        if KillSwitch.enabled?(:s3) do
          Logger.error("S3 health check failed: #{inspect(reason)}")
          KillSwitch.disable(:s3, reason: "Health check failed: #{inspect(reason)}")
        end
    end
  end

  defp check_s3_health do
    bucket = System.get_env("S3_BUCKET")

    case SimpleS3.list(bucket, limit: 1) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end

# In your application, schedule this:
# :timer.apply_interval(:timer.minutes(5), MyApp.CircuitBreaker, :monitor_s3, [])
```

## Integration with Existing Code

### Option 1: Gradual Migration

Keep existing code, add kill switch layer:

```elixir
# Old code
S3.upload(bucket, key, content)

# New code with kill switch
KillSwitch.S3.upload(bucket, key, content,
  fallback: fn -> {:error, :s3_disabled} end
)
```

### Option 2: Service Modules

Create service modules that handle kill switch logic:

```elixir
defmodule MyApp.Storage do
  alias Events.KillSwitch.S3

  def store(key, content) do
    S3.upload(bucket(), key, content,
      fallback: fn -> store_locally(key, content) end
    )
  end

  def fetch(key) do
    S3.download(bucket(), key,
      fallback: fn -> fetch_locally(key) end
    )
  end

  defp bucket, do: System.get_env("S3_BUCKET")
  defp store_locally(key, content), do: File.write(local_path(key), content)
  defp fetch_locally(key), do: File.read(local_path(key))
  defp local_path(key), do: Path.join(["/tmp/storage", key])
end
```

## Best Practices

1. **Always provide fallbacks for critical operations**
   ```elixir
   # Good
   KillSwitch.S3.upload(bucket, key, content,
     fallback: fn -> DbStorage.save(key, content) end
   )

   # Bad (error if S3 disabled)
   KillSwitch.S3.upload(bucket, key, content)
   ```

2. **Use cache kill switch for graceful degradation**
   ```elixir
   # Cache is optional, so no fallback needed
   KillSwitch.Cache.put(key, value)
   KillSwitch.Cache.get(key)  # Returns nil if disabled
   ```

3. **Never disable database without fallback plan**
   ```elixir
   # Database is critical - only disable if you have a backup
   # Most applications should NOT use database kill switch
   ```

4. **Log kill switch actions**
   ```elixir
   case KillSwitch.check(:s3) do
     :enabled -> :ok
     {:disabled, reason} ->
       Logger.warning("S3 operation skipped: #{reason}")
   end
   ```

5. **Monitor service status**
   ```elixir
   # Add to your telemetry/metrics
   def metrics do
     KillSwitch.status_all()
     |> Enum.map(fn {service, %{enabled: enabled}} ->
       value = if enabled, do: 1, else: 0
       Metrics.gauge("kill_switch.#{service}.enabled", value)
     end)
   end
   ```

## Troubleshooting

### Service won't disable

```elixir
# Check if KillSwitch GenServer is running
Process.whereis(Events.KillSwitch)
#=> #PID<0.XXX.0> or nil

# If nil, GenServer not started - check application supervision tree
```

### Configuration not taking effect

```elixir
# Check current configuration
KillSwitch.status_all()

# Environment variables override config
System.get_env("S3_ENABLED")

# To force enable despite env var:
KillSwitch.enable(:s3)
```

### Fallback not executing

```elixir
# Ensure fallback is a function
KillSwitch.S3.upload(bucket, key, content,
  fallback: fn -> alternative_action() end  # Correct
)

# NOT this:
KillSwitch.S3.upload(bucket, key, content,
  fallback: alternative_action()  # Wrong - executes immediately
)
```

## Testing

```elixir
defmodule MyAppTest do
  use ExUnit.Case
  alias Events.KillSwitch

  setup do
    # Disable S3 for tests
    KillSwitch.disable(:s3, reason: "Test environment")

    on_exit(fn ->
      # Re-enable after test
      KillSwitch.enable(:s3)
    end)
  end

  test "handles S3 outage gracefully" do
    # S3 is disabled, should use fallback
    result = MyApp.upload_file("test.txt", "content")
    assert result == :ok
    assert DbStorage.exists?("test.txt")
  end
end
```
