defmodule FnDecorator.OpenTelemetry.Decorators do
  @moduledoc """
  OpenTelemetry-specific decorators for context propagation.

  These decorators provide automatic context propagation for common patterns.

  ## Usage

      defmodule MyApp.Worker do
        use FnDecorator

        # Propagate context to spawned tasks
        @decorate propagate_context()
        def async_work(data) do
          Task.async(fn -> process(data) end)
        end

        # Create a span with automatic attribute extraction
        @decorate otel_span("process_order", extract: [:order_id, :user_id])
        def process_order(order_id, user_id, data) do
          # Attributes order_id and user_id automatically set
          do_work(data)
        end

        # Propagate baggage from function arguments
        @decorate with_baggage(user_id: :user_id, tenant: :tenant_id)
        def tenant_operation(user_id, tenant_id, data) do
          # Baggage propagated to downstream services
          call_external_service(data)
        end
      end
  """

  @propagate_context_schema NimbleOptions.new!(
                              include_baggage: [
                                type: :boolean,
                                default: true,
                                doc: "Include baggage in propagated context"
                              ]
                            )

  @with_baggage_schema NimbleOptions.new!(
                         fields: [
                           type: {:map, :atom, :atom},
                           default: %{},
                           doc: "Map of baggage keys to argument names"
                         ]
                       )

  @otel_span_advanced_schema NimbleOptions.new!(
                               name: [
                                 type: :string,
                                 required: false,
                                 doc: "Span name"
                               ],
                               kind: [
                                 type: {:in, [:internal, :server, :client, :producer, :consumer]},
                                 default: :internal,
                                 doc: "Span kind"
                               ],
                               extract: [
                                 type: {:list, :atom},
                                 default: [],
                                 doc: "Argument names to extract as span attributes"
                               ],
                               attributes: [
                                 type: :map,
                                 default: %{},
                                 doc: "Static attributes to add to span"
                               ],
                               on_error: [
                                 type: {:in, [:record, :ignore, :raise]},
                                 default: :record,
                                 doc: "How to handle errors"
                               ],
                               propagate_result: [
                                 type: :boolean,
                                 default: false,
                                 doc: "Add result status to span"
                               ]
                             )

  @doc """
  Captures the current OpenTelemetry context before function execution.

  The context is stored in a variable that can be used when spawning tasks.

  ## Options

  #{NimbleOptions.docs(@propagate_context_schema)}

  ## Examples

      @decorate propagate_context()
      def spawn_workers(data) do
        # __otel_ctx__ is available for propagation
        Task.async(fn ->
          FnDecorator.OpenTelemetry.attach_context(__otel_ctx__)
          process(data)
        end)
      end
  """
  def propagate_context(opts, body, _context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @propagate_context_schema)
    _include_baggage = validated_opts[:include_baggage]

    quote do
      # Capture context before executing body
      var!(otel_ctx, __MODULE__) = FnDecorator.OpenTelemetry.current_context()

      # Make it available as __otel_ctx__ for convenience
      _ = var!(otel_ctx, __MODULE__)

      unquote(body)
    end
  end

  @doc """
  Sets baggage values from function arguments.

  Baggage is propagated across service boundaries automatically.

  ## Options

  #{NimbleOptions.docs(@with_baggage_schema)}

  ## Examples

      @decorate with_baggage(%{user_id: :user_id, tenant: :tenant_slug})
      def process_for_tenant(user_id, tenant_slug, data) do
        # Baggage "user_id" and "tenant" are set
        call_downstream_service(data)
      end
  """
  # Handle AST representation of map (at compile time)
  def with_baggage({:%{}, _meta, kvs}, body, context) when is_list(kvs) do
    # Convert AST key-value list to a map
    field_mapping = Map.new(kvs)
    with_baggage_impl(field_mapping, body, context)
  end

  # Handle actual map (runtime)
  def with_baggage(field_mapping, body, context) when is_map(field_mapping) do
    with_baggage_impl(field_mapping, body, context)
  end

  defp with_baggage_impl(field_mapping, body, context) do
    validated_opts = NimbleOptions.validate!([fields: field_mapping], @with_baggage_schema)
    fields = validated_opts[:fields]

    baggage_setters = build_baggage_setters(fields, context)

    quote do
      unquote(baggage_setters)
      unquote(body)
    end
  end

  @doc """
  Advanced OpenTelemetry span decorator with automatic attribute extraction.

  ## Options

  #{NimbleOptions.docs(@otel_span_advanced_schema)}

  ## Examples

      @decorate otel_span_advanced("order.process",
        kind: :internal,
        extract: [:order_id, :customer_id],
        attributes: %{service: "order-processor"},
        on_error: :record,
        propagate_result: true
      )
      def process_order(order_id, customer_id, data) do
        # Span created with extracted attributes
        do_work(data)
      end
  """
  def otel_span_advanced(opts, body, context) when is_list(opts) do
    # Normalize AST representations in options
    normalized_opts = normalize_opts(opts)
    validated_opts = NimbleOptions.validate!(normalized_opts, @otel_span_advanced_schema)

    span_name = validated_opts[:name] || default_span_name(context)
    kind = validated_opts[:kind]
    extract = validated_opts[:extract]
    static_attrs = validated_opts[:attributes]
    on_error = validated_opts[:on_error]
    propagate_result = validated_opts[:propagate_result]

    extracted_attrs = build_attribute_extraction(extract, context)

    # Check if OpenTelemetry is available at compile time
    if Code.ensure_loaded?(OpenTelemetry.Tracer) do
      quote do
        require OpenTelemetry.Tracer

        span_opts = %{kind: unquote(kind)}

        # Build attributes from extracted args and static attrs
        attributes =
          Map.merge(
            unquote(Macro.escape(static_attrs)),
            unquote(extracted_attrs)
          )

        span_opts =
          if map_size(attributes) > 0 do
            Map.put(span_opts, :attributes, attributes)
          else
            span_opts
          end

        OpenTelemetry.Tracer.with_span unquote(span_name), span_opts do
          try do
            result = unquote(body)

            if unquote(propagate_result) do
              case result do
                {:ok, _} ->
                  FnDecorator.OpenTelemetry.set_status(:ok)
                  FnDecorator.OpenTelemetry.set_attribute("result.status", "ok")

                {:error, reason} ->
                  FnDecorator.OpenTelemetry.set_status(:error, inspect(reason))
                  FnDecorator.OpenTelemetry.set_attribute("result.status", "error")

                _ ->
                  :ok
              end
            end

            result
          rescue
            e ->
              case unquote(on_error) do
                :record ->
                  FnDecorator.OpenTelemetry.record_exception(e, stacktrace: __STACKTRACE__)
                  FnDecorator.OpenTelemetry.set_status(:error, Exception.message(e))
                  reraise e, __STACKTRACE__

                :ignore ->
                  reraise e, __STACKTRACE__

                :raise ->
                  FnDecorator.OpenTelemetry.record_exception(e, stacktrace: __STACKTRACE__)
                  FnDecorator.OpenTelemetry.set_status(:error, Exception.message(e))
                  reraise e, __STACKTRACE__
              end
          end
        end
      end
    else
      # OpenTelemetry not available, just execute the body
      body
    end
  end

  # Helper to build baggage setters from field mapping
  defp build_baggage_setters(fields, context) do
    arg_names = Enum.map(context.args, &elem(&1, 0))

    setters =
      Enum.map(fields, fn {baggage_key, arg_name} ->
        if arg_name in arg_names do
          var = Macro.var(arg_name, nil)

          quote do
            FnDecorator.OpenTelemetry.set_baggage(
              unquote(to_string(baggage_key)),
              to_string(unquote(var))
            )
          end
        else
          quote do: :ok
        end
      end)

    quote do
      (unquote_splicing(setters))
    end
  end

  # Helper to build attribute extraction from args
  defp build_attribute_extraction(extract_args, context) do
    arg_names = Enum.map(context.args, &elem(&1, 0))

    extractions =
      Enum.filter(extract_args, &(&1 in arg_names))
      |> Enum.map(fn arg_name ->
        var = Macro.var(arg_name, nil)

        quote do
          {unquote(to_string(arg_name)), unquote(var)}
        end
      end)

    quote do
      Map.new([unquote_splicing(extractions)])
    end
  end

  defp default_span_name(context) do
    module_name = context.module |> Module.split() |> List.last() |> Macro.underscore()
    "#{module_name}.#{context.name}"
  end

  # Normalize AST representations in options to actual values
  defp normalize_opts(opts) do
    Enum.map(opts, fn {key, value} ->
      {key, normalize_value(value)}
    end)
  end

  defp normalize_value({:%{}, _meta, kvs}) when is_list(kvs) do
    # Convert AST map to actual map
    Map.new(kvs, fn {k, v} -> {k, normalize_value(v)} end)
  end

  defp normalize_value({:{}, _meta, elements}) when is_list(elements) do
    # Convert AST tuple to actual tuple
    List.to_tuple(Enum.map(elements, &normalize_value/1))
  end

  defp normalize_value(list) when is_list(list) do
    Enum.map(list, &normalize_value/1)
  end

  defp normalize_value(value), do: value
end
