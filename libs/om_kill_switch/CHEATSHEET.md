# OmKillSwitch Cheatsheet

> Runtime service kill switches for graceful degradation. For full docs, see `README.md`.

## Setup

```elixir
# Supervision tree
children = [{OmKillSwitch, services: [:s3, :cache, :email, :payments]}]

# Config
config :om_kill_switch, services: [:s3, :cache, :email, :payments]
```

---

## Core API

```elixir
# Check status
OmKillSwitch.enabled?(:s3)                        #=> true

case OmKillSwitch.check(:s3) do
  :enabled -> S3.upload(bucket, key, content)
  {:disabled, reason} -> {:error, :service_disabled}
end

# Detailed status
OmKillSwitch.status(:s3)
#=> %{enabled: false, reason: "AWS outage", disabled_at: ~U[...]}

# Runtime control
OmKillSwitch.disable(:s3, reason: "AWS us-east-1 outage")
OmKillSwitch.enable(:s3)

# All statuses
OmKillSwitch.status_all()
OmKillSwitch.services()                            #=> [:s3, :cache, :email, :payments]
```

---

## Execute with Protection

```elixir
# Execute or error
result = OmKillSwitch.execute(:s3, fn ->
  S3.upload(bucket, key, content)
end)
# {:ok, _} | {:error, {:service_disabled, reason}}

# Execute with fallback
result = OmKillSwitch.with_service(:cache,
  fn -> Cache.get(key) end,
  fallback: fn -> Repo.get(User, id) end
)
```

---

## Environment Variables

| Service | Env Var | Values |
|---------|---------|--------|
| `:s3` | `S3_ENABLED` | `true`, `false` |
| `:cache` | `CACHE_ENABLED` | `true`, `false` |
| `:email` | `EMAIL_ENABLED` | `true`, `false` |
| `:payments` | `PAYMENTS_ENABLED` | `true`, `false` |

Priority: Env var > App config > Default (true)

---

## Service Wrappers

```elixir
# Pre-built S3 wrapper
alias OmKillSwitch.Services.S3
S3.upload(bucket, key, content, config)            # checks kill switch first

# Pre-built Cache wrapper
alias OmKillSwitch.Services.Cache
Cache.get(cache, key)                              # falls back on disabled
```
