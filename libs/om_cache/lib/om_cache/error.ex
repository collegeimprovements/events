defmodule OmCache.Error do
  @moduledoc """
  Structured error type for cache operations.

  Provides rich error information with protocol implementations for:
  - Error normalization (`FnTypes.Protocols.Normalizable`)
  - Recovery detection (`FnTypes.Protocols.Recoverable`)

  ## Error Types

  - `:connection_failed` - Cache backend unreachable
  - `:timeout` - Operation exceeded timeout
  - `:key_not_found` - Key does not exist (cache miss)
  - `:serialization_error` - Failed to serialize/deserialize value
  - `:adapter_unavailable` - Cache adapter not initialized
  - `:invalid_ttl` - TTL value invalid or out of range
  - `:cache_full` - Cache at capacity, cannot store
  - `:operation_failed` - Generic operation failure
  - `:invalid_key` - Key format invalid
  - `:unknown` - Unclassified error

  ## Examples

      # Connection failure (recoverable with retry)
      error = OmCache.Error.connection_failed(MyApp.Cache, "Connection refused")
      FnTypes.Protocols.Recoverable.recoverable?(error)
      #=> true

      # Key not found (not recoverable)
      error = OmCache.Error.not_found({User, 123}, :get)
      FnTypes.Protocols.Recoverable.recoverable?(error)
      #=> false

      # Normalize to FnTypes.Error
      FnTypes.Error.normalize(error)
      #=> %FnTypes.Error{type: :not_found, ...}
  """

  @type error_type ::
          :connection_failed
          | :timeout
          | :key_not_found
          | :serialization_error
          | :adapter_unavailable
          | :invalid_ttl
          | :cache_full
          | :operation_failed
          | :invalid_key
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          key: term() | nil,
          operation: atom() | nil,
          adapter: module() | nil,
          cache: module() | nil,
          message: String.t(),
          original: term() | nil,
          metadata: map()
        }

  defstruct [
    :type,
    :key,
    :operation,
    :adapter,
    :cache,
    :message,
    :original,
    metadata: %{}
  ]

  # Protocol Implementations

  defimpl FnTypes.Protocols.Normalizable do
    alias FnTypes.Error, as: FnError

    def normalize(%OmCache.Error{} = error, opts \\ []) do
      context = Keyword.get(opts, :context, %{})

      %FnError{
        type: map_error_type(error.type),
        message: error.message,
        details: %{
          cache_error_type: error.type,
          key: error.key,
          operation: error.operation,
          adapter: error.adapter,
          cache: error.cache,
          metadata: error.metadata
        },
        source: error.original,
        context: context
      }
    end

    defp map_error_type(:connection_failed), do: :network_error
    defp map_error_type(:timeout), do: :timeout
    defp map_error_type(:key_not_found), do: :not_found
    defp map_error_type(:serialization_error), do: :invalid_data
    defp map_error_type(:adapter_unavailable), do: :service_unavailable
    defp map_error_type(:invalid_ttl), do: :invalid_argument
    defp map_error_type(:cache_full), do: :resource_exhausted
    defp map_error_type(:operation_failed), do: :operation_failed
    defp map_error_type(:invalid_key), do: :invalid_argument
    defp map_error_type(:unknown), do: :unknown
  end

  defimpl FnTypes.Protocols.Recoverable do
    @recoverable_types [:connection_failed, :timeout, :adapter_unavailable, :cache_full]

    def recoverable?(%OmCache.Error{type: type}), do: type in @recoverable_types

    def strategy(%OmCache.Error{type: :connection_failed}), do: :retry_with_backoff
    def strategy(%OmCache.Error{type: :timeout}), do: :retry
    def strategy(%OmCache.Error{type: :adapter_unavailable}), do: :wait_until
    def strategy(%OmCache.Error{type: :cache_full}), do: :retry_with_backoff
    def strategy(%OmCache.Error{}), do: :fail_fast

    def retry_delay(%OmCache.Error{type: :connection_failed}, attempt), do: min(100 * attempt * attempt, 5_000)
    def retry_delay(%OmCache.Error{type: :timeout}, _attempt), do: 100
    def retry_delay(%OmCache.Error{type: :adapter_unavailable}, attempt), do: min(500 * attempt, 10_000)
    def retry_delay(%OmCache.Error{type: :cache_full}, attempt), do: min(200 * attempt, 3_000)
    def retry_delay(%OmCache.Error{}, _attempt), do: 0

    def max_attempts(%OmCache.Error{type: type}) when type in @recoverable_types, do: 3
    def max_attempts(%OmCache.Error{}), do: 1

    def trips_circuit?(%OmCache.Error{type: :connection_failed}), do: true
    def trips_circuit?(%OmCache.Error{type: :adapter_unavailable}), do: true
    def trips_circuit?(%OmCache.Error{}), do: false

    def severity(%OmCache.Error{type: :connection_failed}), do: :degraded
    def severity(%OmCache.Error{type: :timeout}), do: :transient
    def severity(%OmCache.Error{type: :adapter_unavailable}), do: :critical
    def severity(%OmCache.Error{type: :cache_full}), do: :degraded
    def severity(%OmCache.Error{type: type}) when type in [:key_not_found, :invalid_key, :invalid_ttl], do: :permanent
    def severity(%OmCache.Error{}), do: :transient

    def fallback(%OmCache.Error{}), do: nil
  end

  defimpl String.Chars do
    def to_string(error) do
      OmCache.Error.message(error)
    end
  end

  # Smart Constructors

  @doc """
  Creates a connection_failed error.

  ## Examples

      OmCache.Error.connection_failed(MyApp.Cache, "Redis connection refused")
      #=> %OmCache.Error{type: :connection_failed, ...}
  """
  @spec connection_failed(module() | nil, String.t(), keyword()) :: t()
  def connection_failed(cache \\ nil, message, opts \\ []) do
    %__MODULE__{
      type: :connection_failed,
      cache: cache,
      message: message,
      adapter: Keyword.get(opts, :adapter),
      original: Keyword.get(opts, :original),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a timeout error.

  ## Examples

      OmCache.Error.timeout({User, 123}, :get, "Operation took 5000ms")
  """
  @spec timeout(term() | nil, atom() | nil, String.t(), keyword()) :: t()
  def timeout(key \\ nil, operation \\ nil, message, opts \\ []) do
    %__MODULE__{
      type: :timeout,
      key: key,
      operation: operation,
      message: message,
      cache: Keyword.get(opts, :cache),
      adapter: Keyword.get(opts, :adapter),
      original: Keyword.get(opts, :original),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a key_not_found error.

  ## Examples

      OmCache.Error.not_found({User, 123}, :get)
      #=> %OmCache.Error{type: :key_not_found, key: {User, 123}, operation: :get}
  """
  @spec not_found(term(), atom() | nil, keyword()) :: t()
  def not_found(key, operation \\ nil, opts \\ []) do
    %__MODULE__{
      type: :key_not_found,
      key: key,
      operation: operation,
      message: Keyword.get(opts, :message, "Key not found: #{inspect(key)}"),
      cache: Keyword.get(opts, :cache),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a serialization_error.

  ## Examples

      OmCache.Error.serialization_error({User, 123}, :put, "Cannot encode struct")
  """
  @spec serialization_error(term() | nil, atom() | nil, String.t(), keyword()) :: t()
  def serialization_error(key \\ nil, operation \\ nil, message, opts \\ []) do
    %__MODULE__{
      type: :serialization_error,
      key: key,
      operation: operation,
      message: message,
      original: Keyword.get(opts, :original),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates an adapter_unavailable error.

  ## Examples

      OmCache.Error.adapter_unavailable(MyApp.Cache, "Cache not started")
  """
  @spec adapter_unavailable(module() | nil, String.t(), keyword()) :: t()
  def adapter_unavailable(cache \\ nil, message, opts \\ []) do
    %__MODULE__{
      type: :adapter_unavailable,
      cache: cache,
      message: message,
      adapter: Keyword.get(opts, :adapter),
      original: Keyword.get(opts, :original),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates an invalid_ttl error.

  ## Examples

      OmCache.Error.invalid_ttl(-100, "TTL must be positive")
  """
  @spec invalid_ttl(term(), String.t(), keyword()) :: t()
  def invalid_ttl(ttl_value, message, opts \\ []) do
    %__MODULE__{
      type: :invalid_ttl,
      message: message,
      metadata: Map.merge(Keyword.get(opts, :metadata, %{}), %{ttl: ttl_value})
    }
  end

  @doc """
  Creates a cache_full error.

  ## Examples

      OmCache.Error.cache_full({Product, 456}, "Cache at max capacity")
  """
  @spec cache_full(term() | nil, String.t(), keyword()) :: t()
  def cache_full(key \\ nil, message, opts \\ []) do
    %__MODULE__{
      type: :cache_full,
      key: key,
      message: message,
      cache: Keyword.get(opts, :cache),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates an invalid_key error.

  ## Examples

      OmCache.Error.invalid_key(nil, "Key cannot be nil")
  """
  @spec invalid_key(term(), String.t(), keyword()) :: t()
  def invalid_key(key, message, opts \\ []) do
    %__MODULE__{
      type: :invalid_key,
      key: key,
      message: message,
      operation: Keyword.get(opts, :operation),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a generic operation_failed error.

  ## Examples

      OmCache.Error.operation_failed(:delete, "Unknown error occurred")
  """
  @spec operation_failed(atom() | nil, String.t(), keyword()) :: t()
  def operation_failed(operation \\ nil, message, opts \\ []) do
    %__MODULE__{
      type: :operation_failed,
      operation: operation,
      message: message,
      key: Keyword.get(opts, :key),
      cache: Keyword.get(opts, :cache),
      original: Keyword.get(opts, :original),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates an unknown error.

  ## Examples

      OmCache.Error.unknown("Unexpected exception")
  """
  @spec unknown(String.t(), keyword()) :: t()
  def unknown(message, opts \\ []) do
    %__MODULE__{
      type: :unknown,
      message: message,
      operation: Keyword.get(opts, :operation),
      key: Keyword.get(opts, :key),
      cache: Keyword.get(opts, :cache),
      original: Keyword.get(opts, :original),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Wraps an arbitrary error into OmCache.Error.

  ## Examples

      OmCache.Error.from_exception(%RuntimeError{message: "boom"}, :get, {User, 1})
      #=> %OmCache.Error{type: :unknown, operation: :get, ...}
  """
  @spec from_exception(Exception.t(), atom() | nil, term() | nil, keyword()) :: t()
  def from_exception(exception, operation \\ nil, key \\ nil, opts \\ []) do
    %__MODULE__{
      type: classify_exception(exception),
      operation: operation,
      key: key,
      message: Exception.message(exception),
      original: exception,
      cache: Keyword.get(opts, :cache),
      adapter: Keyword.get(opts, :adapter),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Generates a human-readable error message.

  ## Examples

      error = OmCache.Error.not_found({User, 123}, :get)
      OmCache.Error.message(error)
      #=> "Cache key not found: {User, 123} (operation: get)"
  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{} = error) do
    base = error.message || default_message(error.type)

    parts = [
      base,
      format_key(error.key),
      format_operation(error.operation),
      format_cache(error.cache)
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # ============================================
  # Private
  # ============================================

  defp classify_exception(%Redix.ConnectionError{}), do: :connection_failed
  defp classify_exception(%Redix.Error{message: msg}) when is_binary(msg) do
    cond do
      String.contains?(msg, "timeout") -> :timeout
      String.contains?(msg, "connection") -> :connection_failed
      true -> :operation_failed
    end
  end
  defp classify_exception(%DBConnection.ConnectionError{}), do: :connection_failed
  defp classify_exception(_), do: :unknown

  defp default_message(:connection_failed), do: "Cache connection failed"
  defp default_message(:timeout), do: "Cache operation timed out"
  defp default_message(:key_not_found), do: "Cache key not found"
  defp default_message(:serialization_error), do: "Cache serialization error"
  defp default_message(:adapter_unavailable), do: "Cache adapter unavailable"
  defp default_message(:invalid_ttl), do: "Invalid TTL value"
  defp default_message(:cache_full), do: "Cache is full"
  defp default_message(:operation_failed), do: "Cache operation failed"
  defp default_message(:invalid_key), do: "Invalid cache key"
  defp default_message(:unknown), do: "Unknown cache error"

  defp format_key(nil), do: nil
  defp format_key(key), do: "(key: #{inspect(key)})"

  defp format_operation(nil), do: nil
  defp format_operation(op), do: "(operation: #{op})"

  defp format_cache(nil), do: nil
  defp format_cache(cache), do: "(cache: #{inspect(cache)})"
end
