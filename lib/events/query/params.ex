defmodule Events.Query.Params do
  @moduledoc """
  Helpers for working with query parameters from various sources.

  Provides indifferent access (atom or string keys) and normalization
  utilities for params coming from Phoenix controllers, LiveView, etc.

  ## Examples

      # Indifferent access - checks both atom and string keys
      params = %{"limit" => 20, :status => "active"}
      Params.get(params, :limit)   #=> 20
      Params.get(params, :status)  #=> "active"
      Params.get(params, "limit")  #=> 20

      # Normalize params to atom keys (with opts)
      Params.normalize(%{"limit" => 20, "status" => "active"})
      #=> %{limit: 20, status: "active"}

      # Safe normalize with allowed keys only
      Params.normalize(%{"limit" => 20, "evil" => "drop"}, only: [:limit, :status])
      #=> %{limit: 20}

      # Use with Query
      User
      |> Query.maybe(:status, Params.get(params, :status))
      |> Query.paginate(:cursor, limit: Params.get(params, :limit), after: Params.get(params, :after))
  """

  @type params :: map()

  @doc """
  Get a value from params with indifferent access.

  Checks for atom key first, then string key. Returns default if neither exists.

  ## Examples

      params = %{"limit" => 20, :status => "active"}
      Params.get(params, :limit)              #=> 20
      Params.get(params, :status)             #=> "active"
      Params.get(params, :missing)            #=> nil
      Params.get(params, :missing, "default") #=> "default"
  """
  @spec get(params(), atom() | String.t(), term()) :: term()
  def get(params, key, default \\ nil)

  def get(params, key, default) when is_atom(key) do
    case params do
      %{^key => value} -> value
      _ -> Map.get(params, to_string(key), default)
    end
  end

  def get(params, key, default) when is_binary(key) do
    case params do
      %{^key => value} -> value
      _ -> Map.get(params, String.to_existing_atom(key), default)
    end
  rescue
    ArgumentError -> default
  end

  @doc """
  Fetch a value from params with indifferent access.

  Returns `{:ok, value}` or `:error`.

  ## Examples

      params = %{"limit" => 20}
      Params.fetch(params, :limit)   #=> {:ok, 20}
      Params.fetch(params, :missing) #=> :error
  """
  @spec fetch(params(), atom() | String.t()) :: {:ok, term()} | :error
  def fetch(params, key) when is_atom(key) do
    case params do
      %{^key => value} ->
        {:ok, value}

      _ ->
        string_key = to_string(key)

        case params do
          %{^string_key => value} -> {:ok, value}
          _ -> :error
        end
    end
  end

  def fetch(params, key) when is_binary(key) do
    case params do
      %{^key => value} ->
        {:ok, value}

      _ ->
        atom_key = String.to_existing_atom(key)

        case params do
          %{^atom_key => value} -> {:ok, value}
          _ -> :error
        end
    end
  rescue
    ArgumentError -> :error
  end

  @doc """
  Check if a key exists in params (indifferent access).

  ## Examples

      params = %{"limit" => 20}
      Params.has_key?(params, :limit)   #=> true
      Params.has_key?(params, "limit")  #=> true
      Params.has_key?(params, :missing) #=> false
  """
  @spec has_key?(params(), atom() | String.t()) :: boolean()
  def has_key?(params, key) do
    fetch(params, key) != :error
  end

  @doc """
  Normalize params map to use atom keys.

  Converts all string keys to atoms. Existing atom keys are preserved.

  ## Options

  - `:only` - List of allowed atom keys. String keys not in this list are dropped.
              This is recommended for security to prevent atom table exhaustion.
  - `:except` - List of atom keys to exclude from the result.

  ## Examples

      # Basic normalization (be careful with untrusted input!)
      Params.normalize(%{"limit" => 20, "status" => "active"})
      #=> %{limit: 20, status: "active"}

      # Safe normalization with allowed keys
      Params.normalize(%{"limit" => 20, "evil" => "x"}, only: [:limit, :status])
      #=> %{limit: 20}

      # Exclude certain keys
      Params.normalize(%{"limit" => 20, "internal" => "x"}, except: [:internal])
      #=> %{limit: 20}
  """
  @spec normalize(params(), keyword()) :: map()
  def normalize(params, opts \\ []) do
    only = opts[:only]
    except = opts[:except] || []

    params
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = to_atom_key(key, only)

      cond do
        is_nil(atom_key) -> acc
        atom_key in except -> acc
        true -> Map.put(acc, atom_key, value)
      end
    end)
  end

  defp to_atom_key(key, nil) when is_atom(key), do: key
  defp to_atom_key(key, nil) when is_binary(key), do: String.to_atom(key)

  defp to_atom_key(key, only) when is_atom(key) do
    if key in only, do: key, else: nil
  end

  defp to_atom_key(key, only) when is_binary(key) do
    atom_key = String.to_existing_atom(key)
    if atom_key in only, do: atom_key, else: nil
  rescue
    ArgumentError -> nil
  end

  @doc """
  Take only specified keys from params (with indifferent access).

  Returns a map with atom keys containing only the specified fields.

  ## Examples

      params = %{"limit" => 20, "status" => "active", "other" => "ignored"}
      Params.take(params, [:limit, :status])
      #=> %{limit: 20, status: "active"}
  """
  @spec take(params(), [atom()]) :: map()
  def take(params, keys) when is_list(keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case fetch(params, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @doc """
  Get multiple values from params as a keyword list.

  Useful for passing directly to query functions.

  ## Examples

      params = %{"limit" => 20, "after" => "cursor123"}
      Params.to_keyword(params, [:limit, :after])
      #=> [limit: 20, after: "cursor123"]

      # Missing keys are omitted
      params = %{"limit" => 20}
      Params.to_keyword(params, [:limit, :after])
      #=> [limit: 20]
  """
  @spec to_keyword(params(), [atom()]) :: keyword()
  def to_keyword(params, keys) when is_list(keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case fetch(params, key) do
        {:ok, value} -> [{key, value} | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Compact a keyword list or map by removing nil values.

  Useful for cleaning up params before passing to query functions.

  ## Examples

      Params.compact(limit: nil, after: "cursor", status: nil)
      #=> [after: "cursor"]

      Params.compact(%{limit: nil, after: "cursor"})
      #=> %{after: "cursor"}
  """
  @spec compact(keyword() | map()) :: keyword() | map()
  def compact(params) when is_list(params) do
    Enum.reject(params, fn {_k, v} -> is_nil(v) end)
  end

  def compact(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Build pagination options from params with indifferent access.

  Extracts `:limit`, `:offset`, `:after`, `:before`, and `:cursor_fields`
  from params and returns a clean keyword list with only present values.

  ## Examples

      params = %{"limit" => "20", "after" => "cursor123"}
      Params.pagination_opts(params)
      #=> [limit: 20, after: "cursor123"]

      # With custom key mapping
      params = %{"page_size" => "10", "cursor" => "abc"}
      Params.pagination_opts(params, limit: :page_size, after: :cursor)
      #=> [limit: 10, after: "abc"]
  """
  @spec pagination_opts(params(), keyword()) :: keyword()
  def pagination_opts(params, mapping \\ []) do
    limit_key = mapping[:limit] || :limit
    offset_key = mapping[:offset] || :offset
    after_key = mapping[:after] || :after
    before_key = mapping[:before] || :before

    []
    |> maybe_add_pagination_opt(:limit, get(params, limit_key))
    |> maybe_add_pagination_opt(:offset, get(params, offset_key))
    |> maybe_add_pagination_opt(:after, get(params, after_key))
    |> maybe_add_pagination_opt(:before, get(params, before_key))
    |> Enum.reverse()
  end

  defp maybe_add_pagination_opt(opts, _key, nil), do: opts
  defp maybe_add_pagination_opt(opts, _key, ""), do: opts

  defp maybe_add_pagination_opt(opts, :limit, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> [{:limit, int} | opts]
      _ -> opts
    end
  end

  defp maybe_add_pagination_opt(opts, :offset, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> [{:offset, int} | opts]
      _ -> opts
    end
  end

  defp maybe_add_pagination_opt(opts, key, value), do: [{key, value} | opts]
end
