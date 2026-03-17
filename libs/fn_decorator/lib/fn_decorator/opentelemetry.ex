defmodule FnDecorator.OpenTelemetry do
  @moduledoc """
  OpenTelemetry context propagation utilities and decorators.

  Provides utilities for propagating OpenTelemetry context across:
  - Async boundaries (Task, Task.async, Task.Supervisor)
  - GenServer calls
  - Message passing
  - External HTTP requests

  ## Context Propagation

  OpenTelemetry uses process dictionary for context storage. When spawning
  new processes (Task, GenServer, etc.), context must be explicitly propagated.

  ### Task Propagation

      # Manual propagation
      ctx = FnDecorator.OpenTelemetry.current_context()
      Task.async(fn ->
        FnDecorator.OpenTelemetry.attach_context(ctx)
        do_work()
      end)

      # Using helper
      FnDecorator.OpenTelemetry.async_with_context(fn -> do_work() end)

  ### Decorator-based Propagation

      defmodule MyApp.Worker do
        use FnDecorator

        @decorate propagate_context()
        def async_task(data) do
          Task.async(fn -> process(data) end)
        end
      end

  ## Baggage

  Baggage allows propagating key-value pairs across service boundaries:

      FnDecorator.OpenTelemetry.set_baggage(:user_id, user.id)
      FnDecorator.OpenTelemetry.set_baggage(:tenant, tenant.slug)

      # Later, in another service
      user_id = FnDecorator.OpenTelemetry.get_baggage(:user_id)

  ## Span Links

  Link related spans across async operations:

      parent_span = FnDecorator.OpenTelemetry.current_span()
      Task.async(fn ->
        FnDecorator.OpenTelemetry.with_linked_span("child_operation", parent_span, fn ->
          do_work()
        end)
      end)
  """

  # Type definitions for context
  @type otel_context :: term()
  @type span_ctx :: term()
  @type baggage :: %{String.t() => String.t()}

  @doc """
  Returns the current OpenTelemetry context.

  This captures the entire context including span context and baggage.

  ## Examples

      ctx = FnDecorator.OpenTelemetry.current_context()
      Task.async(fn ->
        FnDecorator.OpenTelemetry.attach_context(ctx)
        # Now traces will be linked
      end)
  """
  @spec current_context() :: otel_context()
  def current_context do
    if otel_available?() do
      apply(OpenTelemetry.Ctx, :get_current, [])
    else
      nil
    end
  end

  @doc """
  Attaches an OpenTelemetry context to the current process.

  Use this after spawning a new process to continue the trace.

  ## Examples

      ctx = FnDecorator.OpenTelemetry.current_context()
      spawn(fn ->
        FnDecorator.OpenTelemetry.attach_context(ctx)
        traced_work()
      end)
  """
  @spec attach_context(otel_context()) :: :ok
  def attach_context(nil), do: :ok

  def attach_context(ctx) do
    if otel_available?() do
      apply(OpenTelemetry.Ctx, :attach, [ctx])
    end

    :ok
  end

  @doc """
  Returns the current span context (trace_id, span_id, etc.).

  ## Examples

      span_ctx = FnDecorator.OpenTelemetry.current_span_context()
      %{trace_id: trace_id, span_id: span_id} = span_ctx
  """
  @spec current_span_context() :: span_ctx() | nil
  def current_span_context do
    if otel_available?() do
      apply(OpenTelemetry.Tracer, :current_span_ctx, [])
    else
      nil
    end
  end

  @doc """
  Executes a function within a new span, propagating the current context.

  ## Options

  - `:kind` - Span kind (`:internal`, `:server`, `:client`, `:producer`, `:consumer`)
  - `:attributes` - Map of span attributes
  - `:links` - List of span contexts to link

  ## Examples

      with_span("process_order", fn ->
        validate_order(order)
        charge_payment(order)
        fulfill_order(order)
      end)

      with_span("external_api_call", [kind: :client, attributes: %{service: "payments"}], fn ->
        PaymentService.charge(amount)
      end)
  """
  @spec with_span(String.t(), keyword(), (-> result)) :: result when result: term()
  def with_span(name, opts \\ [], fun) when is_binary(name) and is_function(fun, 0) do
    if otel_available?() do
      kind = Keyword.get(opts, :kind, :internal)
      attributes = Keyword.get(opts, :attributes, %{})
      links = Keyword.get(opts, :links, [])

      span_opts = build_span_opts(kind, attributes, links)

      apply(OpenTelemetry.Tracer, :with_span, [name, span_opts, fun])
    else
      fun.()
    end
  end

  @doc """
  Creates a new span linked to a parent span context.

  Useful for async operations where you want to show the relationship
  but not make it a strict parent-child relationship.

  ## Examples

      parent_ctx = FnDecorator.OpenTelemetry.current_span_context()

      Task.async(fn ->
        FnDecorator.OpenTelemetry.with_linked_span("async_work", parent_ctx, fn ->
          do_work()
        end)
      end)
  """
  @spec with_linked_span(String.t(), span_ctx(), (-> result)) :: result when result: term()
  def with_linked_span(name, parent_span_ctx, fun) when is_binary(name) and is_function(fun, 0) do
    with_span(name, [links: [parent_span_ctx]], fun)
  end

  @doc """
  Runs a Task.async with the current OpenTelemetry context propagated.

  ## Examples

      task = FnDecorator.OpenTelemetry.async_with_context(fn ->
        # This runs with the parent's trace context
        do_work()
      end)
      Task.await(task)
  """
  @spec async_with_context((-> result)) :: Task.t() when result: term()
  def async_with_context(fun) when is_function(fun, 0) do
    ctx = current_context()

    Task.async(fn ->
      attach_context(ctx)
      fun.()
    end)
  end

  @doc """
  Runs a Task.async_stream with context propagated to each task.

  ## Examples

      items
      |> FnDecorator.OpenTelemetry.async_stream_with_context(fn item ->
        process_item(item)
      end)
      |> Enum.to_list()
  """
  @spec async_stream_with_context(Enumerable.t(), (term() -> result), keyword()) ::
          Enumerable.t()
        when result: term()
  def async_stream_with_context(enumerable, fun, opts \\ []) when is_function(fun, 1) do
    ctx = current_context()

    Task.async_stream(
      enumerable,
      fn item ->
        attach_context(ctx)
        fun.(item)
      end,
      opts
    )
  end

  @doc """
  Runs multiple tasks in parallel with context propagation.

  Returns when all tasks complete.

  ## Examples

      results = FnDecorator.OpenTelemetry.parallel_with_context([
        fn -> fetch_user(id) end,
        fn -> fetch_orders(id) end,
        fn -> fetch_settings(id) end
      ])
  """
  @spec parallel_with_context([(-> term())], keyword()) :: [term()]
  def parallel_with_context(funs, opts \\ []) when is_list(funs) do
    timeout = Keyword.get(opts, :timeout, 5000)

    funs
    |> Enum.map(&async_with_context/1)
    |> Task.await_many(timeout)
  end

  @doc """
  Sets a baggage value in the current context.

  Baggage propagates across process and service boundaries.

  ## Examples

      FnDecorator.OpenTelemetry.set_baggage(:user_id, "123")
      FnDecorator.OpenTelemetry.set_baggage(:tenant, "acme")
  """
  @spec set_baggage(atom() | String.t(), String.t()) :: :ok
  def set_baggage(key, value) when is_binary(value) do
    if otel_baggage_available?() do
      string_key = to_string(key)
      apply(OpenTelemetry.Baggage, :set, [string_key, value])
    end

    :ok
  end

  @doc """
  Gets a baggage value from the current context.

  ## Examples

      user_id = FnDecorator.OpenTelemetry.get_baggage(:user_id)
  """
  @spec get_baggage(atom() | String.t()) :: String.t() | nil
  def get_baggage(key) do
    if otel_baggage_available?() do
      string_key = to_string(key)
      apply(OpenTelemetry.Baggage, :get_value, [string_key])
    else
      nil
    end
  end

  @doc """
  Gets all baggage from the current context.

  ## Examples

      baggage = FnDecorator.OpenTelemetry.get_all_baggage()
      #=> %{"user_id" => "123", "tenant" => "acme"}
  """
  @spec get_all_baggage() :: baggage()
  def get_all_baggage do
    if otel_baggage_available?() do
      apply(OpenTelemetry.Baggage, :get_all, [])
    else
      %{}
    end
  end

  @doc """
  Sets multiple baggage values at once.

  ## Examples

      FnDecorator.OpenTelemetry.set_baggage_from_map(%{
        user_id: "123",
        tenant: "acme",
        request_id: "abc-123"
      })
  """
  @spec set_baggage_from_map(map()) :: :ok
  def set_baggage_from_map(map) when is_map(map) do
    Enum.each(map, fn {key, value} ->
      set_baggage(key, to_string(value))
    end)

    :ok
  end

  @doc """
  Extracts trace context from HTTP headers for incoming requests.

  Supports W3C Trace Context format.

  ## Examples

      def call(conn, _opts) do
        FnDecorator.OpenTelemetry.extract_from_headers(conn.req_headers)
        # Now the trace context is attached
      end
  """
  @spec extract_from_headers([{String.t(), String.t()}]) :: :ok
  def extract_from_headers(headers) when is_list(headers) do
    if otel_available?() do
      # Convert to map format expected by OpenTelemetry
      header_map = Map.new(headers, fn {k, v} -> {String.downcase(k), v} end)
      ctx = apply(:otel_propagator_text_map, :extract, [header_map])
      attach_context(ctx)
    end

    :ok
  end

  @doc """
  Injects trace context into HTTP headers for outgoing requests.

  Returns headers with W3C Trace Context headers added.

  ## Examples

      headers = FnDecorator.OpenTelemetry.inject_into_headers([{"content-type", "application/json"}])
      HTTPClient.post(url, body, headers)
  """
  @spec inject_into_headers([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def inject_into_headers(headers) when is_list(headers) do
    if otel_available?() do
      # Get injected headers
      injected =
        apply(:otel_propagator_text_map, :inject, [%{}, fn map, key, value ->
          Map.put(map, key, value)
        end])

      # Merge with existing headers
      injected_list = Enum.map(injected, fn {k, v} -> {k, v} end)
      headers ++ injected_list
    else
      headers
    end
  end

  @doc """
  Sets an attribute on the current span.

  ## Examples

      FnDecorator.OpenTelemetry.set_attribute(:user_id, user.id)
      FnDecorator.OpenTelemetry.set_attribute("http.status_code", 200)
  """
  @spec set_attribute(atom() | String.t(), term()) :: :ok
  def set_attribute(key, value) do
    if otel_available?() do
      apply(OpenTelemetry.Tracer, :set_attribute, [key, value])
    end

    :ok
  end

  @doc """
  Sets multiple attributes on the current span.

  ## Examples

      FnDecorator.OpenTelemetry.set_attributes(%{
        user_id: user.id,
        operation: "create_order",
        order_total: order.total
      })
  """
  @spec set_attributes(map()) :: :ok
  def set_attributes(attributes) when is_map(attributes) do
    if otel_available?() do
      apply(OpenTelemetry.Tracer, :set_attributes, [attributes])
    end

    :ok
  end

  @doc """
  Records an exception on the current span.

  ## Examples

      try do
        risky_operation()
      rescue
        e ->
          FnDecorator.OpenTelemetry.record_exception(e)
          reraise e, __STACKTRACE__
      end
  """
  @spec record_exception(Exception.t(), keyword()) :: :ok
  def record_exception(exception, opts \\ []) do
    if otel_available?() do
      stacktrace = Keyword.get(opts, :stacktrace, [])
      attributes = Keyword.get(opts, :attributes, %{})

      apply(OpenTelemetry.Tracer, :record_exception, [exception, stacktrace, attributes])
    end

    :ok
  end

  @doc """
  Adds an event to the current span.

  ## Examples

      FnDecorator.OpenTelemetry.add_event("cache_miss", %{key: cache_key})
      FnDecorator.OpenTelemetry.add_event("retry_attempt", %{attempt: 3, delay_ms: 1000})
  """
  @spec add_event(String.t(), map()) :: :ok
  def add_event(name, attributes \\ %{}) when is_binary(name) do
    if otel_available?() do
      apply(OpenTelemetry.Tracer, :add_event, [name, attributes])
    end

    :ok
  end

  @doc """
  Sets the status of the current span.

  ## Examples

      FnDecorator.OpenTelemetry.set_status(:ok)
      FnDecorator.OpenTelemetry.set_status(:error, "Payment failed")
  """
  @spec set_status(:ok | :error, String.t() | nil) :: :ok
  def set_status(status, message \\ nil)

  def set_status(:ok, _message) do
    if otel_available?() do
      apply(OpenTelemetry.Tracer, :set_status, [:ok, ""])
    end

    :ok
  end

  def set_status(:error, message) do
    if otel_available?() do
      apply(OpenTelemetry.Tracer, :set_status, [:error, message || ""])
    end

    :ok
  end

  @doc """
  Wraps a GenServer call with context propagation.

  The context is passed in the call message and must be extracted
  by the GenServer.

  ## Examples

      # Client side
      FnDecorator.OpenTelemetry.call_with_context(MyServer, {:process, data})

      # Server side (in handle_call)
      def handle_call({:otel_ctx, ctx, {:process, data}}, from, state) do
        FnDecorator.OpenTelemetry.attach_context(ctx)
        # Process with context attached
      end
  """
  @spec call_with_context(GenServer.server(), term(), timeout()) :: term()
  def call_with_context(server, request, timeout \\ 5000) do
    ctx = current_context()
    GenServer.call(server, {:otel_ctx, ctx, request}, timeout)
  end

  @doc """
  Wraps a GenServer cast with context propagation.

  ## Examples

      FnDecorator.OpenTelemetry.cast_with_context(MyServer, {:process, data})
  """
  @spec cast_with_context(GenServer.server(), term()) :: :ok
  def cast_with_context(server, request) do
    ctx = current_context()
    GenServer.cast(server, {:otel_ctx, ctx, request})
  end

  @doc """
  Extracts context from a GenServer message wrapped with `call_with_context/3`.

  Returns `{context, original_request}` or `{nil, request}` if not wrapped.

  ## Examples

      def handle_call(msg, from, state) do
        {ctx, request} = FnDecorator.OpenTelemetry.unwrap_context(msg)
        FnDecorator.OpenTelemetry.attach_context(ctx)
        # Handle request...
      end
  """
  @spec unwrap_context(term()) :: {otel_context() | nil, term()}
  def unwrap_context({:otel_ctx, ctx, request}), do: {ctx, request}
  def unwrap_context(request), do: {nil, request}

  @doc """
  Creates a context carrier map for manual propagation.

  Useful when you need to serialize context for message queues, databases, etc.

  ## Examples

      carrier = FnDecorator.OpenTelemetry.to_carrier()
      # Store in message, database, etc.
      Jason.encode!(%{trace_context: carrier, data: data})

      # Later, restore
      FnDecorator.OpenTelemetry.from_carrier(carrier)
  """
  @spec to_carrier() :: map()
  def to_carrier do
    if otel_available?() do
      apply(:otel_propagator_text_map, :inject, [%{}, fn map, key, value ->
        Map.put(map, key, value)
      end])
    else
      %{}
    end
  end

  @doc """
  Restores context from a carrier map.

  ## Examples

      carrier = Jason.decode!(message)["trace_context"]
      FnDecorator.OpenTelemetry.from_carrier(carrier)
  """
  @spec from_carrier(map()) :: :ok
  def from_carrier(carrier) when is_map(carrier) do
    if otel_available?() do
      ctx = apply(:otel_propagator_text_map, :extract, [carrier])
      attach_context(ctx)
    end

    :ok
  end

  @doc """
  Checks if OpenTelemetry is available and configured.

  ## Examples

      if FnDecorator.OpenTelemetry.available?() do
        # Use OpenTelemetry features
      end
  """
  @spec available?() :: boolean()
  def available?, do: otel_available?()

  # Private helpers

  defp otel_available? do
    Code.ensure_loaded?(OpenTelemetry.Tracer) and
      Code.ensure_loaded?(OpenTelemetry.Ctx)
  end

  defp otel_baggage_available? do
    Code.ensure_loaded?(OpenTelemetry.Baggage)
  end

  defp build_span_opts(kind, attributes, links) do
    opts = %{kind: kind}

    opts =
      if map_size(attributes) > 0 do
        Map.put(opts, :attributes, attributes)
      else
        opts
      end

    if links != [] do
      Map.put(opts, :links, links)
    else
      opts
    end
  end
end
