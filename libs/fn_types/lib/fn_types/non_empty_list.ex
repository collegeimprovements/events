defmodule FnTypes.NonEmptyList do
  @moduledoc """
  A list that is guaranteed to have at least one element.

  NonEmptyList provides type-safe operations on lists that can never be empty,
  eliminating runtime errors from operations like `hd/1`, `List.first/1`, etc.

  ## Implemented Behaviours

  - `FnTypes.Behaviours.Mappable` (Functor) - map
  - `FnTypes.Behaviours.Appendable` (Semigroup) - combine
  - `FnTypes.Behaviours.Reducible` (Foldable) - fold_left, fold_right

  ## Representation

  Internally represented as `{head, tail}` where:
  - `head` is the first element (guaranteed to exist)
  - `tail` is a regular list (can be empty)

  ## Why NonEmptyList?

  Many operations are only valid on non-empty lists:

      # These can crash on empty lists!
      hd([])           # ** (ArgumentError)
      List.first([])   # nil (silent failure)
      Enum.max([])     # ** (Enum.EmptyError)
      Enum.reduce([])  # ** (Enum.EmptyError)

  With NonEmptyList, these are compile-time guarantees:

      # Safe - we know it has at least one element
      NonEmptyList.head(nel)  # Always returns a value
      NonEmptyList.reduce(nel, &+/2)  # No initial value needed

  ## Usage

      alias FnTypes.NonEmptyList, as: NEL

      # Create from known elements
      nel = NEL.new(1, [2, 3, 4])
      #=> {1, [2, 3, 4]}

      # Safe conversion from regular list
      case NEL.from_list([1, 2, 3]) do
        {:ok, nel} -> NEL.head(nel)
        :error -> :list_was_empty
      end

      # Or with bang version when you're certain
      nel = NEL.from_list!([1, 2, 3])

  ## Pattern Matching

  You can pattern match on the internal structure:

      {head, tail} = nel
      # head is guaranteed to exist

  ## Functor/Monad Operations

      nel
      |> NEL.map(&(&1 * 2))
      |> NEL.filter(&(&1 > 5))  # Returns Result, might become empty
      |> Result.map(&NEL.to_list/1)

  """

  @behaviour FnTypes.Behaviours.Mappable
  @behaviour FnTypes.Behaviours.Appendable
  @behaviour FnTypes.Behaviours.Reducible

  alias FnTypes.{Result, Maybe}

  # ============================================
  # Types
  # ============================================

  @type t(a) :: {a, [a]}
  @type t() :: t(term())

  # ============================================
  # Construction
  # ============================================

  @doc """
  Creates a NonEmptyList from a head and tail.

  ## Examples

      iex> NonEmptyList.new(1, [2, 3])
      {1, [2, 3]}

      iex> NonEmptyList.new("only")
      {"only", []}
  """
  @spec new(a, [a]) :: t(a) when a: term()
  def new(head, tail \\ []) when is_list(tail), do: {head, tail}

  @doc """
  Creates a singleton NonEmptyList.

  ## Examples

      iex> NonEmptyList.singleton(42)
      {42, []}
  """
  @spec singleton(a) :: t(a) when a: term()
  def singleton(value), do: {value, []}

  @doc """
  Creates a NonEmptyList from a regular list.

  Returns `{:ok, nel}` if list is non-empty, `:error` if empty.

  ## Examples

      iex> NonEmptyList.from_list([1, 2, 3])
      {:ok, {1, [2, 3]}}

      iex> NonEmptyList.from_list([])
      :error
  """
  @spec from_list([a]) :: {:ok, t(a)} | :error when a: term()
  def from_list([]), do: :error
  def from_list([head | tail]), do: {:ok, {head, tail}}

  @doc """
  Creates a NonEmptyList from a list, raising on empty.

  ## Examples

      iex> NonEmptyList.from_list!([1, 2, 3])
      {1, [2, 3]}

      iex> NonEmptyList.from_list!([])
      ** (ArgumentError) Cannot create NonEmptyList from empty list
  """
  @spec from_list!([a]) :: t(a) when a: term()
  def from_list!([]), do: raise(ArgumentError, "Cannot create NonEmptyList from empty list")
  def from_list!([head | tail]), do: {head, tail}

  @doc """
  Creates a NonEmptyList from a list, returning Maybe.

  ## Examples

      iex> NonEmptyList.from_list_maybe([1, 2])
      {:some, {1, [2]}}

      iex> NonEmptyList.from_list_maybe([])
      :none
  """
  @spec from_list_maybe([a]) :: Maybe.t(t(a)) when a: term()
  def from_list_maybe([]), do: :none
  def from_list_maybe([head | tail]), do: {:some, {head, tail}}

  @doc """
  Creates a NonEmptyList of n repeated elements.

  ## Examples

      iex> NonEmptyList.repeat(0, 3)
      {0, [0, 0]}

      iex> NonEmptyList.repeat("x", 1)
      {"x", []}
  """
  @spec repeat(a, pos_integer()) :: t(a) when a: term()
  def repeat(value, n) when is_integer(n) and n > 0 do
    {value, List.duplicate(value, n - 1)}
  end

  @doc """
  Creates a NonEmptyList from a range.

  ## Examples

      iex> NonEmptyList.range(1, 5)
      {1, [2, 3, 4, 5]}

      iex> NonEmptyList.range(5, 5)
      {5, []}

      iex> NonEmptyList.range(5, 3)
      {5, [4, 3]}
  """
  @spec range(integer(), integer()) :: t(integer())
  def range(first, last) when first <= last do
    [head | tail] = Enum.to_list(first..last//1)
    {head, tail}
  end

  def range(first, last) when first > last do
    [head | tail] = Enum.to_list(first..last//-1)
    {head, tail}
  end

  # ============================================
  # Access
  # ============================================

  @doc """
  Returns the first element (head).

  Always safe - NonEmptyList always has at least one element.

  ## Examples

      iex> NonEmptyList.head({1, [2, 3]})
      1

      iex> NonEmptyList.head({"only", []})
      "only"
  """
  @spec head(t(a)) :: a when a: term()
  def head({h, _}), do: h

  @doc """
  Returns the tail as a regular list.

  ## Examples

      iex> NonEmptyList.tail({1, [2, 3]})
      [2, 3]

      iex> NonEmptyList.tail({1, []})
      []
  """
  @spec tail(t(a)) :: [a] when a: term()
  def tail({_, t}), do: t

  @doc """
  Returns the last element.

  Always safe - NonEmptyList always has at least one element.

  ## Examples

      iex> NonEmptyList.last({1, [2, 3]})
      3

      iex> NonEmptyList.last({1, []})
      1
  """
  @spec last(t(a)) :: a when a: term()
  def last({head, []}), do: head
  def last({_, tail}), do: List.last(tail)

  @doc """
  Returns the init (all but last) as a regular list.

  ## Examples

      iex> NonEmptyList.init({1, [2, 3]})
      [1, 2]

      iex> NonEmptyList.init({1, []})
      []
  """
  @spec init(t(a)) :: [a] when a: term()
  def init({_, []}), do: []
  def init({head, tail}), do: [head | Enum.take(tail, length(tail) - 1)]

  @doc """
  Returns element at index (0-based).

  ## Examples

      iex> NonEmptyList.at({1, [2, 3]}, 0)
      {:ok, 1}

      iex> NonEmptyList.at({1, [2, 3]}, 2)
      {:ok, 3}

      iex> NonEmptyList.at({1, [2, 3]}, 10)
      :error
  """
  @spec at(t(a), non_neg_integer()) :: {:ok, a} | :error when a: term()
  def at({head, _}, 0), do: {:ok, head}
  def at({_, tail}, index) when index > 0, do: fetch_at(tail, index - 1)

  defp fetch_at([], _), do: :error
  defp fetch_at([h | _], 0), do: {:ok, h}
  defp fetch_at([_ | t], n), do: fetch_at(t, n - 1)

  @doc """
  Returns element at index, raising on out of bounds.

  ## Examples

      iex> NonEmptyList.at!({1, [2, 3]}, 1)
      2
  """
  @spec at!(t(a), non_neg_integer()) :: a when a: term()
  def at!(nel, index) do
    case at(nel, index) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "index #{index} out of bounds"
    end
  end

  # ============================================
  # Predicates
  # ============================================

  @doc """
  Returns the length of the NonEmptyList (always >= 1).

  ## Examples

      iex> NonEmptyList.size({1, [2, 3]})
      3

      iex> NonEmptyList.size({1, []})
      1
  """
  @spec size(t(a)) :: pos_integer() when a: term()
  def size({_, tail}), do: 1 + Kernel.length(tail)

  @doc """
  Checks if this is a singleton (exactly one element).

  ## Examples

      iex> NonEmptyList.singleton?({1, []})
      true

      iex> NonEmptyList.singleton?({1, [2]})
      false
  """
  @spec singleton?(t(a)) :: boolean() when a: term()
  def singleton?({_, []}), do: true
  def singleton?(_), do: false

  @doc """
  Checks if element exists in the list.

  ## Examples

      iex> NonEmptyList.member?({1, [2, 3]}, 2)
      true

      iex> NonEmptyList.member?({1, [2, 3]}, 5)
      false
  """
  @spec member?(t(a), a) :: boolean() when a: term()
  def member?({head, tail}, element), do: head == element or element in tail

  @doc """
  Checks if all elements satisfy predicate.

  ## Examples

      iex> NonEmptyList.all?({2, [4, 6]}, &(rem(&1, 2) == 0))
      true

      iex> NonEmptyList.all?({2, [3, 4]}, &(rem(&1, 2) == 0))
      false
  """
  @spec all?(t(a), (a -> boolean())) :: boolean() when a: term()
  def all?({head, tail}, pred) when is_function(pred, 1) do
    pred.(head) and Enum.all?(tail, pred)
  end

  @doc """
  Checks if any element satisfies predicate.

  ## Examples

      iex> NonEmptyList.any?({1, [2, 3]}, &(&1 > 2))
      true

      iex> NonEmptyList.any?({1, [2, 3]}, &(&1 > 10))
      false
  """
  @spec any?(t(a), (a -> boolean())) :: boolean() when a: term()
  def any?({head, tail}, pred) when is_function(pred, 1) do
    pred.(head) or Enum.any?(tail, pred)
  end

  # ============================================
  # Transformation
  # ============================================

  @doc """
  Maps a function over all elements.

  ## Examples

      iex> NonEmptyList.map({1, [2, 3]}, &(&1 * 2))
      {2, [4, 6]}
  """
  @impl FnTypes.Behaviours.Mappable
  @spec map(t(a), (a -> b)) :: t(b) when a: term(), b: term()
  def map({head, tail}, fun) when is_function(fun, 1) do
    {fun.(head), Enum.map(tail, fun)}
  end

  @doc """
  Maps a function over elements with index.

  ## Examples

      iex> NonEmptyList.map_with_index({:a, [:b, :c]}, fn el, idx -> {el, idx} end)
      {{:a, 0}, [{:b, 1}, {:c, 2}]}
  """
  @spec map_with_index(t(a), (a, non_neg_integer() -> b)) :: t(b) when a: term(), b: term()
  def map_with_index({head, tail}, fun) when is_function(fun, 2) do
    new_head = fun.(head, 0)

    new_tail =
      tail
      |> Enum.with_index(1)
      |> Enum.map(fn {el, idx} -> fun.(el, idx) end)

    {new_head, new_tail}
  end

  @doc """
  Flat maps a function that returns NonEmptyList.

  ## Examples

      iex> NonEmptyList.flat_map({1, [2]}, fn x -> NonEmptyList.new(x, [x * 10]) end)
      {1, [10, 2, 20]}
  """
  @spec flat_map(t(a), (a -> t(b))) :: t(b) when a: term(), b: term()
  def flat_map({head, tail}, fun) when is_function(fun, 1) do
    {new_head, new_head_tail} = fun.(head)
    rest = Enum.flat_map(tail, fn el -> to_list(fun.(el)) end)
    {new_head, new_head_tail ++ rest}
  end

  @doc """
  Filters elements. Returns Result since filtering might empty the list.

  ## Examples

      iex> NonEmptyList.filter({1, [2, 3, 4]}, &(rem(&1, 2) == 0))
      {:ok, {2, [4]}}

      iex> NonEmptyList.filter({1, [3, 5]}, &(rem(&1, 2) == 0))
      :error
  """
  @spec filter(t(a), (a -> boolean())) :: {:ok, t(a)} | :error when a: term()
  def filter(nel, pred) when is_function(pred, 1) do
    nel
    |> to_list()
    |> Enum.filter(pred)
    |> from_list()
  end

  @doc """
  Rejects elements. Returns Result since rejecting might empty the list.

  ## Examples

      iex> NonEmptyList.reject({1, [2, 3, 4]}, &(rem(&1, 2) == 0))
      {:ok, {1, [3]}}
  """
  @spec reject(t(a), (a -> boolean())) :: {:ok, t(a)} | :error when a: term()
  def reject(nel, pred) when is_function(pred, 1) do
    filter(nel, fn x -> not pred.(x) end)
  end

  @doc """
  Takes the first n elements. Returns Result if n might exceed length.

  ## Examples

      iex> NonEmptyList.take({1, [2, 3, 4]}, 2)
      {:ok, {1, [2]}}

      iex> NonEmptyList.take({1, [2, 3]}, 0)
      :error
  """
  @spec take(t(a), non_neg_integer()) :: {:ok, t(a)} | :error when a: term()
  def take(_, 0), do: :error

  def take({head, tail}, n) when n > 0 do
    {:ok, {head, Enum.take(tail, n - 1)}}
  end

  @doc """
  Takes the first n elements, unsafe version.

  ## Examples

      iex> NonEmptyList.take!({1, [2, 3, 4]}, 2)
      {1, [2]}
  """
  @spec take!(t(a), pos_integer()) :: t(a) when a: term()
  def take!(nel, n) when n > 0 do
    case take(nel, n) do
      {:ok, result} -> result
      :error -> raise ArgumentError, "Cannot take #{n} elements"
    end
  end

  @doc """
  Drops the first n elements. Returns Result since might empty the list.

  ## Examples

      iex> NonEmptyList.drop({1, [2, 3, 4]}, 2)
      {:ok, {3, [4]}}

      iex> NonEmptyList.drop({1, [2]}, 3)
      :error
  """
  @spec drop(t(a), non_neg_integer()) :: {:ok, t(a)} | :error when a: term()
  def drop(nel, 0), do: {:ok, nel}

  def drop(nel, n) when n > 0 do
    nel
    |> to_list()
    |> Enum.drop(n)
    |> from_list()
  end

  @doc """
  Reverses the NonEmptyList.

  ## Examples

      iex> NonEmptyList.reverse({1, [2, 3]})
      {3, [2, 1]}

      iex> NonEmptyList.reverse({1, []})
      {1, []}
  """
  @spec reverse(t(a)) :: t(a) when a: term()
  def reverse({head, []}), do: {head, []}

  def reverse({head, tail}) do
    [new_head | new_tail] = Enum.reverse([head | tail])
    {new_head, new_tail}
  end

  @doc """
  Sorts the NonEmptyList.

  ## Examples

      iex> NonEmptyList.sort({3, [1, 2]})
      {1, [2, 3]}
  """
  @spec sort(t(a)) :: t(a) when a: term()
  def sort(nel) do
    [head | tail] = nel |> to_list() |> Enum.sort()
    {head, tail}
  end

  @doc """
  Sorts by a key function.

  ## Examples

      iex> NonEmptyList.sort_by({%{n: 3}, [%{n: 1}, %{n: 2}]}, & &1.n)
      {%{n: 1}, [%{n: 2}, %{n: 3}]}
  """
  @spec sort_by(t(a), (a -> term())) :: t(a) when a: term()
  def sort_by(nel, key_fun) when is_function(key_fun, 1) do
    [head | tail] = nel |> to_list() |> Enum.sort_by(key_fun)
    {head, tail}
  end

  @doc """
  Removes duplicates.

  ## Examples

      iex> NonEmptyList.uniq({1, [2, 1, 3, 2]})
      {1, [2, 3]}
  """
  @spec uniq(t(a)) :: t(a) when a: term()
  def uniq(nel) do
    [head | tail] = nel |> to_list() |> Enum.uniq()
    {head, tail}
  end

  @doc """
  Removes duplicates by key function.

  ## Examples

      iex> NonEmptyList.uniq_by({%{id: 1, n: "a"}, [%{id: 2, n: "b"}, %{id: 1, n: "c"}]}, & &1.id)
      {%{id: 1, n: "a"}, [%{id: 2, n: "b"}]}
  """
  @spec uniq_by(t(a), (a -> term())) :: t(a) when a: term()
  def uniq_by(nel, key_fun) when is_function(key_fun, 1) do
    [head | tail] = nel |> to_list() |> Enum.uniq_by(key_fun)
    {head, tail}
  end

  @doc """
  Flattens a NonEmptyList of NonEmptyLists.

  ## Examples

      iex> inner1 = NonEmptyList.new(1, [2])
      iex> inner2 = NonEmptyList.new(3, [4])
      iex> NonEmptyList.flatten(NonEmptyList.new(inner1, [inner2]))
      {1, [2, 3, 4]}
  """
  @spec flatten(t(t(a))) :: t(a) when a: term()
  def flatten(nel_of_nels) do
    nel_of_nels
    |> to_list()
    |> Enum.flat_map(&to_list/1)
    |> from_list!()
  end

  @doc """
  Intersperses an element between all elements.

  ## Examples

      iex> NonEmptyList.intersperse({1, [2, 3]}, 0)
      {1, [0, 2, 0, 3]}

      iex> NonEmptyList.intersperse({1, []}, 0)
      {1, []}
  """
  @spec intersperse(t(a), a) :: t(a) when a: term()
  def intersperse({head, []}, _sep), do: {head, []}

  def intersperse({head, tail}, sep) do
    new_tail =
      tail
      |> Enum.flat_map(fn el -> [sep, el] end)

    {head, new_tail}
  end

  # ============================================
  # Reduction
  # ============================================

  @doc """
  Reduces without initial value (safe - list is never empty).

  ## Examples

      iex> NonEmptyList.reduce({1, [2, 3]}, &+/2)
      6

      iex> NonEmptyList.reduce({5, []}, &+/2)
      5
  """
  @spec reduce(t(a), (a, a -> a)) :: a when a: term()
  def reduce({head, []}, _fun), do: head
  def reduce({head, tail}, fun) when is_function(fun, 2), do: Enum.reduce(tail, head, fun)

  @doc """
  Reduces with initial value.

  ## Examples

      iex> NonEmptyList.fold({1, [2, 3]}, 10, &+/2)
      16
  """
  @spec fold(t(a), b, (a, b -> b)) :: b when a: term(), b: term()
  def fold({head, tail}, acc, fun) when is_function(fun, 2) do
    Enum.reduce([head | tail], acc, fun)
  end

  @doc """
  Returns the maximum element (safe - list is never empty).

  ## Examples

      iex> NonEmptyList.max({3, [1, 4, 1, 5]})
      5
  """
  @spec max(t(a)) :: a when a: term()
  def max(nel), do: nel |> to_list() |> Enum.max()

  @doc """
  Returns the minimum element (safe - list is never empty).

  ## Examples

      iex> NonEmptyList.min({3, [1, 4, 1, 5]})
      1
  """
  @spec min(t(a)) :: a when a: term()
  def min(nel), do: nel |> to_list() |> Enum.min()

  @doc """
  Returns element with maximum value by key function.

  ## Examples

      iex> NonEmptyList.max_by({%{n: 1}, [%{n: 3}, %{n: 2}]}, & &1.n)
      %{n: 3}
  """
  @spec max_by(t(a), (a -> term())) :: a when a: term()
  def max_by(nel, key_fun) when is_function(key_fun, 1) do
    nel |> to_list() |> Enum.max_by(key_fun)
  end

  @doc """
  Returns element with minimum value by key function.

  ## Examples

      iex> NonEmptyList.min_by({%{n: 1}, [%{n: 3}, %{n: 2}]}, & &1.n)
      %{n: 1}
  """
  @spec min_by(t(a), (a -> term())) :: a when a: term()
  def min_by(nel, key_fun) when is_function(key_fun, 1) do
    nel |> to_list() |> Enum.min_by(key_fun)
  end

  @doc """
  Sums numeric elements.

  ## Examples

      iex> NonEmptyList.sum({1, [2, 3]})
      6
  """
  @spec sum(t(number())) :: number()
  def sum(nel), do: nel |> to_list() |> Enum.sum()

  @doc """
  Multiplies numeric elements.

  ## Examples

      iex> NonEmptyList.product({2, [3, 4]})
      24
  """
  @spec product(t(number())) :: number()
  def product(nel), do: nel |> to_list() |> Enum.product()

  # ============================================
  # Combination
  # ============================================

  @doc """
  Prepends an element.

  ## Examples

      iex> NonEmptyList.cons({2, [3]}, 1)
      {1, [2, 3]}
  """
  @spec cons(t(a), a) :: t(a) when a: term()
  def cons({head, tail}, new_head), do: {new_head, [head | tail]}

  @doc """
  Appends an element.

  ## Examples

      iex> NonEmptyList.append({1, [2]}, 3)
      {1, [2, 3]}
  """
  @spec append(t(a), a) :: t(a) when a: term()
  def append({head, tail}, element), do: {head, tail ++ [element]}

  @doc """
  Concatenates two NonEmptyLists.

  ## Examples

      iex> NonEmptyList.concat({1, [2]}, {3, [4]})
      {1, [2, 3, 4]}
  """
  @spec concat(t(a), t(a)) :: t(a) when a: term()
  def concat({h1, t1}, {h2, t2}), do: {h1, t1 ++ [h2 | t2]}

  @doc """
  Concatenates a NonEmptyList with a regular list.

  ## Examples

      iex> NonEmptyList.concat_list({1, [2]}, [3, 4])
      {1, [2, 3, 4]}
  """
  @spec concat_list(t(a), [a]) :: t(a) when a: term()
  def concat_list({head, tail}, list) when is_list(list), do: {head, tail ++ list}

  @doc """
  Zips two NonEmptyLists together.

  ## Examples

      iex> NonEmptyList.zip({1, [2, 3]}, {:a, [:b, :c]})
      {{1, :a}, [{2, :b}, {3, :c}]}
  """
  @spec zip(t(a), t(b)) :: t({a, b}) when a: term(), b: term()
  def zip({h1, t1}, {h2, t2}) do
    zipped_tail = Enum.zip(t1, t2)
    {{h1, h2}, zipped_tail}
  end

  @doc """
  Zips with a combining function.

  ## Examples

      iex> NonEmptyList.zip_with({1, [2]}, {10, [20]}, &+/2)
      {11, [22]}
  """
  @spec zip_with(t(a), t(b), (a, b -> c)) :: t(c) when a: term(), b: term(), c: term()
  def zip_with({h1, t1}, {h2, t2}, fun) when is_function(fun, 2) do
    new_head = fun.(h1, h2)
    new_tail = Enum.zip_with(t1, t2, fun)
    {new_head, new_tail}
  end

  @doc """
  Unzips a NonEmptyList of tuples.

  ## Examples

      iex> NonEmptyList.unzip({{1, :a}, [{2, :b}, {3, :c}]})
      {{1, [2, 3]}, {:a, [:b, :c]}}
  """
  @spec unzip(t({a, b})) :: {t(a), t(b)} when a: term(), b: term()
  def unzip({{h1, h2}, tail}) do
    {t1, t2} = Enum.unzip(tail)
    {{h1, t1}, {h2, t2}}
  end

  # ============================================
  # Grouping & Partitioning
  # ============================================

  @doc """
  Groups elements by key function.

  Returns a map where each key maps to a NonEmptyList.

  ## Examples

      iex> NonEmptyList.group_by({1, [2, 3, 4]}, &rem(&1, 2))
      %{0 => {2, [4]}, 1 => {1, [3]}}
  """
  @spec group_by(t(a), (a -> k)) :: %{k => t(a)} when a: term(), k: term()
  def group_by(nel, key_fun) when is_function(key_fun, 1) do
    nel
    |> to_list()
    |> Enum.group_by(key_fun)
    |> Map.new(fn {k, v} -> {k, from_list!(v)} end)
  end

  @doc """
  Partitions into two lists based on predicate.

  ## Examples

      iex> NonEmptyList.partition({1, [2, 3, 4]}, &(rem(&1, 2) == 0))
      {[2, 4], [1, 3]}
  """
  @spec partition(t(a), (a -> boolean())) :: {[a], [a]} when a: term()
  def partition(nel, pred) when is_function(pred, 1) do
    nel |> to_list() |> Enum.split_with(pred)
  end

  @doc """
  Splits at position. First part is guaranteed non-empty if n > 0.

  ## Examples

      iex> NonEmptyList.split({1, [2, 3, 4]}, 2)
      {{1, [2]}, [3, 4]}
  """
  @spec split(t(a), pos_integer()) :: {t(a), [a]} when a: term()
  def split(nel, n) when n > 0 do
    {first, rest} = nel |> to_list() |> Enum.split(n)
    {from_list!(first), rest}
  end

  # ============================================
  # Conversion
  # ============================================

  @doc """
  Converts to a regular list.

  ## Examples

      iex> NonEmptyList.to_list({1, [2, 3]})
      [1, 2, 3]
  """
  @spec to_list(t(a)) :: [a, ...] when a: term()
  @impl FnTypes.Behaviours.Reducible
  def to_list({head, tail}), do: [head | tail]

  @doc """
  Converts to MapSet.

  ## Examples

      iex> NonEmptyList.to_mapset({1, [2, 1, 3]})
      MapSet.new([1, 2, 3])
  """
  @spec to_mapset(t(a)) :: MapSet.t(a) when a: term()
  def to_mapset(nel), do: nel |> to_list() |> MapSet.new()

  @doc """
  Converts to a stream.

  ## Examples

      iex> NonEmptyList.to_stream({1, [2, 3]}) |> Enum.take(2)
      [1, 2]
  """
  @spec to_stream(t(a)) :: Enumerable.t() when a: term()
  def to_stream(nel), do: nel |> to_list() |> Stream.map(& &1)

  # ============================================
  # Traversal (Monadic)
  # ============================================

  @doc """
  Traverses with a Result-returning function.

  ## Examples

      iex> NonEmptyList.traverse_result({1, [2, 3]}, fn x -> {:ok, x * 2} end)
      {:ok, {2, [4, 6]}}

      iex> NonEmptyList.traverse_result({1, [2, 3]}, fn
      ...>   2 -> {:error, :bad}
      ...>   x -> {:ok, x * 2}
      ...> end)
      {:error, :bad}
  """
  @spec traverse_result(t(a), (a -> Result.t(b, e))) :: Result.t(t(b), e)
        when a: term(), b: term(), e: term()
  def traverse_result(nel, fun) when is_function(fun, 1) do
    nel
    |> to_list()
    |> Result.traverse(fun)
    |> Result.and_then(&from_list/1)
    |> case do
      {:ok, result} -> {:ok, result}
      :error -> {:error, :empty_after_traverse}
      error -> error
    end
  end

  @doc """
  Traverses with a Maybe-returning function.

  ## Examples

      iex> NonEmptyList.traverse_maybe({1, [2, 3]}, fn x -> {:some, x * 2} end)
      {:some, {2, [4, 6]}}

      iex> NonEmptyList.traverse_maybe({1, [2, 3]}, fn
      ...>   2 -> :none
      ...>   x -> {:some, x * 2}
      ...> end)
      :none
  """
  @spec traverse_maybe(t(a), (a -> Maybe.t(b))) :: Maybe.t(t(b)) when a: term(), b: term()
  def traverse_maybe(nel, fun) when is_function(fun, 1) do
    nel
    |> to_list()
    |> Maybe.traverse(fun)
    |> Maybe.and_then(fn list ->
      case from_list(list) do
        {:ok, result} -> {:some, result}
        :error -> :none
      end
    end)
  end

  # ============================================
  # Utilities
  # ============================================

  @doc """
  Taps into each element for side effects.

  ## Examples

      NonEmptyList.each({1, [2, 3]}, &IO.inspect/1)
      # Prints: 1, 2, 3
  """
  @spec each(t(a), (a -> any())) :: :ok when a: term()
  def each({head, tail}, fun) when is_function(fun, 1) do
    fun.(head)
    Enum.each(tail, fun)
    :ok
  end

  @doc """
  Finds first element matching predicate.

  ## Examples

      iex> NonEmptyList.find({1, [2, 3, 4]}, &(&1 > 2))
      {:some, 3}

      iex> NonEmptyList.find({1, [2, 3]}, &(&1 > 10))
      :none
  """
  @spec find(t(a), (a -> boolean())) :: Maybe.t(a) when a: term()
  def find(nel, pred) when is_function(pred, 1) do
    case Enum.find(to_list(nel), pred) do
      nil -> :none
      value -> {:some, value}
    end
  end

  @doc """
  Returns index of first matching element.

  ## Examples

      iex> NonEmptyList.find_index({:a, [:b, :c]}, &(&1 == :b))
      {:some, 1}

      iex> NonEmptyList.find_index({:a, [:b, :c]}, &(&1 == :z))
      :none
  """
  @spec find_index(t(a), (a -> boolean())) :: Maybe.t(non_neg_integer()) when a: term()
  def find_index(nel, pred) when is_function(pred, 1) do
    case Enum.find_index(to_list(nel), pred) do
      nil -> :none
      idx -> {:some, idx}
    end
  end

  @doc """
  Counts elements matching predicate.

  ## Examples

      iex> NonEmptyList.count({1, [2, 3, 4]}, &(rem(&1, 2) == 0))
      2
  """
  @spec count(t(a), (a -> boolean())) :: non_neg_integer() when a: term()
  def count(nel, pred) when is_function(pred, 1) do
    nel |> to_list() |> Enum.count(pred)
  end

  @doc """
  Creates frequencies map.

  ## Examples

      iex> NonEmptyList.frequencies({:a, [:b, :a, :c, :a]})
      %{a: 3, b: 1, c: 1}
  """
  @spec frequencies(t(a)) :: %{a => pos_integer()} when a: term()
  def frequencies(nel), do: nel |> to_list() |> Enum.frequencies()

  @doc """
  Creates frequencies by key function.

  ## Examples

      iex> NonEmptyList.frequencies_by({1, [2, 3, 4, 5]}, &rem(&1, 2))
      %{0 => 2, 1 => 3}
  """
  @spec frequencies_by(t(a), (a -> k)) :: %{k => pos_integer()} when a: term(), k: term()
  def frequencies_by(nel, key_fun) when is_function(key_fun, 1) do
    nel |> to_list() |> Enum.frequencies_by(key_fun)
  end

  @doc """
  Joins elements into a string.

  ## Examples

      iex> NonEmptyList.join({1, [2, 3]}, ", ")
      "1, 2, 3"

      iex> NonEmptyList.join({"a", ["b", "c"]})
      "abc"
  """
  @spec join(t(a), String.t()) :: String.t() when a: term()
  def join(nel, joiner \\ "") do
    nel |> to_list() |> Enum.join(joiner)
  end

  @doc """
  Updates element at index.

  ## Examples

      iex> NonEmptyList.update_at({1, [2, 3]}, 1, &(&1 * 10))
      {1, [20, 3]}

      iex> NonEmptyList.update_at({1, [2, 3]}, 0, &(&1 * 10))
      {10, [2, 3]}
  """
  @spec update_at(t(a), non_neg_integer(), (a -> a)) :: t(a) when a: term()
  def update_at({head, tail}, 0, fun) when is_function(fun, 1), do: {fun.(head), tail}

  def update_at({head, tail}, index, fun) when index > 0 and is_function(fun, 1) do
    {head, List.update_at(tail, index - 1, fun)}
  end

  @doc """
  Replaces element at index.

  ## Examples

      iex> NonEmptyList.replace_at({1, [2, 3]}, 1, 99)
      {1, [99, 3]}
  """
  @spec replace_at(t(a), non_neg_integer(), a) :: t(a) when a: term()
  def replace_at(nel, index, value), do: update_at(nel, index, fn _ -> value end)

  @doc """
  Deletes element at index. Returns Result since might empty list.

  ## Examples

      iex> NonEmptyList.delete_at({1, [2, 3]}, 1)
      {:ok, {1, [3]}}

      iex> NonEmptyList.delete_at({1, []}, 0)
      :error
  """
  @spec delete_at(t(a), non_neg_integer()) :: {:ok, t(a)} | :error when a: term()
  def delete_at(nel, index) do
    nel
    |> to_list()
    |> List.delete_at(index)
    |> from_list()
  end

  @doc """
  Inserts element at index.

  ## Examples

      iex> NonEmptyList.insert_at({1, [3]}, 1, 2)
      {1, [2, 3]}
  """
  @spec insert_at(t(a), non_neg_integer(), a) :: t(a) when a: term()
  def insert_at({head, tail}, 0, value), do: {value, [head | tail]}

  def insert_at({head, tail}, index, value) when index > 0 do
    {head, List.insert_at(tail, index - 1, value)}
  end

  # ============================================
  # Behaviour Implementations
  # ============================================

  @doc """
  Combines two NonEmptyLists (Semigroup.combine).

  Alias for `concat/2`.

  ## Examples

      iex> NonEmptyList.combine({1, [2]}, {3, [4]})
      {1, [2, 3, 4]}
  """
  @impl FnTypes.Behaviours.Appendable
  @spec combine(t(a), t(a)) :: t(a) when a: term()
  def combine(nel1, nel2), do: concat(nel1, nel2)

  @doc """
  Left fold over all elements (Foldable.fold_left).

  ## Examples

      iex> NonEmptyList.fold_left({1, [2, 3]}, 0, &+/2)
      6
  """
  @impl FnTypes.Behaviours.Reducible
  @spec fold_left(t(a), acc, (a, acc -> acc)) :: acc when a: term(), acc: term()
  def fold_left({head, tail}, acc, fun) when is_function(fun, 2) do
    Enum.reduce([head | tail], acc, fun)
  end

  @doc """
  Right fold over all elements (Foldable.fold_right).

  ## Examples

      iex> NonEmptyList.fold_right({1, [2, 3]}, [], fn x, acc -> [x | acc] end)
      [1, 2, 3]
  """
  @impl FnTypes.Behaviours.Reducible
  @spec fold_right(t(a), acc, (a, acc -> acc)) :: acc when a: term(), acc: term()
  def fold_right({head, tail}, acc, fun) when is_function(fun, 2) do
    List.foldr([head | tail], acc, fun)
  end
end
