defmodule Events.Extensions.Decorator.Telemetry do
  @moduledoc """
  Events-specific telemetry decorators.

  Only contains decorators that require Events-specific dependencies:
  - `log_query` - Uses Events.Data.Repo
  - `log_remote` - Uses Events.TaskSupervisor

  For other telemetry decorators, use FnDecorator.Telemetry directly.
  """

  import FnDecorator.Shared

  @default_repo Application.compile_env(:events, [__MODULE__, :repo], Events.Data.Repo)

  # Shared log level specification
  @log_levels [:emergency, :alert, :critical, :error, :warning, :warn, :notice, :info, :debug]

  @log_query_schema NimbleOptions.new!(
                      slow_threshold: [
                        type: :pos_integer,
                        default: 1000,
                        doc: "Threshold in ms to log as slow query"
                      ],
                      level: [
                        type: {:in, @log_levels},
                        default: :debug,
                        doc: "Log level"
                      ],
                      slow_level: [
                        type: {:in, @log_levels},
                        default: :warn,
                        doc: "Log level for slow queries"
                      ],
                      include_query: [
                        type: :boolean,
                        default: true,
                        doc: "Include query in log output"
                      ]
                    )

  @log_remote_schema NimbleOptions.new!(
                       service: [
                         type: :atom,
                         required: true,
                         doc: "Remote logging service module"
                       ],
                       async: [
                         type: :boolean,
                         default: true,
                         doc: "Send logs asynchronously"
                       ],
                       metadata: [
                         type: :map,
                         default: %{},
                         doc: "Additional metadata to include"
                       ]
                     )

  @doc """
  Database query logging decorator.

  Events-specific implementation that uses Events.Data.Repo.

  ## Options

  #{NimbleOptions.docs(@log_query_schema)}
  """
  def log_query(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @log_query_schema)

    slow_threshold = validated_opts[:slow_threshold]
    level = validate_log_level!(validated_opts[:level])
    slow_level = validate_log_level!(validated_opts[:slow_level])
    include_query? = validated_opts[:include_query]

    quote do
      require Logger

      start_time = System.monotonic_time()

      result = unquote(body)

      duration = System.monotonic_time() - start_time
      duration_ms = System.convert_time_unit(duration, :native, :millisecond)

      # Extract query string if result is an Ecto query or has a query
      query_info =
        if unquote(include_query?) do
          case result do
            %Ecto.Query{} = q ->
              try do
                repo = unquote(@default_repo)
                {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, repo, q)
                sql
              rescue
                _ -> inspect(q, limit: 200)
              end

            {:ok, %{__struct__: _} = struct} ->
              struct.__struct__ |> to_string() |> String.split(".") |> List.last()

            {:ok, list} when is_list(list) ->
              "#{length(list)} records"

            _ ->
              nil
          end
        end

      cond do
        duration_ms > unquote(slow_threshold) ->
          message =
            if query_info,
              do: "SLOW QUERY (#{duration_ms}ms): #{query_info}",
              else: "SLOW QUERY (#{duration_ms}ms)"

          Logger.unquote(slow_level)(
            message,
            module: unquote(context.module),
            function: unquote(context.name),
            duration_ms: duration_ms
          )

        true ->
          message =
            if query_info && unquote(include_query?),
              do: "Query executed in #{duration_ms}ms: #{query_info}",
              else: "Query executed in #{duration_ms}ms"

          Logger.unquote(level)(
            message,
            module: unquote(context.module),
            function: unquote(context.name),
            duration_ms: duration_ms
          )
      end

      result
    end
  end

  @doc """
  Remote logging decorator.

  Events-specific implementation that uses Events.TaskSupervisor.

  ## Options

  #{NimbleOptions.docs(@log_remote_schema)}
  """
  def log_remote(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @log_remote_schema)

    service = validated_opts[:service]
    async? = validated_opts[:async]
    metadata = validated_opts[:metadata]

    base_metadata =
      quote do
        Map.merge(unquote(Macro.escape(metadata)), %{
          module: unquote(context.module),
          function: unquote(context.name),
          arity: unquote(context.arity),
          timestamp: DateTime.utc_now()
        })
      end

    quote do
      start_time = System.monotonic_time()

      try do
        result = unquote(body)

        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        metadata = Map.put(unquote(base_metadata), :duration_ms, duration_ms)

        if unquote(async?) do
          Task.Supervisor.start_child(Events.TaskSupervisor, fn ->
            unquote(service).log_async(:info, "Function completed", metadata)
          end)
        else
          unquote(service).log(:info, "Function completed", metadata)
        end

        result
      rescue
        error ->
          metadata =
            Map.merge(unquote(base_metadata), %{
              error: Exception.format(:error, error, __STACKTRACE__)
            })

          if unquote(async?) do
            Task.Supervisor.start_child(Events.TaskSupervisor, fn ->
              unquote(service).log_async(:error, "Function failed", metadata)
            end)
          else
            unquote(service).log(:error, "Function failed", metadata)
          end

          reraise error, __STACKTRACE__
      end
    end
  end
end
