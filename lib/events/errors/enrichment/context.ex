defmodule Events.Errors.Enrichment.Context do
  @moduledoc """
  Error context enrichment for debugging and analytics.

  This module enriches errors with contextual information:
  - User context (user_id, role, tenant)
  - Request context (request_id, IP, user_agent, operation)
  - Application context (module, function, line, environment, version)
  - Temporal context (timestamp, processing_time, retry_attempts)

  ## Usage

      # Enrich error with context
      error
      |> Context.enrich_user(user_id: user.id, role: user.role)
      |> Context.enrich_request(request_id: request_id, ip: conn.remote_ip)
      |> Context.enrich_application(module: __MODULE__, function: __ENV__.function)

      # Or use the all-in-one function
      Context.enrich(error,
        user: [user_id: user.id],
        request: [request_id: request_id],
        application: [module: __MODULE__]
      )
  """

  alias Events.Errors.Error

  @type user_context :: [
          user_id: String.t() | integer(),
          urm_id: String.t(),
          role: atom() | String.t(),
          tenant_id: String.t() | integer(),
          organization_id: String.t() | integer()
        ]

  @type request_context :: [
          request_id: String.t(),
          ip_address: String.t(),
          user_agent: String.t(),
          operation: String.t(),
          query: String.t(),
          variables: map(),
          referer: String.t(),
          origin: String.t()
        ]

  @type application_context :: [
          module: module(),
          function: {atom(), arity()},
          line: integer(),
          file: String.t(),
          environment: atom(),
          release: String.t(),
          node: atom(),
          hostname: String.t()
        ]

  @type temporal_context :: [
          timestamp: DateTime.t(),
          occurred_at: DateTime.t(),
          processing_time_ms: integer(),
          retry_attempt: integer(),
          total_retries: integer()
        ]

  @doc """
  Enriches an error with all context types at once.

  ## Examples

      iex> Context.enrich(error,
      ...>   user: [user_id: 123, role: :admin],
      ...>   request: [request_id: "req_123"],
      ...>   application: [module: MyModule],
      ...>   temporal: [retry_attempt: 2]
      ...> )
  """
  @spec enrich(Error.t(), keyword()) :: Error.t()
  def enrich(%Error{} = error, contexts) do
    error
    |> maybe_enrich_user(Keyword.get(contexts, :user))
    |> maybe_enrich_request(Keyword.get(contexts, :request))
    |> maybe_enrich_application(Keyword.get(contexts, :application))
    |> maybe_enrich_temporal(Keyword.get(contexts, :temporal))
  end

  @doc """
  Enriches error with user context.

  ## Examples

      iex> Context.enrich_user(error, user_id: 123, role: :admin)
      %Error{metadata: %{user: %{user_id: 123, role: :admin}}}
  """
  @spec enrich_user(Error.t(), user_context()) :: Error.t()
  def enrich_user(%Error{} = error, user_context) do
    user_data =
      user_context
      |> Enum.into(%{})
      |> Map.take([
        :user_id,
        :urm_id,
        :role,
        :tenant_id,
        :organization_id,
        :email,
        :username
      ])

    add_metadata(error, :user, user_data)
  end

  @doc """
  Enriches error with request context.

  ## Examples

      iex> Context.enrich_request(error,
      ...>   request_id: "req_123",
      ...>   ip_address: "192.168.1.1",
      ...>   operation: "createUser"
      ...> )
  """
  @spec enrich_request(Error.t(), request_context()) :: Error.t()
  def enrich_request(%Error{} = error, request_context) do
    request_data =
      request_context
      |> Enum.into(%{})
      |> Map.take([
        :request_id,
        :ip_address,
        :user_agent,
        :operation,
        :query,
        :variables,
        :referer,
        :origin,
        :path,
        :method
      ])

    add_metadata(error, :request, request_data)
  end

  @doc """
  Enriches error with application context.

  ## Examples

      iex> Context.enrich_application(error,
      ...>   module: MyApp.Users,
      ...>   function: {:create_user, 1},
      ...>   environment: :production
      ...> )
  """
  @spec enrich_application(Error.t(), application_context()) :: Error.t()
  def enrich_application(%Error{} = error, app_context) do
    app_data =
      app_context
      |> Enum.into(%{})
      |> Map.take([
        :module,
        :function,
        :line,
        :file,
        :environment,
        :release,
        :node,
        :hostname
      ])
      |> format_application_context()

    add_metadata(error, :application, app_data)
  end

  @doc """
  Enriches error with temporal context.

  ## Examples

      iex> Context.enrich_temporal(error,
      ...>   processing_time_ms: 1500,
      ...>   retry_attempt: 2
      ...> )
  """
  @spec enrich_temporal(Error.t(), temporal_context()) :: Error.t()
  def enrich_temporal(%Error{} = error, temporal_context) do
    temporal_data =
      temporal_context
      |> Enum.into(%{})
      |> Map.take([
        :timestamp,
        :occurred_at,
        :processing_time_ms,
        :retry_attempt,
        :total_retries
      ])
      |> format_temporal_context()

    add_metadata(error, :temporal, temporal_data)
  end

  @doc """
  Automatically captures application context from caller.

  ## Examples

      iex> Context.capture_caller(error)
      %Error{metadata: %{application: %{module: ..., function: ...}}}
  """
  @spec capture_caller(Error.t()) :: Error.t()
  def capture_caller(%Error{} = error) do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, [_ | [{module, function, arity, info} | _]]} ->
        enrich_application(error,
          module: module,
          function: {function, arity},
          file: Keyword.get(info, :file),
          line: Keyword.get(info, :line)
        )

      _ ->
        error
    end
  end

  @doc """
  Adds environment information automatically.

  ## Examples

      iex> Context.with_environment(error)
      %Error{metadata: %{application: %{environment: :production, ...}}}
  """
  @spec with_environment(Error.t()) :: Error.t()
  def with_environment(%Error{} = error) do
    enrich_application(error,
      environment: Mix.env(),
      node: node(),
      hostname: to_string(:inet.gethostname() |> elem(1))
    )
  end

  @doc """
  Adds timestamp to error.

  ## Examples

      iex> Context.with_timestamp(error)
      %Error{metadata: %{temporal: %{timestamp: ~U[...]}}}
  """
  @spec with_timestamp(Error.t()) :: Error.t()
  def with_timestamp(%Error{} = error) do
    enrich_temporal(error, timestamp: DateTime.utc_now())
  end

  @doc """
  Tracks retry attempts.

  ## Examples

      iex> Context.with_retry(error, 2, 3)
      %Error{metadata: %{temporal: %{retry_attempt: 2, total_retries: 3}}}
  """
  @spec with_retry(Error.t(), integer(), integer()) :: Error.t()
  def with_retry(%Error{} = error, retry_attempt, total_retries) do
    enrich_temporal(error,
      retry_attempt: retry_attempt,
      total_retries: total_retries
    )
  end

  ## Helpers

  defp maybe_enrich_user(error, nil), do: error
  defp maybe_enrich_user(error, context), do: enrich_user(error, context)

  defp maybe_enrich_request(error, nil), do: error
  defp maybe_enrich_request(error, context), do: enrich_request(error, context)

  defp maybe_enrich_application(error, nil), do: error
  defp maybe_enrich_application(error, context), do: enrich_application(error, context)

  defp maybe_enrich_temporal(error, nil), do: error
  defp maybe_enrich_temporal(error, context), do: enrich_temporal(error, context)

  defp add_metadata(%Error{metadata: metadata} = error, key, value) do
    %{error | metadata: Map.put(metadata, key, value)}
  end

  defp format_application_context(context) do
    context
    |> Map.update(:module, nil, &format_module/1)
    |> Map.update(:function, nil, &format_function/1)
  end

  defp format_module(nil), do: nil
  defp format_module(module) when is_atom(module), do: inspect(module)
  defp format_module(module), do: to_string(module)

  defp format_function(nil), do: nil
  defp format_function({name, arity}), do: "#{name}/#{arity}"
  defp format_function(function), do: to_string(function)

  defp format_temporal_context(context) do
    context
    |> Map.update(:timestamp, nil, &format_datetime/1)
    |> Map.update(:occurred_at, nil, &format_datetime/1)
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(dt), do: dt
end
