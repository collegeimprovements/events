defmodule OmCache.ErrorTest do
  use ExUnit.Case, async: true

  alias OmCache.Error

  describe "smart constructors" do
    test "connection_failed/3 builds correct struct" do
      error = Error.connection_failed(MyCache, "Redis down", adapter: NebulexRedisAdapter)
      assert error.type == :connection_failed
      assert error.cache == MyCache
      assert error.message == "Redis down"
      assert error.adapter == NebulexRedisAdapter
    end

    test "timeout/4 builds correct struct" do
      error = Error.timeout({User, 1}, :get, "Timed out")
      assert error.type == :timeout
      assert error.key == {User, 1}
      assert error.operation == :get
      assert error.message == "Timed out"
    end

    test "not_found/3 builds correct struct" do
      error = Error.not_found({User, 999}, :get)
      assert error.type == :key_not_found
      assert error.key == {User, 999}
      assert error.operation == :get
      assert error.message =~ "not found"
    end

    test "serialization_error/4 builds correct struct" do
      error = Error.serialization_error({User, 1}, :put, "Cannot encode")
      assert error.type == :serialization_error
      assert error.key == {User, 1}
    end

    test "adapter_unavailable/3 builds correct struct" do
      error = Error.adapter_unavailable(MyCache, "Not started")
      assert error.type == :adapter_unavailable
      assert error.cache == MyCache
    end

    test "invalid_ttl/3 builds correct struct" do
      error = Error.invalid_ttl(-100, "Must be positive")
      assert error.type == :invalid_ttl
      assert error.metadata.ttl == -100
    end

    test "cache_full/3 builds correct struct" do
      error = Error.cache_full({User, 1}, "At capacity")
      assert error.type == :cache_full
      assert error.key == {User, 1}
    end

    test "invalid_key/3 builds correct struct" do
      error = Error.invalid_key(nil, "Cannot be nil")
      assert error.type == :invalid_key
      assert error.key == nil
    end

    test "operation_failed/3 builds correct struct" do
      error = Error.operation_failed(:delete, "Unknown error")
      assert error.type == :operation_failed
      assert error.operation == :delete
    end

    test "unknown/2 builds correct struct" do
      error = Error.unknown("Something broke")
      assert error.type == :unknown
      assert error.message == "Something broke"
    end
  end

  describe "from_exception/4" do
    test "classifies RuntimeError as unknown" do
      error = Error.from_exception(%RuntimeError{message: "boom"}, :get, {User, 1})
      assert error.type == :unknown
      assert error.operation == :get
      assert error.key == {User, 1}
      assert error.original == %RuntimeError{message: "boom"}
    end
  end

  describe "format_message/1" do
    test "formats basic error message" do
      error = Error.not_found({User, 123}, :get, cache: MyCache)
      msg = Error.format_message(error)
      assert msg =~ "not found"
      assert msg =~ "User, 123"
      assert msg =~ "get"
      assert msg =~ "MyCache"
    end

    test "formats message without optional fields" do
      error = Error.unknown("Something broke")
      msg = Error.format_message(error)
      assert msg == "Something broke"
    end
  end

  describe "Exception behaviour" do
    test "is raisable" do
      assert_raise OmCache.Error, fn ->
        raise Error.not_found({User, 1}, :get)
      end
    end

    test "message/1 returns formatted string" do
      error = Error.not_found({User, 1})
      assert is_binary(Exception.message(error))
    end
  end

  describe "String.Chars protocol" do
    test "to_string returns formatted message" do
      error = Error.not_found({User, 1}, :get)
      assert is_binary(to_string(error))
      assert to_string(error) =~ "not found"
    end
  end

  describe "Normalizable protocol" do
    test "normalizes to FnTypes.Error" do
      error = Error.connection_failed(MyCache, "Redis down")
      normalized = FnTypes.Protocols.Normalizable.normalize(error, [])
      assert normalized.__struct__ == FnTypes.Error
      assert normalized.type == :network_error
    end

    test "maps all error types correctly" do
      mappings = [
        {:connection_failed, :network_error},
        {:timeout, :timeout},
        {:key_not_found, :not_found},
        {:serialization_error, :invalid_data},
        {:adapter_unavailable, :service_unavailable},
        {:invalid_ttl, :invalid_argument},
        {:cache_full, :resource_exhausted},
        {:operation_failed, :operation_failed},
        {:invalid_key, :invalid_argument},
        {:unknown, :unknown}
      ]

      for {cache_type, fn_type} <- mappings do
        error = %Error{type: cache_type, message: "test"}
        normalized = FnTypes.Protocols.Normalizable.normalize(error, [])
        assert normalized.type == fn_type, "Expected #{cache_type} -> #{fn_type}"
      end
    end
  end

  describe "Recoverable protocol" do
    test "connection_failed is recoverable" do
      error = Error.connection_failed(MyCache, "down")
      assert FnTypes.Protocols.Recoverable.recoverable?(error) == true
      assert FnTypes.Protocols.Recoverable.strategy(error) == :retry_with_backoff
      assert FnTypes.Protocols.Recoverable.max_attempts(error) == 3
      assert FnTypes.Protocols.Recoverable.trips_circuit?(error) == true
      assert FnTypes.Protocols.Recoverable.severity(error) == :degraded
    end

    test "timeout is recoverable" do
      error = Error.timeout(nil, nil, "slow")
      assert FnTypes.Protocols.Recoverable.recoverable?(error) == true
      assert FnTypes.Protocols.Recoverable.strategy(error) == :retry
    end

    test "key_not_found is not recoverable" do
      error = Error.not_found({User, 1})
      assert FnTypes.Protocols.Recoverable.recoverable?(error) == false
      assert FnTypes.Protocols.Recoverable.strategy(error) == :fail_fast
      assert FnTypes.Protocols.Recoverable.max_attempts(error) == 1
    end

    test "retry_delay increases with attempt" do
      error = Error.connection_failed(nil, "down")
      delay_1 = FnTypes.Protocols.Recoverable.retry_delay(error, 1)
      delay_2 = FnTypes.Protocols.Recoverable.retry_delay(error, 2)
      assert delay_2 > delay_1
    end
  end
end
