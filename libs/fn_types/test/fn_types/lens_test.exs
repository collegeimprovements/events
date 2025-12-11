defmodule FnTypes.LensTest do
  use ExUnit.Case, async: true

  alias FnTypes.Lens

  describe "constructors" do
    test "make/2 creates a lens from getter and setter" do
      lens =
        Lens.make(
          fn data -> data.name end,
          fn data, value -> %{data | name: value} end
        )

      assert Lens.get(lens, %{name: "Alice"}) == "Alice"
      assert Lens.set(lens, %{name: "Alice"}, "Bob") == %{name: "Bob"}
    end

    test "identity/0 focuses on entire structure" do
      lens = Lens.identity()

      assert Lens.get(lens, "hello") == "hello"
      assert Lens.get(lens, 42) == 42
      assert Lens.set(lens, "hello", "world") == "world"
    end

    test "key/1 focuses on map key" do
      lens = Lens.key(:name)

      assert Lens.get(lens, %{name: "Alice"}) == "Alice"
      assert Lens.get(lens, %{}) == nil
      assert Lens.set(lens, %{name: "Alice"}, "Bob") == %{name: "Bob"}
      assert Lens.set(lens, %{}, "Bob") == %{name: "Bob"}
    end

    test "key/2 with default value" do
      lens = Lens.key(:bio, default: "No bio")

      assert Lens.get(lens, %{bio: "Developer"}) == "Developer"
      assert Lens.get(lens, %{}) == "No bio"
      assert Lens.get(lens, %{bio: nil}) == "No bio"
    end

    test "path/1 focuses on nested path" do
      lens = Lens.path([:address, :city])
      data = %{address: %{city: "NYC", zip: "10001"}}

      assert Lens.get(lens, data) == "NYC"
      assert Lens.set(lens, data, "LA") == %{address: %{city: "LA", zip: "10001"}}
    end

    test "path/2 with default" do
      lens = Lens.path([:profile, :settings, :theme], default: "dark")

      assert Lens.get(lens, %{profile: %{settings: %{theme: "light"}}}) == "light"
      assert Lens.get(lens, %{profile: %{}}) == "dark"
      assert Lens.get(lens, %{}) == "dark"
    end

    test "at/1 focuses on list index" do
      lens = Lens.at(1)

      assert Lens.get(lens, [1, 2, 3]) == 2
      assert Lens.set(lens, [1, 2, 3], 20) == [1, 20, 3]
    end

    test "at/1 with negative index" do
      lens = Lens.at(-1)

      assert Lens.get(lens, [1, 2, 3]) == 3
      assert Lens.set(lens, [1, 2, 3], 30) == [1, 2, 30]
    end

    test "elem/1 focuses on tuple element" do
      lens = Lens.elem(1)

      assert Lens.get(lens, {:ok, 42}) == 42
      assert Lens.set(lens, {:ok, 42}, 100) == {:ok, 100}
    end

    test "first/0 focuses on first element" do
      lens = Lens.first()

      assert Lens.get(lens, [1, 2, 3]) == 1
      assert Lens.get(lens, {:a, :b, :c}) == :a
      assert Lens.set(lens, [1, 2, 3], 10) == [10, 2, 3]
    end

    test "last/0 focuses on last list element" do
      lens = Lens.last()

      assert Lens.get(lens, [1, 2, 3]) == 3
      assert Lens.set(lens, [1, 2, 3], 30) == [1, 2, 30]
      assert Lens.set(lens, [], 1) == [1]
    end

    test "ok/0 focuses on :ok tuple value" do
      lens = Lens.ok()

      assert Lens.get(lens, {:ok, "value"}) == "value"
      assert Lens.set(lens, {:ok, "old"}, "new") == {:ok, "new"}
    end

    test "error/0 focuses on :error tuple value" do
      lens = Lens.error()

      assert Lens.get(lens, {:error, :not_found}) == :not_found
      assert Lens.set(lens, {:error, :old}, :new) == {:error, :new}
    end

    test "some/0 focuses on :some tuple value" do
      lens = Lens.some()

      assert Lens.get(lens, {:some, "value"}) == "value"
      assert Lens.set(lens, {:some, "old"}, "new") == {:some, "new"}
    end
  end

  describe "core operations" do
    setup do
      %{
        data: %{name: "Alice", age: 30, address: %{city: "NYC"}},
        name_lens: Lens.key(:name),
        age_lens: Lens.key(:age),
        city_lens: Lens.path([:address, :city])
      }
    end

    test "get/2 extracts value", %{data: data, name_lens: lens} do
      assert Lens.get(lens, data) == "Alice"
    end

    test "set/3 sets value", %{data: data, name_lens: lens} do
      result = Lens.set(lens, data, "Bob")
      assert result.name == "Bob"
      assert result.age == 30
    end

    test "update/3 transforms value", %{data: data, age_lens: lens} do
      result = Lens.update(lens, data, &(&1 + 1))
      assert result.age == 31
    end

    test "modify/3 is alias for update", %{data: data, name_lens: lens} do
      result = Lens.modify(lens, data, &String.upcase/1)
      assert result.name == "ALICE"
    end

    test "get_and_update/3 returns old value and updates", %{data: data, age_lens: lens} do
      {old, new_data} = Lens.get_and_update(lens, data, &(&1 + 5))

      assert old == 30
      assert new_data.age == 35
    end

    test "get_and_set/3 returns old value and sets new", %{data: data, name_lens: lens} do
      {old, new_data} = Lens.get_and_set(lens, data, "Bob")

      assert old == "Alice"
      assert new_data.name == "Bob"
    end
  end

  describe "composition" do
    test "compose/2 chains lenses" do
      address_lens = Lens.key(:address)
      city_lens = Lens.key(:city)
      composed = Lens.compose(address_lens, city_lens)

      data = %{address: %{city: "NYC"}}

      assert Lens.get(composed, data) == "NYC"
      assert Lens.set(composed, data, "LA") == %{address: %{city: "LA"}}
    end

    test "~>/2 operator composes lenses" do
      import Lens, only: [~>: 2]

      lens = Lens.key(:user) ~> Lens.key(:profile) ~> Lens.key(:name)
      data = %{user: %{profile: %{name: "Alice"}}}

      assert Lens.get(lens, data) == "Alice"
    end

    test "compose_all/1 composes list of lenses" do
      lens =
        Lens.compose_all([
          Lens.key(:company),
          Lens.key(:employees),
          Lens.at(0),
          Lens.key(:name)
        ])

      data = %{company: %{employees: [%{name: "Alice"}, %{name: "Bob"}]}}

      assert Lens.get(lens, data) == "Alice"
    end
  end

  describe "safe operations" do
    test "get_maybe/2 returns Maybe" do
      lens = Lens.key(:name)

      assert Lens.get_maybe(lens, %{name: "Alice"}) == {:some, "Alice"}
      assert Lens.get_maybe(lens, %{name: nil}) == :none
      assert Lens.get_maybe(lens, %{}) == :none
    end

    test "get_result/2 returns Result" do
      lens = Lens.key(:name)

      assert Lens.get_result(lens, %{name: "Alice"}) == {:ok, "Alice"}
      assert Lens.get_result(lens, %{}) == {:error, :not_found}
    end

    test "get_result/3 with custom error" do
      lens = Lens.key(:email)

      assert Lens.get_result(lens, %{}, error: :missing_email) == {:error, :missing_email}
    end

    test "update_if/3 updates only non-nil values" do
      lens = Lens.key(:name)

      # Updates when present
      assert Lens.update_if(lens, %{name: "alice"}, &String.upcase/1) == %{name: "ALICE"}

      # No-op when nil
      assert Lens.update_if(lens, %{name: nil}, &String.upcase/1) == %{name: nil}
    end

    test "set_default/3 sets only when nil" do
      lens = Lens.key(:role)

      # Sets when nil
      assert Lens.set_default(lens, %{role: nil}, "user") == %{role: "user"}

      # No-op when present
      assert Lens.set_default(lens, %{role: "admin"}, "user") == %{role: "admin"}
    end
  end

  describe "collection operations" do
    test "map_get/2 gets from all items" do
      lens = Lens.key(:name)
      users = [%{name: "Alice"}, %{name: "Bob"}, %{name: "Carol"}]

      assert Lens.map_get(lens, users) == ["Alice", "Bob", "Carol"]
    end

    test "map_set/3 sets on all items" do
      lens = Lens.key(:active)
      users = [%{name: "Alice", active: false}, %{name: "Bob", active: false}]

      result = Lens.map_set(lens, users, true)

      assert Enum.all?(result, & &1.active)
    end

    test "map_update/3 updates all items" do
      lens = Lens.key(:count)
      items = [%{count: 1}, %{count: 2}, %{count: 3}]

      result = Lens.map_update(lens, items, &(&1 * 2))

      assert Enum.map(result, & &1.count) == [2, 4, 6]
    end

    test "map_over/3 is alias for map_update" do
      lens = Lens.key(:name)
      users = [%{name: "alice"}, %{name: "bob"}]

      result = Lens.map_over(lens, users, &String.capitalize/1)

      assert Enum.map(result, & &1.name) == ["Alice", "Bob"]
    end
  end

  describe "predicate operations" do
    test "update_when/4 updates when predicate passes" do
      lens = Lens.key(:age)

      # Updates when predicate passes
      result = Lens.update_when(lens, %{age: 25}, &(&1 >= 18), &(&1 + 1))
      assert result.age == 26

      # No-op when predicate fails
      result = Lens.update_when(lens, %{age: 15}, &(&1 >= 18), &(&1 + 1))
      assert result.age == 15
    end

    test "matches?/3 checks predicate" do
      lens = Lens.key(:status)

      assert Lens.matches?(lens, %{status: :active}, &(&1 == :active))
      refute Lens.matches?(lens, %{status: :inactive}, &(&1 == :active))
    end
  end

  describe "iso transformation" do
    test "iso/3 transforms on get and set" do
      # Store as cents, view as dollars
      cents_lens = Lens.key(:price_cents)
      dollars_lens = Lens.iso(cents_lens, &(&1 / 100), &round(&1 * 100))

      data = %{price_cents: 1999}

      assert Lens.get(dollars_lens, data) == 19.99
      assert Lens.set(dollars_lens, data, 25.50) == %{price_cents: 2550}
    end

    test "iso/3 with string/integer conversion" do
      int_lens = Lens.key(:count)
      string_lens = Lens.iso(int_lens, &Integer.to_string/1, &String.to_integer/1)

      data = %{count: 42}

      assert Lens.get(string_lens, data) == "42"
      assert Lens.set(string_lens, data, "100") == %{count: 100}
    end
  end

  describe "utility functions" do
    test "nil?/2 checks for nil value" do
      lens = Lens.key(:name)

      assert Lens.nil?(lens, %{name: nil})
      assert Lens.nil?(lens, %{})
      refute Lens.nil?(lens, %{name: "Alice"})
    end

    test "present?/2 checks for non-nil value" do
      lens = Lens.key(:name)

      assert Lens.present?(lens, %{name: "Alice"})
      refute Lens.present?(lens, %{name: nil})
      refute Lens.present?(lens, %{})
    end

    test "keys/1 focuses on multiple keys" do
      lens = Lens.keys([:name, :email])
      data = %{name: "Alice", email: "a@b.c", age: 30, role: "admin"}

      assert Lens.get(lens, data) == %{name: "Alice", email: "a@b.c"}

      # Set merges values
      result = Lens.set(lens, data, %{name: "Bob", email: "b@c.d"})
      assert result.name == "Bob"
      assert result.email == "b@c.d"
      assert result.age == 30
    end

    test "path_force/1 creates nested maps if needed" do
      lens = Lens.path_force([:a, :b, :c])

      # Creates nested structure
      assert Lens.set(lens, %{}, "value") == %{a: %{b: %{c: "value"}}}

      # Works with existing structure
      assert Lens.set(lens, %{a: %{b: %{}}}, "value") == %{a: %{b: %{c: "value"}}}
    end
  end

  describe "struct support" do
    defmodule User do
      defstruct [:name, :email, :settings]
    end

    defmodule Settings do
      defstruct [:theme, :notifications]
    end

    test "works with structs" do
      lens = Lens.key(:name)
      user = %User{name: "Alice", email: "a@b.c"}

      assert Lens.get(lens, user) == "Alice"
      assert %User{name: "Bob"} = Lens.set(lens, user, "Bob")
    end

    test "nested struct access with key lenses" do
      # For structs, compose key lenses instead of using path
      settings_lens = Lens.key(:settings)
      theme_lens = Lens.key(:theme)
      lens = Lens.compose(settings_lens, theme_lens)

      user = %User{
        name: "Alice",
        settings: %Settings{theme: "dark", notifications: true}
      }

      assert Lens.get(lens, user) == "dark"
    end
  end

  describe "real-world examples" do
    test "deeply nested config update" do
      config = %{
        database: %{
          primary: %{host: "localhost", port: 5432},
          replica: %{host: "replica.local", port: 5432}
        },
        cache: %{enabled: true, ttl: 3600}
      }

      primary_host = Lens.path([:database, :primary, :host])
      cache_ttl = Lens.path([:cache, :ttl])

      updated =
        config
        |> then(&Lens.set(primary_host, &1, "db.prod.com"))
        |> then(&Lens.update(cache_ttl, &1, fn x -> x * 2 end))

      assert get_in(updated, [:database, :primary, :host]) == "db.prod.com"
      assert get_in(updated, [:cache, :ttl]) == 7200
    end

    test "transform list of nested structures" do
      orders = [
        %{id: 1, items: [%{price: 10}, %{price: 20}]},
        %{id: 2, items: [%{price: 15}]}
      ]

      # Get all first item prices
      first_item_price =
        Lens.compose_all([
          Lens.key(:items),
          Lens.first(),
          Lens.key(:price)
        ])

      prices = Lens.map_get(first_item_price, orders)
      assert prices == [10, 15]

      # Double all first item prices
      updated = Lens.map_update(first_item_price, orders, &(&1 * 2))
      assert hd(hd(updated).items).price == 20
    end

    test "result tuple transformation" do
      results = [
        {:ok, %{value: 1}},
        {:ok, %{value: 2}},
        {:error, :not_found}
      ]

      ok_value_lens = Lens.compose(Lens.ok(), Lens.key(:value))

      # Get values from ok tuples (will fail on error tuple)
      ok_results = Enum.filter(results, &match?({:ok, _}, &1))
      values = Lens.map_get(ok_value_lens, ok_results)

      assert values == [1, 2]
    end
  end
end
