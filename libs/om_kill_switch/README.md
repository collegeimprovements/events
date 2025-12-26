# OmKillSwitch

Feature flags and kill switches for graceful degradation.

## Installation

```elixir
def deps do
  [{:om_kill_switch, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
alias OmKillSwitch

# Check if feature is enabled
if OmKillSwitch.enabled?(:new_checkout) do
  new_checkout_flow(order)
else
  legacy_checkout_flow(order)
end

# Kill switch (inverse - disabled by default)
unless OmKillSwitch.killed?(:stripe_payments) do
  process_payment(order)
else
  {:error, :payments_disabled}
end
```

## Configuration

```elixir
# config/config.exs
config :om_kill_switch,
  backend: :ets,  # :ets, :redis, :database
  defaults: %{
    new_checkout: false,
    stripe_payments: true
  }
```

## Runtime Control

```elixir
# Enable a feature
OmKillSwitch.enable(:new_checkout)

# Disable (kill) a feature
OmKillSwitch.disable(:stripe_payments)

# Toggle
OmKillSwitch.toggle(:beta_features)

# Get current state
OmKillSwitch.get(:new_checkout)
# => %{enabled: true, updated_at: ~U[...]}

# List all switches
OmKillSwitch.list()
# => [%{name: :new_checkout, enabled: true}, ...]
```

## Percentage Rollouts

```elixir
# Enable for 10% of requests
OmKillSwitch.enable(:new_feature, percentage: 10)

# Check with consistent bucketing
OmKillSwitch.enabled?(:new_feature, user_id: user.id)
```

## Conditional Switches

```elixir
OmKillSwitch.enabled?(:beta_features,
  when: fn -> user.role == :beta_tester end
)
```

## Telemetry

Events emitted:
- `[:om_kill_switch, :check]` - Switch checked
- `[:om_kill_switch, :toggle]` - Switch state changed

## License

MIT
