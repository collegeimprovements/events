# FnTypes.Lens

Functional lenses for immutable data access and updates.

## Overview

Lenses provide a composable way to focus on parts of nested data structures. They solve the pain of deeply nested updates in immutable data:

```elixir
# Without lenses - verbose and error-prone
user = %{profile: %{settings: %{theme: "light"}}}
%{user | profile: %{user.profile | settings: %{user.profile.settings | theme: "dark"}}}

# With lenses - clean and composable
alias FnTypes.Lens
theme_lens = Lens.path([:profile, :settings, :theme])
Lens.set(theme_lens, user, "dark")
```

## Quick Start

```elixir
alias FnTypes.Lens

# Create a lens
name_lens = Lens.key(:name)

# Get a value
Lens.get(name_lens, %{name: "Alice"})
#=> "Alice"

# Set a value
Lens.set(name_lens, %{name: "Alice"}, "Bob")
#=> %{name: "Bob"}

# Update a value
Lens.update(name_lens, %{name: "alice"}, &String.upcase/1)
#=> %{name: "ALICE"}
```

## Creating Lenses

### Key Access

```elixir
# Single key
lens = Lens.key(:name)
Lens.get(lens, %{name: "Alice"})  #=> "Alice"

# With default for missing keys
lens = Lens.key(:bio, default: "No bio")
Lens.get(lens, %{})  #=> "No bio"
```

### Path Access

```elixir
# Nested path
lens = Lens.path([:user, :profile, :email])
data = %{user: %{profile: %{email: "a@b.c"}}}

Lens.get(lens, data)  #=> "a@b.c"
Lens.set(lens, data, "new@email.com")
#=> %{user: %{profile: %{email: "new@email.com"}}}

# With default
lens = Lens.path([:config, :timeout], default: 5000)
Lens.get(lens, %{config: %{}})  #=> 5000
```

### List/Tuple Access

```elixir
# List index
lens = Lens.at(1)
Lens.get(lens, [10, 20, 30])  #=> 20
Lens.set(lens, [10, 20, 30], 99)  #=> [10, 99, 30]

# Negative index
lens = Lens.at(-1)
Lens.get(lens, [1, 2, 3])  #=> 3

# Tuple element
lens = Lens.elem(1)
Lens.get(lens, {:ok, "value"})  #=> "value"

# First/Last shortcuts
Lens.get(Lens.first(), [1, 2, 3])  #=> 1
Lens.get(Lens.last(), [1, 2, 3])   #=> 3
```

### Result/Maybe Access

```elixir
# Focus on :ok value
lens = Lens.ok()
Lens.get(lens, {:ok, 42})  #=> 42
Lens.set(lens, {:ok, 42}, 100)  #=> {:ok, 100}

# Focus on :error value
lens = Lens.error()
Lens.get(lens, {:error, :not_found})  #=> :not_found

# Focus on :some value (Maybe)
lens = Lens.some()
Lens.get(lens, {:some, "value"})  #=> "value"
```

### Custom Lenses

```elixir
# Create from getter/setter functions
lens = Lens.make(
  fn data -> data.name end,
  fn data, value -> %{data | name: value} end
)

# Identity lens (focuses on entire structure)
lens = Lens.identity()
Lens.get(lens, "anything")  #=> "anything"
```

## Composition

### Basic Composition

```elixir
# Compose two lenses
address_lens = Lens.key(:address)
city_lens = Lens.key(:city)
composed = Lens.compose(address_lens, city_lens)

data = %{address: %{city: "NYC"}}
Lens.get(composed, data)  #=> "NYC"
```

### Operator Syntax

```elixir
import Lens, only: [~>: 2]

lens = Lens.key(:user) ~> Lens.key(:profile) ~> Lens.key(:name)
data = %{user: %{profile: %{name: "Alice"}}}

Lens.get(lens, data)  #=> "Alice"
```

### Compose All

```elixir
lens = Lens.compose_all([
  Lens.key(:company),
  Lens.key(:employees),
  Lens.at(0),
  Lens.key(:name)
])

data = %{company: %{employees: [%{name: "Alice"}, %{name: "Bob"}]}}
Lens.get(lens, data)  #=> "Alice"
```

## Core Operations

### Get

```elixir
lens = Lens.key(:name)
Lens.get(lens, %{name: "Alice"})  #=> "Alice"
Lens.get(lens, %{})  #=> nil
```

