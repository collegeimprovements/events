# Configuration Reference

The Events application uses a comprehensive configuration validation system that checks all service configurations at startup and displays them in the system health dashboard.

## Configuration Validation

### Startup Behavior

The application validates configurations in two phases:

1. **Critical Validation** (before services start):
   - Runs before the supervision tree starts
   - Validates only critical services (Database, PubSub, Endpoint)
   - **Fails fast** in production/test environments
   - **Logs warnings** and continues in development (better DX)

2. **Full Validation** (after services start):
   - Validates all services (critical + optional)
   - Logs warnings for configuration issues
   - Does not block application startup

### Viewing Configuration Status

Use the health dashboard to see configuration status:

```elixir
# In IEx
iex> SystemHealth.display()
```

Or check specific services:

```elixir
iex> ConfigValidator.validate_service(:database)
{:ok, %{url: "ecto://...", pool_size: 10}}

iex> ConfigValidator.validate_all()
%{
  ok: [...],
  warnings: [...],
  errors: [...],
  disabled: [...]
}
```

---

## Services

### Critical Services

These services **must** be configured correctly for the application to start:

#### Database (PostgreSQL)
**Environment Variables:**
- `DATABASE_URL` - PostgreSQL connection string (required in production)
- `DB_POOL_SIZE` - Connection pool size (default: 10, max: 100)
- `DB_SSL` - Enable SSL connections (default: false)

**Example:**
```bash
DATABASE_URL=ecto://postgres:password@localhost:5432/events_prod
DB_POOL_SIZE=20
DB_SSL=true
```

**Validation Checks:**
- DATABASE_URL is set (production only)
- Connection string is parseable
- Pool size is between 1 and 100

---

### Optional Services

These services can be disabled or partially configured without blocking startup:

#### Cache (Redis/Local)
**Environment Variables:**
- `CACHE_ADAPTER` - Cache backend: "redis", "local", "null" (default: "redis")
- `REDIS_HOST` - Redis hostname (default: "localhost")
- `REDIS_PORT` - Redis port (default: 6379)

**Example:**
```bash
CACHE_ADAPTER=redis
REDIS_HOST=redis.example.com
REDIS_PORT=6379
```

**Validation Checks:**
- Adapter is configured
- Adapter-specific settings are valid

---

#### S3 / MinIO
**Environment Variables:**
- `S3_ENABLED` - Enable/disable S3 service (default: true)
- `AWS_ACCESS_KEY_ID` - AWS access key (required if enabled)
- `AWS_SECRET_ACCESS_KEY` - AWS secret key (required if enabled)
- `S3_BUCKET` - S3 bucket name (optional, warns if not set)
- `AWS_REGION` - AWS region (default: "us-east-1")
- `AWS_ENDPOINT_URL_S3` - Custom S3 endpoint (for MinIO/LocalStack)

**Example (AWS):**
```bash
S3_ENABLED=true
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
S3_BUCKET=my-events-bucket
AWS_REGION=us-west-2
```

**Example (MinIO):**
```bash
S3_ENABLED=true
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_ENDPOINT_URL_S3=http://localhost:9000
S3_BUCKET=events
AWS_REGION=us-east-1
```

**Validation Checks:**
- S3 enabled via KillSwitch
- AWS credentials present
- Bucket configured (warning if not)

---

#### Email (Swoosh)
**Configuration:** Set in `config/runtime.exs`

**Development:**
```elixir
config :events, Events.Infra.Mailer, adapter: Swoosh.Adapters.Local
```

**Test:**
```elixir
config :events, Events.Infra.Mailer, adapter: Swoosh.Adapters.Test
```

**Production (Mailgun):**
```elixir
config :events, Events.Infra.Mailer,
  adapter: Swoosh.Adapters.Mailgun,
  api_key: System.get_env("MAILGUN_API_KEY"),
  domain: System.get_env("MAILGUN_DOMAIN")
```

**Validation Checks:**
- Mailer adapter configured
- Production adapters have credentials

---

#### Stripe
**Environment Variables:**
- `STRIPE_API_KEY` or `STRIPE_SECRET_KEY` - Stripe API key (optional)
- `STRIPE_API_VERSION` - API version (default: "2024-10-28.acacia")

**Example:**
```bash
STRIPE_API_KEY=sk_test_...
STRIPE_API_VERSION=2024-10-28.acacia
```

