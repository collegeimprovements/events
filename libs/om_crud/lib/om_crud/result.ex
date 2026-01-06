defmodule OmCrud.Result do
  @moduledoc """
  Type-safe result container for paginated queries.

  This struct wraps query results with pagination metadata,
  providing a consistent interface for list operations.

  ## Structure

      %OmCrud.Result{
        data: [%User{}, %User{}],
        pagination: %OmCrud.Pagination{
          type: :cursor,
          has_more: true,
          has_previous: false,
          start_cursor: "eyJpZCI6...",
          end_cursor: "eyJpZCI6...",
          limit: 20
        }
      }

  ## Usage with Pattern Matching

      case Accounts.list_users() do
        {:ok, %OmCrud.Result{data: users, pagination: %{has_more: true}}} ->
          # Handle paginated results with more pages
        {:ok, %OmCrud.Result{data: users, pagination: nil}} ->
          # Handle results without pagination (limit: :all)
      end

  ## Accessing Data

      {:ok, result} = Accounts.list_users()
      users = result.data
      next_cursor = result.pagination.end_cursor
  """

  alias OmCrud.Pagination

  @type t :: %__MODULE__{
          data: [struct()],
          pagination: Pagination.t() | nil
        }

  @type t(entity) :: %__MODULE__{
          data: [entity],
          pagination: Pagination.t() | nil
        }

  defstruct [:data, :pagination]

  @doc """
  Create a new Result with data and pagination.

  ## Examples

      iex> OmCrud.Result.new([user1, user2], %OmCrud.Pagination{...})
      %OmCrud.Result{data: [user1, user2], pagination: %OmCrud.Pagination{...}}

      iex> OmCrud.Result.new([user1, user2], nil)
      %OmCrud.Result{data: [user1, user2], pagination: nil}
  """
  @spec new([struct()], Pagination.t() | nil) :: t()
  def new(data, pagination) when is_list(data) do
    %__MODULE__{
      data: data,
      pagination: pagination
    }
  end

  @doc """
  Create a Result with no pagination (all records).

  ## Examples

      iex> OmCrud.Result.all([user1, user2])
      %OmCrud.Result{data: [user1, user2], pagination: nil}
  """
  @spec all([struct()]) :: t()
  def all(data) when is_list(data) do
    %__MODULE__{
      data: data,
      pagination: nil
    }
  end

  @doc """
  Check if there are more results after the current page.

  ## Examples

      iex> OmCrud.Result.has_more?(%OmCrud.Result{pagination: %{has_more: true}})
      true

      iex> OmCrud.Result.has_more?(%OmCrud.Result{pagination: nil})
      false
  """
  @spec has_more?(t()) :: boolean()
  def has_more?(%__MODULE__{pagination: nil}), do: false
  def has_more?(%__MODULE__{pagination: %{has_more: has_more}}), do: has_more

  @doc """
  Check if there are previous results before the current page.

  ## Examples

      iex> OmCrud.Result.has_previous?(%OmCrud.Result{pagination: %{has_previous: true}})
      true

      iex> OmCrud.Result.has_previous?(%OmCrud.Result{pagination: nil})
      false
  """
  @spec has_previous?(t()) :: boolean()
  def has_previous?(%__MODULE__{pagination: nil}), do: false
  def has_previous?(%__MODULE__{pagination: %{has_previous: has_previous}}), do: has_previous

  @doc """
  Get the cursor for fetching the next page.

  ## Examples

      iex> OmCrud.Result.next_cursor(%OmCrud.Result{pagination: %{end_cursor: "abc"}})
      "abc"

      iex> OmCrud.Result.next_cursor(%OmCrud.Result{pagination: nil})
      nil
  """
  @spec next_cursor(t()) :: String.t() | nil
  def next_cursor(%__MODULE__{pagination: nil}), do: nil
  def next_cursor(%__MODULE__{pagination: %{end_cursor: cursor}}), do: cursor

  @doc """
  Get the cursor for fetching the previous page.

  ## Examples

      iex> OmCrud.Result.previous_cursor(%OmCrud.Result{pagination: %{start_cursor: "abc"}})
      "abc"

      iex> OmCrud.Result.previous_cursor(%OmCrud.Result{pagination: nil})
      nil
  """
  @spec previous_cursor(t()) :: String.t() | nil
  def previous_cursor(%__MODULE__{pagination: nil}), do: nil
  def previous_cursor(%__MODULE__{pagination: %{start_cursor: cursor}}), do: cursor

  @doc """
  Get the count of records in this result.

  ## Examples

      iex> OmCrud.Result.count(%OmCrud.Result{data: [1, 2, 3]})
      3
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{data: data}), do: length(data)

  @doc """
  Check if the result is empty.

  ## Examples

      iex> OmCrud.Result.empty?(%OmCrud.Result{data: []})
      true

      iex> OmCrud.Result.empty?(%OmCrud.Result{data: [user]})
      false
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{data: []}), do: true
  def empty?(%__MODULE__{data: _}), do: false

  @doc """
  Map over the data in the result.

  ## Examples

      iex> result |> OmCrud.Result.map(&Map.get(&1, :email))
      %OmCrud.Result{data: ["a@test.com", "b@test.com"], pagination: ...}
  """
  @spec map(t(), (struct() -> any())) :: t()
  def map(%__MODULE__{data: data, pagination: pagination}, fun) when is_function(fun, 1) do
    %__MODULE__{
      data: Enum.map(data, fun),
      pagination: pagination
    }
  end

  @doc """
  Filter the data in the result.

  Note: This only filters the current page, not all results.

  ## Examples

      iex> result |> OmCrud.Result.filter(&(&1.active))
      %OmCrud.Result{data: [active_user], pagination: ...}
  """
  @spec filter(t(), (struct() -> boolean())) :: t()
  def filter(%__MODULE__{data: data, pagination: pagination}, fun) when is_function(fun, 1) do
    %__MODULE__{
      data: Enum.filter(data, fun),
      pagination: pagination
    }
  end

  @doc """
  Convert result to a plain map (for JSON serialization).

  ## Examples

      iex> OmCrud.Result.to_map(%OmCrud.Result{...})
      %{data: [...], pagination: %{...}}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{data: data, pagination: nil}) do
    %{data: data, pagination: nil}
  end

  def to_map(%__MODULE__{data: data, pagination: pagination}) do
    %{data: data, pagination: Pagination.to_map(pagination)}
  end
end