### Set

```elixir
lens = Lens.key(:name)
Lens.set(lens, %{name: "Alice"}, "Bob")  #=> %{name: "Bob"}
Lens.set(lens, %{}, "Bob")  #=> %{name: "Bob"}
```

### Update (Modify)

```elixir
lens = Lens.key(:count)
Lens.update(lens, %{count: 5}, &(&1 + 1))  #=> %{count: 6}
Lens.modify(lens, %{count: 5}, &(&1 * 2))  #=> %{count: 10}  # alias
```

### Get and Update

```elixir
lens = Lens.key(:count)
{old, new_data} = Lens.get_and_update(lens, %{count: 5}, &(&1 + 1))
# old = 5
# new_data = %{count: 6}
```

### Get and Set

```elixir
lens = Lens.key(:name)
{old, new_data} = Lens.get_and_set(lens, %{name: "Alice"}, "Bob")
# old = "Alice"
# new_data = %{name: "Bob"}
```

## Safe Operations

### Get with Maybe

```elixir
lens = Lens.key(:email)

Lens.get_maybe(lens, %{email: "a@b.c"})  #=> {:some, "a@b.c"}
Lens.get_maybe(lens, %{email: nil})       #=> :none
Lens.get_maybe(lens, %{})                 #=> :none
```

### Get with Result

```elixir
lens = Lens.key(:email)

Lens.get_result(lens, %{email: "a@b.c"})  #=> {:ok, "a@b.c"}
Lens.get_result(lens, %{})                 #=> {:error, :not_found}

# Custom error
Lens.get_result(lens, %{}, error: :missing_email)
#=> {:error, :missing_email}
```

### Conditional Updates

```elixir
lens = Lens.key(:name)

# Update only if non-nil
Lens.update_if(lens, %{name: "alice"}, &String.upcase/1)  #=> %{name: "ALICE"}
Lens.update_if(lens, %{name: nil}, &String.upcase/1)      #=> %{name: nil}

# Set only if nil
Lens.set_default(lens, %{name: nil}, "Anonymous")   #=> %{name: "Anonymous"}
Lens.set_default(lens, %{name: "Alice"}, "Anonymous")  #=> %{name: "Alice"}
```

## Collection Operations

### Map Over Collections

```elixir
lens = Lens.key(:name)
users = [%{name: "alice"}, %{name: "bob"}]

# Get from all
Lens.map_get(lens, users)
#=> ["alice", "bob"]

# Set on all
Lens.map_set(lens, users, "anonymous")
#=> [%{name: "anonymous"}, %{name: "anonymous"}]

# Update all
Lens.map_update(lens, users, &String.capitalize/1)
#=> [%{name: "Alice"}, %{name: "Bob"}]

# Alias
Lens.map_over(lens, users, &String.upcase/1)
#=> [%{name: "ALICE"}, %{name: "BOB"}]
```

## Predicate Operations

### Conditional Update

```elixir
lens = Lens.key(:age)

# Update only when predicate passes
Lens.update_when(lens, %{age: 25}, &(&1 >= 18), &(&1 + 1))
#=> %{age: 26}

Lens.update_when(lens, %{age: 15}, &(&1 >= 18), &(&1 + 1))
#=> %{age: 15}  # Not updated
```

### Check Predicate

```elixir
lens = Lens.key(:status)

Lens.matches?(lens, %{status: :active}, &(&1 == :active))  #=> true
Lens.matches?(lens, %{status: :inactive}, &(&1 == :active))  #=> false
```

## Transformation (Iso)

Transform values on get and set:

```elixir
# Store as cents, view as dollars
cents_lens = Lens.key(:price_cents)
dollars_lens = Lens.iso(
  cents_lens,
  &(&1 / 100),           # get transform: cents -> dollars
  &round(&1 * 100)       # set transform: dollars -> cents
)

data = %{price_cents: 1999}

Lens.get(dollars_lens, data)        #=> 19.99
Lens.set(dollars_lens, data, 25.50) #=> %{price_cents: 2550}
```

```elixir
# String/Integer conversion
int_lens = Lens.key(:count)
string_lens = Lens.iso(int_lens, &Integer.to_string/1, &String.to_integer/1)

data = %{count: 42}
Lens.get(string_lens, data)          #=> "42"
Lens.set(string_lens, data, "100")   #=> %{count: 100}
```