**Validation Checks:**
- API key present (disabled if not)
- API key format (test vs live mode)

---

#### Scheduler
**Configuration:** Set in `config/config.exs` and `config/runtime.exs`

**Example:**
```elixir
config :events, Events.Infra.Scheduler,
  enabled: true,
  store: :database,
  repo: Events.Core.Repo,
  peer: Events.Infra.Scheduler.Peer.Postgres,
  queues: [
    default: 10,
    realtime: 20
  ]
```

**Validation Checks:**
- Config validates per NimbleOptions schema
- Database store requires repo
- Peer module available

---

## Kill Switch System

Services can be disabled via the Kill Switch system:

**Environment Variables:**
```bash
S3_ENABLED=false        # Disable S3
CACHE_ENABLED=false     # Disable cache
EMAIL_ENABLED=false     # Disable email
```

**Runtime Control:**
```elixir
# Disable service
KillSwitch.disable(:s3, reason: "S3 outage detected")

# Re-enable service
KillSwitch.enable(:s3)

# Check status
KillSwitch.status_all()
```

---

## Health Dashboard

The system health dashboard shows comprehensive configuration status:

```
═══════════════════════════════════════════════════════════════════
                      SYSTEM HEALTH STATUS
═══════════════════════════════════════════════════════════════════

CONFIGURATION
SERVICE      │ STATUS      │ ADAPTER             │ DETAILS
─────────────┼─────────────┼─────────────────────┼──────────────
Database     │ ✓ Valid     │ PostgreSQL          │ Pool: 10, DB: events_dev
Cache        │ ✓ Valid     │ Redis               │ Host: localhost, Port: 6379
S3           │ ⚠ Warning   │ ReqS3               │ Bucket not set (optional service)
Scheduler    │ ✓ Valid     │ Memory              │ Store: memory, Queues: default
Email        │ ✓ Valid     │ Local (dev)         │
Stripe       │ ◯ Disabled  │ -                   │ API key not set (optional service)
═══════════════════════════════════════════════════════════════════
```

---

## Configuration Best Practices

### Development
- Use defaults for quick setup
- Enable local adapters (Local cache, Local mailer)
- Set schema validation to warn but not fail

### Test
- Use test-specific adapters (Swoosh.Adapters.Test)
- Enable schema validation with fail-fast
- Use sandbox mode for database

### Production
- **Always** set required environment variables
- Use managed services (Redis, AWS S3)
- Enable SSL for database connections
- Set appropriate pool sizes
- Configure schema validation to fail on errors

### Environment Management
- Use `mise` or `direnv` for local env vars
- Use secrets management (AWS Secrets Manager, Vault) in production
- Never commit `.env` files with real credentials
- Document all env vars in this file

---

## Troubleshooting

### Application won't start
1. Check logs for "Critical configuration errors"
2. Verify DATABASE_URL is set (production)
3. Check database connectivity

### Services degraded
1. Run `SystemHealth.display()` in IEx
2. Check CONFIGURATION section for warnings/errors
3. Verify optional service env vars
4. Check Kill Switch status

### Configuration changes not taking effect
1. Restart the application
2. Check `config/runtime.exs` for env var names
3. Verify env vars are set in your shell
4. Use `Cfg.present?("VAR_NAME")` to check

---

## API Reference

### ConfigValidator

```elixir
# Validate all services
ConfigValidator.validate_all()
#=> %{ok: [...], warnings: [...], errors: [...], disabled: [...]}

# Validate only critical services (fail fast)
ConfigValidator.validate_critical()
#=> {:ok, results} | {:error, errors}

# Validate specific service
ConfigValidator.validate_service(:database)
#=> {:ok, metadata} | {:error, reason} | {:warning, reason, metadata}
```

### SystemHealth

```elixir
# Display full health dashboard
SystemHealth.display()

# Get raw health data
SystemHealth.check_all()
```

### KillSwitch

```elixir
# Check if service enabled
KillSwitch.enabled?(:s3)

# Disable service
KillSwitch.disable(:s3, reason: "Maintenance")

# Enable service
KillSwitch.enable(:s3)

# Get status
KillSwitch.status(:s3)
KillSwitch.status_all()
```

---

## See Also

- `docs/claude/S3.md` - S3 API reference
- `docs/claude/SCHEDULER.md` - Scheduler configuration
- `config/config.exs` - Compile-time configuration
- `config/runtime.exs` - Runtime configuration
