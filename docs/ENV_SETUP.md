# Environment Configuration Guide

This project uses **mise** (formerly rtx) for managing environment variables and tool versions.

## Quick Start

### Development (Default)

The `.mise.toml` file contains development defaults. Just run:

```bash
cd /path/to/events
mise install  # Install required tools (Elixir, Erlang, PostgreSQL)
mise trust    # Trust the .mise.toml file
```

Your development environment is now configured with:
- Database: `ecto://emd:Emd@123@localhost:5434/nitro`
- Port: `4000`
- Log Level: `debug`

### Local Overrides (Optional)

Create `.env.local` to override any development settings without modifying `.mise.toml`:

```bash
# .env.local (gitignored)
export DATABASE_URL="ecto://different_user:different_pass@localhost:5434/nitro"
export PORT="5000"
```

This file is automatically loaded by mise and gitignored.

## Environment-Specific Configuration

### Development

**Default configuration** (already in `.mise.toml`):
```toml
DATABASE_URL = "ecto://emd:Emd@123@localhost:5434/nitro"
PORT = "4000"
DB_LOG_LEVEL = "debug"
```

### Production

On your production server, create `.env.local`:

```bash
# On production server
cd /var/www/events

# Copy the example file
cp .env.production.example .env.local

# Edit with your production values
nano .env.local
```

**Production `.env.local` example**:
```bash
export DATABASE_URL="ecto://prod_user:prod_password@db-prod.internal:5432/nitro_prod"
export PORT="4000"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="yourdomain.com"
export PHX_SERVER="true"
export DB_POOL_SIZE="20"
export DB_LOG_LEVEL="warning"
export DB_SSL="true"
```

### Testing

Test environment uses defaults from `config/runtime.exs`:
```bash
MIX_ENV=test mix test
```

## How It Works

1. **mise** loads `.mise.toml` first (development defaults)
2. **mise** then loads `.env.local` if it exists (overrides)
3. **Phoenix** reads environment variables in `config/runtime.exs`

## Directory Structure

```
/home/user/projects/events/    # Development
  .mise.toml                   # Dev defaults (committed)
  .env.local                   # Dev overrides (gitignored)

/var/www/events/               # Production
  .mise.toml                   # Same file (dev defaults)
  .env.local                   # Prod config (gitignored)
```

## Available Environment Variables

### Database
- `DATABASE_URL` - Full database connection string
- `DB_POOL_SIZE` - Connection pool size (default: 10)
- `DB_QUEUE_TARGET` - Queue target in ms (default: 50)
- `DB_QUEUE_INTERVAL` - Queue interval in ms (default: 1000)
- `DB_LOG_LEVEL` - Log level: debug, info, warning, error
- `ECTO_IPV6` - Enable IPv6: true, false, 1, 0
- `DB_SSL` - Enable SSL: true, false, 1, 0

### Phoenix
- `PORT` - HTTP port (default: 4000)
- `SECRET_KEY_BASE` - Secret key for sessions (required in prod)
- `PHX_HOST` - Hostname (required in prod)
- `PHX_SERVER` - Start server: true, false

### Testing
- `MIX_TEST_PARTITION` - For parallel test execution

### Production
- `DNS_CLUSTER_QUERY` - DNS query for clustering
- `MAILGUN_API_KEY` - Mailgun API key
- `MAILGUN_DOMAIN` - Mailgun domain

## Best Practices

1. **Never commit `.env.local`** - It's gitignored for security
2. **Keep `.mise.toml` with safe defaults** - Commit this file
3. **Document changes** - Update this file when adding new env vars
4. **Use mise for consistency** - Team members get the same dev environment
5. **Generate secrets properly** - Use `mix phx.gen.secret` for `SECRET_KEY_BASE`

## Troubleshooting

### Variables not loading?

```bash
# Check what mise sees
mise env

# Reload mise
mise trust
```

### Database connection failed?

```bash
# Check your DATABASE_URL
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL
```

### Production deployment?

```bash
# On production server
cd /var/www/events
cp .env.production.example .env.local
nano .env.local  # Configure all values
mise trust
mix release
```

## Security Notes

- `.env.local` is **gitignored** - never commit it
- Production secrets should be managed by your deployment system
- Consider using secrets management tools (Vault, AWS Secrets Manager, etc.)
- Rotate `SECRET_KEY_BASE` regularly in production
