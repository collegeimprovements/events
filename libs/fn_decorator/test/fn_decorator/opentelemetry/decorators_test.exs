defmodule FnDecorator.OpenTelemetry.DecoratorsTest do
  use ExUnit.Case, async: true

  # Test module that uses the OpenTelemetry decorators
  defmodule TestModule do
    use FnDecorator

    @decorate propagate_context([])
    def with_context(data) do
      {:ok, data}
    end

    @decorate with_baggage(%{user_id: :user_id})
    def with_baggage_decorator(user_id, data) do
      {:ok, user_id, data}
    end

    @decorate otel_span_advanced(
                name: "test.operation",
                kind: :internal,
                extract: [:id],
                attributes: %{service: "test"}
              )
    def advanced_span(id, data) do
      {:ok, id, data}
    end
  end

  describe "propagate_context decorator" do
    test "function executes normally" do
      result = TestModule.with_context(:test_data)

      assert result == {:ok, :test_data}
    end
  end

  describe "with_baggage decorator" do
    test "function executes normally" do
      result = TestModule.with_baggage_decorator("user_123", %{key: "value"})

      assert result == {:ok, "user_123", %{key: "value"}}
    end
  end

  describe "otel_span_advanced decorator" do
    test "function executes normally" do
      result = TestModule.advanced_span(123, %{data: "test"})

      assert result == {:ok, 123, %{data: "test"}}
    end

    test "handles errors gracefully" do
      # Define a module with a function that raises
      defmodule RaisingModule do
        use FnDecorator

        @decorate otel_span_advanced(name: "test.raising", on_error: :record)
        def raising_function do
          raise "test error"
        end
      end

      assert_raise RuntimeError, "test error", fn ->
        RaisingModule.raising_function()
      end
    end

    test "propagates result status when enabled" do
      defmodule ResultModule do
        use FnDecorator

        @decorate otel_span_advanced(name: "test.result", propagate_result: true)
        def ok_function do
          {:ok, "success"}
        end

        @decorate otel_span_advanced(name: "test.error", propagate_result: true)
        def error_function do
          {:error, :failed}
        end
      end

      assert {:ok, "success"} = ResultModule.ok_function()
      assert {:error, :failed} = ResultModule.error_function()
    end
  end

  describe "decorator options validation" do
    test "otel_span_advanced accepts valid kind values" do
      defmodule KindModule do
        use FnDecorator

        @decorate otel_span_advanced(name: "test.server", kind: :server)
        def server_fn, do: :ok

        @decorate otel_span_advanced(name: "test.client", kind: :client)
        def client_fn, do: :ok

        @decorate otel_span_advanced(name: "test.producer", kind: :producer)
        def producer_fn, do: :ok

        @decorate otel_span_advanced(name: "test.consumer", kind: :consumer)
        def consumer_fn, do: :ok
      end

      assert :ok = KindModule.server_fn()
      assert :ok = KindModule.client_fn()
      assert :ok = KindModule.producer_fn()
      assert :ok = KindModule.consumer_fn()
    end
  end

  describe "attribute extraction" do
    test "extracts specified arguments as attributes" do
      defmodule ExtractModule do
        use FnDecorator

        @decorate otel_span_advanced(
                    name: "test.extract",
                    extract: [:user_id, :order_id]
                  )
        def process(user_id, order_id, _data) do
          {user_id, order_id}
        end
      end

      assert {123, 456} = ExtractModule.process(123, 456, %{})
    end

    test "ignores non-existent argument names" do
      defmodule IgnoreModule do
        use FnDecorator

        @decorate otel_span_advanced(
                    name: "test.ignore",
                    extract: [:user_id, :nonexistent]
                  )
        def process(user_id) do
          user_id
        end
      end

      assert 123 = IgnoreModule.process(123)
    end
  end
end
