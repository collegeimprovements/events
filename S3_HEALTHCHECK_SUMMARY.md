# S3 Health Check Implementation Summary

## What Was Added

### 1. S3 Service Health Check
Added S3 to the system health monitoring in `lib/events/system_health/services.ex`:

- **Service Entry**: Added S3 as an optional (non-critical) service
- **Health Check Function**: `check_s3/0` - Tests S3 connection by attempting to list objects
- **Context Creation**: `s3_context/0` - Creates S3 context from environment variables
- **Adapter Detection**: `safe_get_s3_adapter/0` - Detects and displays ReqS3 adapter

### 2. S3 Configuration Detection
The health check validates:
- ✅ AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- ✅ AWS region configuration
- ✅ S3 bucket configuration
- ✅ S3 endpoint (for MinIO support)
- ✅ Actual connectivity by listing objects

### 3. Enhanced Infrastructure Display
Updated `lib/events/system_health/infra.ex` to show S3/MinIO connection details:

- Displays endpoint URL
- Shows configured bucket
- Shows region
- Detects MinIO vs AWS S3

### 4. Environment Configuration
Updated `.mise.toml` with S3/MinIO settings:

```toml
AWS_ACCESS_KEY_ID = "arpit"
AWS_SECRET_ACCESS_KEY = "India@2025"
AWS_ENDPOINT_URL_S3 = "http://31.97.231.247:9000"
AWS_REGION = "ap-southeast-1"
AWS_S3_FORCE_PATH_STYLE = "true"
S3_BUCKET = "qms"
```

## How It Works

### Health Check Display

When you run `Events.SystemHealth.display()` or start IEx, you'll see:

```
SERVICES

SERVICE      │ STATUS     │ ADAPTER            │ LEVEL    │ INFO
─────────────┼────────────┼────────────────────┼──────────┼─────────────────
S3           │ ✓ Running  │ ReqS3              │ Optional │ Bucket: qms
```

Or if S3 is not configured/unreachable:

```
SERVICE      │ STATUS     │ ADAPTER            │ LEVEL    │ INFO
─────────────┼────────────┼────────────────────┼──────────┼─────────────────
S3           │ ✗ Failed   │ ReqS3              │ Degraded │ File uploads unavailable
```

### Infrastructure Connections

The INFRA CONNECTIONS section now shows:

```
INFRA CONNECTIONS

● S3 / MinIO
    Endpoint : http://31.97.231.247:9000/qms
    Source   : AWS_* env vars
    Details  : bucket=qms, region=ap-southeast-1, endpoint=http://31.97.231.247:9000
```

## Testing S3 Health

### In IEx

```elixir
# Start IEx (automatically runs health check on startup)
iex -S mix

# Or manually run health check
Events.SystemHealth.display()

# Check S3 status specifically
Events.SystemHealth.services_status()
|> Enum.find(&(&1.name == "S3"))
```

### From Command Line

```bash
# Run health check
mix run -e "Events.SystemHealth.display()"

# Or use shorthand (if you create a mix task)
mix health
```

## S3 Status Conditions

### ✅ Healthy (Green)
- AWS credentials are configured
- S3 bucket is set
- Endpoint is reachable
- Can successfully list objects

**Display**: `✓ Running | Bucket: qms`

### ❌ Degraded (Yellow)
S3 is marked as **optional** (not critical), so failures show as "Degraded":

- Missing credentials → "AWS credentials not configured"
- Missing bucket → "S3 bucket not configured"
- Connection failed → "S3 error (HTTP 403)"
- Network error → Shows error message

**Display**: `✗ Failed | File uploads unavailable`

**Impact**: "File uploads unavailable"

## Environment Variables Required

For S3 health check to pass, you need:

```bash
# Required
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
S3_BUCKET=your-bucket-name  # or AWS_S3_BUCKET

# Optional (defaults shown)
AWS_REGION=ap-southeast-1          # default: us-east-1
AWS_ENDPOINT_URL_S3=http://...     # for MinIO
AWS_S3_FORCE_PATH_STYLE=true       # for MinIO compatibility
```

## Benefits

1. **Visibility**: Instantly see if S3/MinIO is properly configured
2. **Early Detection**: Catch S3 configuration issues before runtime errors
3. **Environment Validation**: Confirms all required env vars are set
4. **Connection Testing**: Actively tests S3 connectivity (not just config check)
5. **MinIO Support**: Works with both AWS S3 and MinIO/compatible services
6. **Non-Breaking**: S3 is optional, so failures don't prevent app startup

## Files Modified

1. `lib/events/system_health/services.ex` - Added S3 health check
2. `lib/events/system_health/infra.ex` - Enhanced S3 connection display
3. `lib/events/services/aws/context.ex` - Added `s3()` helper and `from_env()` support for `S3_BUCKET`
4. `.mise.toml` - Added S3/MinIO configuration

## Files Created

1. `S3_CHEATSHEET.md` - Complete guide for S3 operations
2. `S3_HEALTHCHECK_SUMMARY.md` - This file

## Next Steps

To make S3 health check pass:

1. Ensure your MinIO server is running on `31.97.231.247:9000`
2. Verify the bucket "qms" exists
3. Restart your shell or run `mise trust` to reload env vars
4. Start IEx: `iex -S mix`
5. You should see `S3 | ✓ Running | Bucket: qms`

## Troubleshooting

### "S3 bucket not configured"
- Add `S3_BUCKET=qms` to `.mise.toml`
- Run `mise trust` and restart

### "AWS_ACCESS_KEY_ID not set"
- Check `.mise.toml` has credentials
- Run `mise trust` to apply changes

### "S3 error (HTTP 403)"
- Wrong credentials
- Bucket doesn't exist
- Endpoint unreachable

### "S3 error (HTTP 404)"
- Bucket doesn't exist on the server
- Create the bucket in MinIO console

### Test S3 connection manually:
```elixir
alias Events.Services.Aws.{Context, S3}
ctx = Context.s3() |> Context.with_bucket("qms")
S3.list_objects(ctx, max_keys: 1)
```
