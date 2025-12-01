defmodule Events.Types.Lens do
  @moduledoc """
  Functional lenses for accessing and updating deeply nested immutable data.

  Lenses provide a composable way to focus on parts of data structures,
  enabling clean get/set/update operations without manual nested access.

  ## What is a Lens?

  A lens is a first-class reference to a part of a data structure. It encapsulates:
  - **getter**: How to extract a value from a structure
  - **setter**: How to update a value within a structure

  ## Quick Start

      alias Events.Types.Lens

      # Create lenses for nested access
      user = %{name: "Alice", address: %{city: "NYC", zip: "10001"}}

      # Using path-based lens (easiest)
      city_lens = Lens.path([:address, :city])

      Lens.get(city_lens, user)           #=> "NYC"
      Lens.set(city_lens, user, "LA")     #=> %{..., address: %{city: "LA", ...}}
      Lens.update(city_lens, user, &String.upcase/1)  #=> %{..., city: "NYC"}

  ## Creating Lenses

  ### Path-based (recommended for maps/structs)

      # Single key
      name_lens = Lens.key(:name)

      # Nested path
      city_lens = Lens.path([:address, :city])

      # With default value
      bio_lens = Lens.path([:profile, :bio], default: "")

  ### Index-based (for lists/tuples)

      # List index
      first_lens = Lens.at(0)
      third_lens = Lens.at(2)

      # Tuple element
      ok_value = Lens.elem(1)  # Second element of tuple

  ### Custom lenses

      # Full control over get/set
      custom = Lens.make(
        fn data -> data.special_field end,
        fn data, value -> %{data | special_field: value} end
      )

  ## Composition

  The real power of lenses is composition - combine simple lenses to access deep structures:

      # Compose two lenses
      address_lens = Lens.key(:address)
      city_lens = Lens.key(:city)
      user_city = Lens.compose(address_lens, city_lens)

      # Or use the ~> operator
      import Lens, only: [~>: 2]
      user_city = Lens.key(:address) ~> Lens.key(:city)

      # Or use path (simpler for maps)
      user_city = Lens.path([:address, :city])

  ## Operations

  | Function | Description |
  |----------|-------------|
  | `get/2` | Extract value through lens |
  | `set/3` | Set value through lens |
  | `update/3` | Update value with function |
  | `get_and_update/3` | Get old value and set new |
  | `modify/3` | Alias for update |

  ## Common Patterns

  ### Deeply nested updates

      # Instead of:
      %{user | settings: %{user.settings | theme: %{user.settings.theme | color: "blue"}}}

      # Use lens:
      color_lens = Lens.path([:settings, :theme, :color])
      Lens.set(color_lens, user, "blue")

  ### Conditional updates

      # Update only if present
      Lens.update_if(lens, data, &String.upcase/1)

  ### Working with lists

      # Update all items
      users = [%{name: "Alice"}, %{name: "Bob"}]
      name_lens = Lens.key(:name)

      Lens.map_over(name_lens, users, &String.upcase/1)
      #=> [%{name: "ALICE"}, %{name: "BOB"}]

  ### Lens pipelines

      data
      |> Lens.set(name_lens, "Alice")
      |> Lens.update(age_lens, &(&1 + 1))
      |> Lens.set(city_lens, "NYC")

  ## Integration with Result/Maybe

      alias Events.Types.{Lens, Result, Maybe}

      # Safe get returning Maybe
      Lens.get_maybe(city_lens, user)  #=> {:some, "NYC"} or :none

      # Safe get returning Result
      Lens.get_result(city_lens, user)  #=> {:ok, "NYC"} or {:error, :not_found}

  ## Predefined Lenses

  | Lens | Description |
  |------|-------------|
  | `Lens.identity()` | Returns data unchanged |
  | `Lens.key(k)` | Focus on map key |
  | `Lens.path(p)` | Focus on nested path |
  | `Lens.at(i)` | Focus on list index |
  | `Lens.elem(i)` | Focus on tuple element |
  | `Lens.first()` | First element |
  | `Lens.last()` | Last element (list) |
  | `Lens.all()` | All elements (traversal-like) |

  ## Struct Support

      defmodule User do
        defstruct [:name, :email, :address]
      end

      user = %User{name: "Alice", email: "alice@example.com"}
      name_lens = Lens.key(:name)

      Lens.get(name_lens, user)        #=> "Alice"
      Lens.set(name_lens, user, "Bob") #=> %User{name: "Bob", ...}
  """

  alias Events.Types.{Maybe, Result}

  # ============================================================================
  # Types
  # ============================================================================

  @type t :: t(any(), any())

  @type t(s, a) :: %__MODULE__{
          getter: (s -> a),
          setter: (s, a -> s)
        }

  @enforce_keys [:getter, :setter]
  defstruct [:getter, :setter]

  # ============================================================================
  # Constructors
  # ============================================================================

  @doc """
  Creates a lens from getter and setter functions.

  ## Examples

      lens = Lens.make(
        fn user -> user.name end,
        fn user, name -> %{user | name: name} end
      )

      Lens.get(lens, %{name: "Alice"})  #=> "Alice"
  """
  @spec make((s -> a), (s, a -> s)) :: t(s, a) when s: any(), a: any()
  def make(getter, setter) when is_function(getter, 1) and is_function(setter, 2) do
    %__MODULE__{getter: getter, setter: setter}
  end

  @doc """
  Creates an identity lens that focuses on the entire structure.

  ## Examples

      lens = Lens.identity()
      Lens.get(lens, "hello")        #=> "hello"
      Lens.set(lens, "hello", "hi")  #=> "hi"
  """
  @spec identity() :: t(a, a) when a: any()
  def identity do
    make(
      fn data -> data end,
      fn _data, value -> value end
    )
  end

  @doc """
  Creates a lens focusing on a map/struct key.

  ## Options

  - `:default` - Value to return if key is missing (default: nil)

  ## Examples

      name_lens = Lens.key(:name)
      Lens.get(name_lens, %{name: "Alice"})  #=> "Alice"
      Lens.get(name_lens, %{})               #=> nil

      # With default
      bio_lens = Lens.key(:bio, default: "No bio")
      Lens.get(bio_lens, %{})  #=> "No bio"
  """
  @spec key(atom() | String.t(), keyword()) :: t(map(), any())
  def key(key, opts \\ []) do
    default = Keyword.get(opts, :default)

    make(
      fn data ->
        case Map.get(data, key) do
          nil -> default
          value -> value
        end
      end,
      fn data, value -> Map.put(data, key, value) end
    )
  end

  @doc """
  Creates a lens focusing on a nested path in a map/struct.

  ## Options

  - `:default` - Value to return if path doesn't exist (default: nil)

  ## Examples

      city_lens = Lens.path([:address, :city])

      user = %{address: %{city: "NYC"}}
      Lens.get(city_lens, user)        #=> "NYC"
      Lens.set(city_lens, user, "LA")  #=> %{address: %{city: "LA"}}

      # With default
      zip_lens = Lens.path([:address, :zip], default: "00000")
      Lens.get(zip_lens, %{address: %{}})  #=> "00000"
  """
  @spec path([atom() | String.t()], keyword()) :: t(map(), any())
  def path(keys, opts \\ []) when is_list(keys) do
    default = Keyword.get(opts, :default)

    make(
      fn data ->
        case safe_get_in(data, keys) do
          nil -> default
          value -> value
        end
      end,
      fn data, value -> put_in_path(data, keys, value) end
    )
  end

  @doc """
  Creates a lens focusing on a list element at the given index.

  Supports negative indices (-1 for last, -2 for second-to-last, etc.)

  ## Examples

      first = Lens.at(0)
      Lens.get(first, [1, 2, 3])        #=> 1
      Lens.set(first, [1, 2, 3], 10)    #=> [10, 2, 3]

      last = Lens.at(-1)
      Lens.get(last, [1, 2, 3])         #=> 3
      Lens.set(last, [1, 2, 3], 30)     #=> [1, 2, 30]
  """
  @spec at(integer()) :: t(list(), any())
  def at(index) when is_integer(index) do
    make(
      fn list -> Enum.at(list, index) end,
      fn list, value -> List.replace_at(list, index, value) end
    )
  end

  @doc """
  Creates a lens focusing on a tuple element at the given index.

  ## Examples

      second = Lens.elem(1)
      Lens.get(second, {:ok, 42})        #=> 42
      Lens.set(second, {:ok, 42}, 100)   #=> {:ok, 100}
  """
  @spec elem(non_neg_integer()) :: t(tuple(), any())
  def elem(index) when is_integer(index) and index >= 0 do
    make(
      fn tuple -> Kernel.elem(tuple, index) end,
      fn tuple, value -> put_elem(tuple, index, value) end
    )
  end

  @doc """
  Creates a lens focusing on the first element.

  Works with lists, tuples, and any enumerable.

  ## Examples

      first = Lens.first()
      Lens.get(first, [1, 2, 3])      #=> 1
      Lens.get(first, {:a, :b})       #=> :a
      Lens.set(first, [1, 2, 3], 10)  #=> [10, 2, 3]
  """
  @spec first() :: t(any(), any())
  def first do
    make(
      fn
        [h | _] -> h
        tuple when is_tuple(tuple) -> Kernel.elem(tuple, 0)
        data -> Enum.at(data, 0)
      end,
      fn data, value ->
        case data do
          [_ | t] -> [value | t]
          tuple when is_tuple(tuple) -> put_elem(tuple, 0, value)
          _ -> List.replace_at(Enum.to_list(data), 0, value)
        end
      end
    )
  end

  @doc """
  Creates a lens focusing on the last element of a list.

  ## Examples

      last = Lens.last()
      Lens.get(last, [1, 2, 3])      #=> 3
      Lens.set(last, [1, 2, 3], 30)  #=> [1, 2, 30]
  """
  @spec last() :: t(list(), any())
  def last do
    make(
      fn list -> List.last(list) end,
      fn list, value ->
        case list do
          [] -> [value]
          _ -> List.replace_at(list, -1, value)
        end
      end
    )
  end

  @doc """
  Creates a lens for the value inside an :ok tuple.

  ## Examples

      ok_lens = Lens.ok()
      Lens.get(ok_lens, {:ok, 42})        #=> 42
      Lens.set(ok_lens, {:ok, 42}, 100)   #=> {:ok, 100}
  """
  @spec ok() :: t({:ok, a}, a) when a: any()
  def ok do
    elem(1)
  end

  @doc """
  Creates a lens for the value inside an :error tuple.

  ## Examples

      error_lens = Lens.error()
      Lens.get(error_lens, {:error, :not_found})     #=> :not_found
      Lens.set(error_lens, {:error, :not_found}, :invalid)  #=> {:error, :invalid}
  """
  @spec error() :: t({:error, a}, a) when a: any()
  def error do
    elem(1)
  end

  @doc """
  Creates a lens for the value inside a :some tuple (Maybe).

  ## Examples

      some_lens = Lens.some()
      Lens.get(some_lens, {:some, "value"})        #=> "value"
      Lens.set(some_lens, {:some, "value"}, "new") #=> {:some, "new"}
  """
  @spec some() :: t({:some, a}, a) when a: any()
  def some do
    elem(1)
  end

  # ============================================================================
  # Core Operations
  # ============================================================================

  @doc """
  Gets the value focused by the lens.

  ## Examples

      lens = Lens.key(:name)
      Lens.get(lens, %{name: "Alice"})  #=> "Alice"
  """
  @spec get(t(s, a), s) :: a when s: any(), a: any()
  def get(%__MODULE__{getter: getter}, data) do
    getter.(data)
  end

  @doc """
  Sets the value focused by the lens.

  ## Examples

      lens = Lens.key(:name)
      Lens.set(lens, %{name: "Alice"}, "Bob")  #=> %{name: "Bob"}
  """
  @spec set(t(s, a), s, a) :: s when s: any(), a: any()
  def set(%__MODULE__{setter: setter}, data, value) do
    setter.(data, value)
  end

  @doc """
  Updates the value focused by the lens using a function.

  ## Examples

      lens = Lens.key(:count)
      Lens.update(lens, %{count: 5}, &(&1 + 1))  #=> %{count: 6}

      name_lens = Lens.key(:name)
      Lens.update(name_lens, %{name: "alice"}, &String.capitalize/1)
      #=> %{name: "Alice"}
  """
  @spec update(t(s, a), s, (a -> a)) :: s when s: any(), a: any()
  def update(%__MODULE__{} = lens, data, fun) when is_function(fun, 1) do
    current = get(lens, data)
    set(lens, data, fun.(current))
  end

  @doc """
  Alias for `update/3`.
  """
  @spec modify(t(s, a), s, (a -> a)) :: s when s: any(), a: any()
  def modify(lens, data, fun), do: update(lens, data, fun)

  @doc """
  Gets the current value and sets a new value in one operation.

  Returns `{old_value, new_data}`.

  ## Examples

      lens = Lens.key(:count)
      Lens.get_and_update(lens, %{count: 5}, fn c -> c + 1 end)
      #=> {5, %{count: 6}}
  """
  @spec get_and_update(t(s, a), s, (a -> a)) :: {a, s} when s: any(), a: any()
  def get_and_update(%__MODULE__{} = lens, data, fun) when is_function(fun, 1) do
    old_value = get(lens, data)
    new_value = fun.(old_value)
    {old_value, set(lens, data, new_value)}
  end

  @doc """
  Gets the current value and sets a specific new value.

  Returns `{old_value, new_data}`.

  ## Examples

      lens = Lens.key(:name)
      Lens.get_and_set(lens, %{name: "Alice"}, "Bob")
      #=> {"Alice", %{name: "Bob"}}
  """
  @spec get_and_set(t(s, a), s, a) :: {a, s} when s: any(), a: any()
  def get_and_set(%__MODULE__{} = lens, data, new_value) do
    old_value = get(lens, data)
    {old_value, set(lens, data, new_value)}
  end

  # ============================================================================
  # Composition
  # ============================================================================

  @doc """
  Composes two lenses, creating a lens that focuses through both.

  The first lens focuses on the outer structure, the second on the inner.

  ## Examples

      address_lens = Lens.key(:address)
      city_lens = Lens.key(:city)
      user_city = Lens.compose(address_lens, city_lens)

      user = %{address: %{city: "NYC"}}
      Lens.get(user_city, user)        #=> "NYC"
      Lens.set(user_city, user, "LA")  #=> %{address: %{city: "LA"}}
  """
  @spec compose(t(s, a), t(a, b)) :: t(s, b) when s: any(), a: any(), b: any()
  def compose(%__MODULE__{} = outer, %__MODULE__{} = inner) do
    make(
      fn data -> inner.getter.(outer.getter.(data)) end,
      fn data, value ->
        inner_data = outer.getter.(data)
        new_inner = inner.setter.(inner_data, value)
        outer.setter.(data, new_inner)
      end
    )
  end

  @doc """
  Infix operator for lens composition.

  ## Examples

      import Events.Types.Lens, only: [~>: 2]

      lens = Lens.key(:address) ~> Lens.key(:city)
      Lens.get(lens, %{address: %{city: "NYC"}})  #=> "NYC"
  """
  @spec t(s, a) ~> t(a, b) :: t(s, b) when s: any(), a: any(), b: any()
  def left ~> right do
    compose(left, right)
  end

  @doc """
  Composes a list of lenses from left to right.

  ## Examples

      lens = Lens.compose_all([
        Lens.key(:company),
        Lens.key(:address),
        Lens.key(:city)
      ])

      data = %{company: %{address: %{city: "NYC"}}}
      Lens.get(lens, data)  #=> "NYC"
  """
  @spec compose_all([t()]) :: t()
  def compose_all([single]), do: single

  def compose_all([first | rest]) do
    Enum.reduce(rest, first, &compose(&2, &1))
  end

  # ============================================================================
  # Safe Operations (with Maybe/Result)
  # ============================================================================

  @doc """
  Gets the value through a lens, returning a Maybe.

  Returns `:none` if the value is nil.

  ## Examples

      lens = Lens.key(:name)
      Lens.get_maybe(lens, %{name: "Alice"})  #=> {:some, "Alice"}
      Lens.get_maybe(lens, %{name: nil})      #=> :none
      Lens.get_maybe(lens, %{})               #=> :none
  """
  @spec get_maybe(t(s, a), s) :: Maybe.t(a) when s: any(), a: any()
  def get_maybe(%__MODULE__{} = lens, data) do
    case get(lens, data) do
      nil -> :none
      value -> {:some, value}
    end
  end

  @doc """
  Gets the value through a lens, returning a Result.

  Returns `{:error, :not_found}` if the value is nil.

  ## Options

  - `:error` - Custom error to return (default: `:not_found`)

  ## Examples

      lens = Lens.key(:name)
      Lens.get_result(lens, %{name: "Alice"})  #=> {:ok, "Alice"}
      Lens.get_result(lens, %{})               #=> {:error, :not_found}

      Lens.get_result(lens, %{}, error: :missing_name)
      #=> {:error, :missing_name}
  """
  @spec get_result(t(s, a), s, keyword()) :: Result.t(a, atom()) when s: any(), a: any()
  def get_result(%__MODULE__{} = lens, data, opts \\ []) do
    error = Keyword.get(opts, :error, :not_found)

    case get(lens, data) do
      nil -> {:error, error}
      value -> {:ok, value}
    end
  end

  @doc """
  Updates the value only if the current value is not nil.

  ## Examples

      lens = Lens.key(:name)

      # Updates when value exists
      Lens.update_if(lens, %{name: "alice"}, &String.upcase/1)
      #=> %{name: "ALICE"}

      # No-op when nil
      Lens.update_if(lens, %{name: nil}, &String.upcase/1)
      #=> %{name: nil}
  """
  @spec update_if(t(s, a), s, (a -> a)) :: s when s: any(), a: any()
  def update_if(%__MODULE__{} = lens, data, fun) when is_function(fun, 1) do
    case get(lens, data) do
      nil -> data
      value -> set(lens, data, fun.(value))
    end
  end

  @doc """
  Sets the value only if the current value is nil.

  ## Examples

      lens = Lens.key(:name)

      # Sets when nil
      Lens.set_default(lens, %{name: nil}, "Unknown")
      #=> %{name: "Unknown"}

      # No-op when already set
      Lens.set_default(lens, %{name: "Alice"}, "Unknown")
      #=> %{name: "Alice"}
  """
  @spec set_default(t(s, a), s, a) :: s when s: any(), a: any()
  def set_default(%__MODULE__{} = lens, data, default) do
    case get(lens, data) do
      nil -> set(lens, data, default)
      _ -> data
    end
  end

  # ============================================================================
  # Collection Operations
  # ============================================================================

  @doc """
  Maps a lens operation over a collection.

  ## Examples

      name_lens = Lens.key(:name)
      users = [%{name: "alice"}, %{name: "bob"}]

      Lens.map_get(name_lens, users)
      #=> ["alice", "bob"]

      Lens.map_update(name_lens, users, &String.upcase/1)
      #=> [%{name: "ALICE"}, %{name: "BOB"}]
  """
  @spec map_get(t(s, a), [s]) :: [a] when s: any(), a: any()
  def map_get(%__MODULE__{} = lens, collection) do
    Enum.map(collection, &get(lens, &1))
  end

  @spec map_set(t(s, a), [s], a) :: [s] when s: any(), a: any()
  def map_set(%__MODULE__{} = lens, collection, value) do
    Enum.map(collection, &set(lens, &1, value))
  end

  @spec map_update(t(s, a), [s], (a -> a)) :: [s] when s: any(), a: any()
  def map_update(%__MODULE__{} = lens, collection, fun) when is_function(fun, 1) do
    Enum.map(collection, &update(lens, &1, fun))
  end

  @doc """
  Alias for `map_update/3`.
  """
  @spec map_over(t(s, a), [s], (a -> a)) :: [s] when s: any(), a: any()
  def map_over(lens, collection, fun), do: map_update(lens, collection, fun)

  # ============================================================================
  # Predicate-based Operations
  # ============================================================================

  @doc """
  Updates the value only if it satisfies a predicate.

  ## Examples

      lens = Lens.key(:age)

      # Update only if positive
      Lens.update_when(lens, %{age: 25}, &(&1 > 0), &(&1 + 1))
      #=> %{age: 26}

      # No-op when predicate fails
      Lens.update_when(lens, %{age: -1}, &(&1 > 0), &(&1 + 1))
      #=> %{age: -1}
  """
  @spec update_when(t(s, a), s, (a -> boolean()), (a -> a)) :: s when s: any(), a: any()
  def update_when(%__MODULE__{} = lens, data, predicate, fun)
      when is_function(predicate, 1) and is_function(fun, 1) do
    value = get(lens, data)

    if predicate.(value) do
      set(lens, data, fun.(value))
    else
      data
    end
  end

  @doc """
  Checks if the focused value satisfies a predicate.

  ## Examples

      lens = Lens.key(:age)
      Lens.matches?(lens, %{age: 25}, &(&1 >= 18))  #=> true
      Lens.matches?(lens, %{age: 15}, &(&1 >= 18))  #=> false
  """
  @spec matches?(t(s, a), s, (a -> boolean())) :: boolean() when s: any(), a: any()
  def matches?(%__MODULE__{} = lens, data, predicate) when is_function(predicate, 1) do
    predicate.(get(lens, data))
  end

  # ============================================================================
  # Conversion Operations
  # ============================================================================

  @doc """
  Creates a lens that applies a transformation on get and its inverse on set.

  Useful for viewing data in a different format while maintaining the original structure.

  ## Examples

      # Store as integer, view as string
      string_lens = Lens.key(:count)
        |> Lens.iso(&Integer.to_string/1, &String.to_integer/1)

      data = %{count: 42}
      Lens.get(string_lens, data)        #=> "42"
      Lens.set(string_lens, data, "100") #=> %{count: 100}

      # Store as cents, view as dollars
      dollars_lens = Lens.key(:price_cents)
        |> Lens.iso(&(&1 / 100), &(&1 * 100))

      Lens.get(dollars_lens, %{price_cents: 1999})  #=> 19.99
  """
  @spec iso(t(s, a), (a -> b), (b -> a)) :: t(s, b) when s: any(), a: any(), b: any()
  def iso(%__MODULE__{} = lens, get_transform, set_transform)
      when is_function(get_transform, 1) and is_function(set_transform, 1) do
    make(
      fn data -> get_transform.(get(lens, data)) end,
      fn data, value -> set(lens, data, set_transform.(value)) end
    )
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Returns whether the focused value is nil.

  ## Examples

      lens = Lens.key(:name)
      Lens.nil?(lens, %{name: nil})    #=> true
      Lens.nil?(lens, %{name: "Bob"})  #=> false
  """
  @spec nil?(t(s, any()), s) :: boolean() when s: any()
  def nil?(%__MODULE__{} = lens, data) do
    get(lens, data) == nil
  end

  @doc """
  Returns whether the focused value is present (not nil).

  ## Examples

      lens = Lens.key(:name)
      Lens.present?(lens, %{name: "Alice"})  #=> true
      Lens.present?(lens, %{name: nil})      #=> false
  """
  @spec present?(t(s, any()), s) :: boolean() when s: any()
  def present?(%__MODULE__{} = lens, data) do
    get(lens, data) != nil
  end

  @doc """
  Focuses on multiple keys, returning a map of key => value.

  ## Examples

      lens = Lens.keys([:name, :email])
      Lens.get(lens, %{name: "Alice", email: "a@b.c", age: 30})
      #=> %{name: "Alice", email: "a@b.c"}
  """
  @spec keys([atom() | String.t()]) :: t(map(), map())
  def keys(key_list) when is_list(key_list) do
    make(
      fn data -> Map.take(data, key_list) end,
      fn data, values -> Map.merge(data, values) end
    )
  end

  @doc """
  Creates a lens that focuses on a key, creating nested maps if they don't exist.

  ## Examples

      lens = Lens.path_force([:a, :b, :c])
      Lens.set(lens, %{}, "value")
      #=> %{a: %{b: %{c: "value"}}}
  """
  @spec path_force([atom() | String.t()]) :: t(map(), any())
  def path_force(key_path) when is_list(key_path) do
    make(
      fn data -> get_in(data, key_path) end,
      fn data, value -> force_put_in(data, key_path, value) end
    )
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Safe get_in that works with structs
  defp safe_get_in(data, keys) do
    Enum.reduce_while(keys, data, fn key, acc ->
      case acc do
        nil -> {:halt, nil}
        %{} = map -> {:cont, Map.get(map, key)}
        _ -> {:halt, nil}
      end
    end)
  end

  defp put_in_path(data, keys, value) do
    # Safely put value at nested path, creating intermediate maps if needed
    put_in(data, Enum.map(keys, &Access.key(&1, %{})), value)
  rescue
    # Fallback for structs or other types
    _ -> force_put_in(data, keys, value)
  end

  defp force_put_in(data, [key], value) do
    Map.put(data || %{}, key, value)
  end

  defp force_put_in(data, [key | rest], value) do
    current = Map.get(data || %{}, key, %{})
    Map.put(data || %{}, key, force_put_in(current, rest, value))
  end
end