## Utility Functions

```elixir
lens = Lens.key(:name)

# Check for nil
Lens.nil?(lens, %{name: nil})     #=> true
Lens.nil?(lens, %{})              #=> true
Lens.nil?(lens, %{name: "Alice"}) #=> false

# Check for presence
Lens.present?(lens, %{name: "Alice"}) #=> true
Lens.present?(lens, %{name: nil})     #=> false

# Multiple keys
lens = Lens.keys([:name, :email])
data = %{name: "Alice", email: "a@b.c", age: 30}

Lens.get(lens, data)  #=> %{name: "Alice", email: "a@b.c"}
Lens.set(lens, data, %{name: "Bob", email: "b@c.d"})
#=> %{name: "Bob", email: "b@c.d", age: 30}

# Force-create nested paths
lens = Lens.path_force([:a, :b, :c])
Lens.set(lens, %{}, "value")  #=> %{a: %{b: %{c: "value"}}}
```

## Real-World Examples

### Configuration Management

```elixir
defmodule Config do
  alias FnTypes.Lens

  @db_timeout Lens.path([:database, :timeout])
  @cache_ttl Lens.path([:cache, :ttl])
  @feature_flags Lens.path([:features])

  def get_db_timeout(config), do: Lens.get(@db_timeout, config)
  def set_db_timeout(config, ms), do: Lens.set(@db_timeout, config, ms)

  def get_cache_ttl(config), do: Lens.get(@cache_ttl, config)
  def double_cache_ttl(config), do: Lens.update(@cache_ttl, config, &(&1 * 2))

  def enable_feature(config, feature) do
    flags_lens = Lens.compose(@feature_flags, Lens.key(feature))
    Lens.set(flags_lens, config, true)
  end
end
```

### Form Data Handling

```elixir
defmodule FormHandler do
  alias FnTypes.Lens

  def normalize_user_form(params) do
    email_lens = Lens.key(:email)
    name_lens = Lens.key(:name)

    params
    |> then(&Lens.update_if(email_lens, &1, &String.downcase/1))
    |> then(&Lens.update_if(name_lens, &1, &String.trim/1))
    |> then(&Lens.set_default(Lens.key(:role), &1, "user"))
  end
end
```

### Bulk Updates

```elixir
defmodule UserService do
  alias FnTypes.Lens

  @status_lens Lens.key(:status)
  @updated_at_lens Lens.key(:updated_at)

  def deactivate_all(users) do
    now = DateTime.utc_now()

    users
    |> Lens.map_set(@status_lens, :inactive)
    |> Lens.map_set(@updated_at_lens, now)
  end

  def increment_login_counts(users) do
    login_lens = Lens.key(:login_count)
    Lens.map_update(login_lens, users, &((&1 || 0) + 1))
  end
end
```

## Function Reference

| Function | Description |
|----------|-------------|
| `make/2` | Create lens from getter/setter |
| `identity/0` | Lens focusing on entire structure |
| `key/1,2` | Lens for map key |
| `path/1,2` | Lens for nested path |
| `at/1` | Lens for list index |
| `elem/1` | Lens for tuple element |
| `first/0` | Lens for first element |
| `last/0` | Lens for last element |
| `ok/0` | Lens for :ok tuple value |
| `error/0` | Lens for :error tuple value |
| `some/0` | Lens for :some tuple value |
| `get/2` | Extract focused value |
| `set/3` | Set focused value |
| `update/3` | Transform focused value |
| `modify/3` | Alias for update |
| `get_and_update/3` | Get old, apply update |
| `get_and_set/3` | Get old, set new |
| `compose/2` | Chain two lenses |
| `~>/2` | Operator for compose |
| `compose_all/1` | Chain list of lenses |
| `get_maybe/2` | Get as Maybe |
| `get_result/2,3` | Get as Result |
| `update_if/3` | Update if non-nil |
| `set_default/3` | Set if nil |
| `map_get/2` | Get from all items |
| `map_set/3` | Set on all items |
| `map_update/3` | Update all items |
| `update_when/4` | Conditional update |
| `matches?/3` | Check predicate |
| `iso/3` | Bidirectional transform |
| `nil?/2` | Check if nil |
| `present?/2` | Check if non-nil |
| `keys/1` | Multi-key lens |
| `path_force/1` | Path with auto-create |
