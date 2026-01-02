defmodule OmGoogle.FCM do
  @moduledoc """
  Firebase Cloud Messaging (FCM) HTTP v1 API client.

  Sends push notifications to Android, iOS, and web applications using
  Google's FCM HTTP v1 API with service account authentication.

  ## Setup

  1. Create a Firebase project and download the service account JSON
  2. Set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable or load credentials directly

  ## Quick Start

      # Load credentials
      {:ok, creds} = OmGoogle.FCM.credentials_from_env()

      # Send a simple notification
      {:ok, response} = OmGoogle.FCM.push(creds,
        token: "device_fcm_token",
        title: "Hello",
        body: "World"
      )

  ## Configuration

      # From environment variable
      {:ok, config} = OmGoogle.FCM.config_from_env()

      # Manual configuration
      config = OmGoogle.FCM.config(
        credentials: creds,
        project_id: "my-firebase-project"
      )

  ## Sending Messages

      # To a single device
      OmGoogle.FCM.push(config,
        token: "device_token",
        title: "New Message",
        body: "You have a new message",
        data: %{message_id: "123"}
      )

      # To a topic
      OmGoogle.FCM.push_to_topic(config, "news",
        title: "Breaking News",
        body: "Something happened!"
      )

      # To a condition (topic expression)
      OmGoogle.FCM.push_to_condition(config, "'news' in topics && 'local' in topics",
        title: "Local News",
        body: "News in your area"
      )

      # With platform-specific options
      OmGoogle.FCM.push(config,
        token: "device_token",
        title: "Alert",
        body: "Important alert",
        android: %{priority: :high, ttl: "86400s"},
        apns: %{headers: %{"apns-priority" => "10"}}
      )

  ## Using with TokenServer (Recommended for Production)

      # In your application.ex
      children = [
        {OmGoogle.ServiceAccount.TokenServer,
          credentials: creds,
          scopes: OmGoogle.FCM.scopes(),
          name: :fcm_token_server}
      ]

      # Then send messages using the token server
      OmGoogle.FCM.push_with_server(:fcm_token_server, config,
        token: "device_token",
        title: "Hello",
        body: "World"
      )
  """

  use OmApiClient,
    base_url: "https://fcm.googleapis.com",
    auth: :custom,
    content_type: :json

  alias OmGoogle.ServiceAccount
  alias OmApiClient.{Request, Response}

  @fcm_scope "https://www.googleapis.com/auth/firebase.messaging"

  # ============================================
  # Types
  # ============================================

  @type config :: %{
          credentials: ServiceAccount.credentials(),
          project_id: String.t(),
          token: ServiceAccount.token() | nil
        }

  @type notification :: %{
          optional(:title) => String.t(),
          optional(:body) => String.t(),
          optional(:image) => String.t()
        }

  @type android_config :: %{
          optional(:collapse_key) => String.t(),
          optional(:priority) => :normal | :high,
          optional(:ttl) => String.t(),
          optional(:restricted_package_name) => String.t(),
          optional(:data) => map(),
          optional(:notification) => map(),
          optional(:fcm_options) => map()
        }

  @type apns_config :: %{
          optional(:headers) => map(),
          optional(:payload) => map(),
          optional(:fcm_options) => map()
        }

  @type webpush_config :: %{
          optional(:headers) => map(),
          optional(:data) => map(),
          optional(:notification) => map(),
          optional(:fcm_options) => map()
        }

  @type message_opts :: [
          token: String.t(),
          topic: String.t(),
          condition: String.t(),
          title: String.t(),
          body: String.t(),
          image: String.t(),
          data: map(),
          android: android_config(),
          apns: apns_config(),
          webpush: webpush_config(),
          fcm_options: map()
        ]

  # ============================================
  # Configuration
  # ============================================

  @doc """
  Returns the OAuth2 scope required for FCM.

  ## Examples

      OmGoogle.FCM.scopes()
      #=> ["https://www.googleapis.com/auth/firebase.messaging"]
  """
  @spec scopes() :: [String.t()]
  def scopes, do: [@fcm_scope]

  @doc """
  Creates FCM configuration from options.

  ## Options

  - `:credentials` - Service account credentials (required)
  - `:project_id` - Firebase project ID (optional, defaults to credentials project_id)

  ## Examples

      config = OmGoogle.FCM.config(credentials: creds)
      config = OmGoogle.FCM.config(credentials: creds, project_id: "my-project")
  """
  @spec config(keyword()) :: config()
  def config(opts) do
    credentials = Keyword.fetch!(opts, :credentials)

    %{
      credentials: credentials,
      project_id: Keyword.get(opts, :project_id, credentials.project_id),
      token: nil
    }
  end

  @doc """
  Creates FCM configuration from environment variables.

  Reads credentials from `GOOGLE_APPLICATION_CREDENTIALS` or `FIREBASE_CREDENTIALS`.

  ## Examples

      {:ok, config} = OmGoogle.FCM.config_from_env()
      {:ok, config} = OmGoogle.FCM.config_from_env("CUSTOM_FIREBASE_CREDENTIALS")
  """
  @spec config_from_env(String.t()) :: {:ok, config()} | {:error, term()}
  def config_from_env(env_var \\ "GOOGLE_APPLICATION_CREDENTIALS") do
    with {:ok, creds} <- ServiceAccount.from_env(env_var) do
      {:ok, config(credentials: creds)}
    end
  end

  @doc """
  Loads service account credentials from environment.

  ## Examples

      {:ok, creds} = OmGoogle.FCM.credentials_from_env()
  """
  @spec credentials_from_env(String.t()) :: {:ok, ServiceAccount.credentials()} | {:error, term()}
  def credentials_from_env(env_var \\ "GOOGLE_APPLICATION_CREDENTIALS") do
    ServiceAccount.from_env(env_var)
  end

  # ============================================
  # Sending Messages
  # ============================================

  @doc """
  Sends a push notification message.

  Automatically handles token refresh if needed.

  ## Options

  Target (one required):
  - `:token` - FCM device registration token
  - `:topic` - Topic name (without /topics/ prefix)
  - `:condition` - Topic condition expression

  Notification:
  - `:title` - Notification title
  - `:body` - Notification body
  - `:image` - Image URL

  Data:
  - `:data` - Custom data payload (map of string keys and values)

  Platform-specific:
  - `:android` - Android-specific configuration
  - `:apns` - iOS/APNs-specific configuration
  - `:webpush` - Web push-specific configuration
  - `:fcm_options` - FCM options (analytics_label)

  ## Examples

      # Simple notification
      OmGoogle.FCM.push(config,
        token: "device_token",
        title: "Hello",
        body: "World"
      )

      # Data-only message (silent push)
      OmGoogle.FCM.push(config,
        token: "device_token",
        data: %{"action" => "sync", "id" => "123"}
      )

      # With platform-specific options
      OmGoogle.FCM.push(config,
        token: "device_token",
        title: "Alert",
        body: "Important!",
        android: %{priority: :high},
        apns: %{headers: %{"apns-priority" => "10"}}
      )
  """
  @spec push(config(), message_opts()) :: {:ok, map()} | {:error, term()}
  def push(config, opts) do
    with {:ok, config} <- ensure_valid_token(config),
         message <- build_message(opts),
         {:ok, response} <- do_send(config, message) do
      handle_response(response)
    end
  end

  @doc """
  Sends a message to a topic.

  ## Examples

      OmGoogle.FCM.push_to_topic(config, "news",
        title: "Breaking News",
        body: "Something happened!"
      )
  """
  @spec push_to_topic(config(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def push_to_topic(config, topic, opts) do
    opts = Keyword.put(opts, :topic, topic)
    push(config, opts)
  end

  @doc """
  Sends a message to devices matching a topic condition.

  ## Examples

      # Send to devices subscribed to both 'news' AND 'local'
      OmGoogle.FCM.push_to_condition(config, "'news' in topics && 'local' in topics",
        title: "Local News",
        body: "News in your area"
      )

      # Send to devices subscribed to 'news' OR 'weather'
      OmGoogle.FCM.push_to_condition(config, "'news' in topics || 'weather' in topics",
        title: "Update",
        body: "New content available"
      )
  """
  @spec push_to_condition(config(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def push_to_condition(config, condition, opts) do
    opts = Keyword.put(opts, :condition, condition)
    push(config, opts)
  end

  @doc """
  Sends a message using a TokenServer for credential management.

  Recommended for production use as it handles token caching and refresh.

  ## Examples

      # Start token server in your supervision tree
      {ServiceAccount.TokenServer,
        credentials: creds,
        scopes: OmGoogle.FCM.scopes(),
        name: :fcm_token_server}

      # Send messages
      OmGoogle.FCM.push_with_server(:fcm_token_server, project_id,
        token: "device_token",
        title: "Hello",
        body: "World"
      )
  """
  @spec push_with_server(GenServer.server(), String.t(), message_opts()) ::
          {:ok, map()} | {:error, term()}
  def push_with_server(token_server, project_id, opts) do
    with {:ok, token} <- ServiceAccount.TokenServer.get_token(token_server) do
      config = %{
        credentials: nil,
        project_id: project_id,
        token: token
      }

      message = build_message(opts)
      do_send_with_token(config, message, token)
    end
  end

  @doc """
  Sends multiple messages in a batch (up to 500 messages).

  Note: FCM HTTP v1 API doesn't have a native batch endpoint.
  This sends messages concurrently for efficiency.

  ## Options

  - `:concurrency` - Number of concurrent requests (default: 10)

  ## Examples

      messages = [
        [token: "token1", title: "Hello", body: "User 1"],
        [token: "token2", title: "Hello", body: "User 2"],
        [token: "token3", title: "Hello", body: "User 3"]
      ]

      results = OmGoogle.FCM.push_batch(config, messages)
      #=> [ok: %{name: "..."}, ok: %{name: "..."}, error: %{...}]
  """
  @spec push_batch(config(), [message_opts()], keyword()) :: [{:ok, map()} | {:error, term()}]
  def push_batch(config, messages, opts \\ []) when is_list(messages) do
    concurrency = Keyword.get(opts, :concurrency, 10)

    # Ensure we have a valid token before starting batch
    case ensure_valid_token(config) do
      {:ok, config} ->
        messages
        |> Task.async_stream(
          fn msg_opts -> push(config, msg_opts) end,
          max_concurrency: concurrency,
          timeout: 30_000
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, {:task_exit, reason}}
        end)

      {:error, _} = error ->
        Enum.map(messages, fn _ -> error end)
    end
  end

  # ============================================
  # Message Building
  # ============================================

  defp build_message(opts) do
    message = %{}

    # Add target
    message =
      cond do
        opts[:token] -> Map.put(message, "token", opts[:token])
        opts[:topic] -> Map.put(message, "topic", opts[:topic])
        opts[:condition] -> Map.put(message, "condition", opts[:condition])
        true -> message
      end

    # Add notification
    notification = build_notification(opts)

    message =
      if map_size(notification) > 0,
        do: Map.put(message, "notification", notification),
        else: message

    # Add data
    message =
      case opts[:data] do
        nil -> message
        data when is_map(data) -> Map.put(message, "data", stringify_data(data))
      end

    # Add platform-specific configs
    message = maybe_add_android(message, opts[:android])
    message = maybe_add_apns(message, opts[:apns])
    message = maybe_add_webpush(message, opts[:webpush])

    # Add FCM options
    message =
      case opts[:fcm_options] do
        nil -> message
        fcm_opts -> Map.put(message, "fcm_options", fcm_opts)
      end

    message
  end

  defp build_notification(opts) do
    %{}
    |> maybe_put("title", opts[:title])
    |> maybe_put("body", opts[:body])
    |> maybe_put("image", opts[:image])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_data(data) do
    Map.new(data, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp maybe_add_android(message, nil), do: message

  defp maybe_add_android(message, android) do
    android_config = %{}

    android_config = maybe_put(android_config, "collapse_key", android[:collapse_key])

    android_config =
      maybe_put(android_config, "restricted_package_name", android[:restricted_package_name])

    android_config =
      case android[:priority] do
        nil -> android_config
        :normal -> Map.put(android_config, "priority", "NORMAL")
        :high -> Map.put(android_config, "priority", "HIGH")
      end

    android_config = maybe_put(android_config, "ttl", android[:ttl])
    android_config = maybe_put(android_config, "data", android[:data])
    android_config = maybe_put(android_config, "notification", android[:notification])
    android_config = maybe_put(android_config, "fcm_options", android[:fcm_options])

    if map_size(android_config) > 0 do
      Map.put(message, "android", android_config)
    else
      message
    end
  end

  defp maybe_add_apns(message, nil), do: message

  defp maybe_add_apns(message, apns) do
    apns_config = %{}
    apns_config = maybe_put(apns_config, "headers", apns[:headers])
    apns_config = maybe_put(apns_config, "payload", apns[:payload])
    apns_config = maybe_put(apns_config, "fcm_options", apns[:fcm_options])

    if map_size(apns_config) > 0 do
      Map.put(message, "apns", apns_config)
    else
      message
    end
  end

  defp maybe_add_webpush(message, nil), do: message

  defp maybe_add_webpush(message, webpush) do
    webpush_config = %{}
    webpush_config = maybe_put(webpush_config, "headers", webpush[:headers])
    webpush_config = maybe_put(webpush_config, "data", webpush[:data])
    webpush_config = maybe_put(webpush_config, "notification", webpush[:notification])
    webpush_config = maybe_put(webpush_config, "fcm_options", webpush[:fcm_options])

    if map_size(webpush_config) > 0 do
      Map.put(message, "webpush", webpush_config)
    else
      message
    end
  end

  # ============================================
  # Token Management
  # ============================================

  defp ensure_valid_token(%{token: token} = config) when not is_nil(token) do
    if ServiceAccount.token_valid?(token) do
      {:ok, config}
    else
      refresh_token(config)
    end
  end

  defp ensure_valid_token(config) do
    refresh_token(config)
  end

  defp refresh_token(%{credentials: creds} = config) do
    case ServiceAccount.get_access_token(creds, [@fcm_scope]) do
      {:ok, token} -> {:ok, %{config | token: token}}
      {:error, _} = error -> error
    end
  end

  # ============================================
  # HTTP Requests
  # ============================================

  defp do_send(config, message) do
    do_send_with_token(config, message, config.token)
  end

  defp do_send_with_token(config, message, token) do
    path = "/v1/projects/#{config.project_id}/messages:send"
    body = %{"message" => message}

    new(%{access_token: token.access_token})
    |> Request.header("authorization", "#{token.token_type} #{token.access_token}")
    |> post(path, body)
  end

  defp handle_response({:ok, %Response{} = resp}) do
    case Response.categorize(resp) do
      {:ok, body} -> {:ok, body}
      {:created, body} -> {:ok, body}
      {:unauthorized, resp} -> {:error, {:unauthorized, resp.body}}
      {:forbidden, resp} -> {:error, {:forbidden, resp.body}}
      {:not_found, resp} -> {:error, {:invalid_token, resp.body}}
      {:client_error, resp} -> {:error, normalize_fcm_error(resp)}
      {:server_error, resp} -> {:error, {:server_error, resp.status, resp.body}}
      _ -> {:error, {:unexpected_status, resp.status, resp.body}}
    end
  end

  defp handle_response({:error, _} = error), do: error

  defp normalize_fcm_error(%Response{body: body}) when is_map(body) do
    case body do
      %{"error" => %{"details" => details, "message" => message, "status" => status}} ->
        error_code = extract_fcm_error_code(details)

        %{
          status: status,
          code: error_code,
          message: message,
          details: details
        }

      %{"error" => error} ->
        %{
          status: error["status"],
          code: error["code"],
          message: error["message"]
        }

      _ ->
        %{body: body}
    end
  end

  defp normalize_fcm_error(%Response{body: body}), do: %{body: body}

  defp extract_fcm_error_code(details) when is_list(details) do
    Enum.find_value(details, fn
      %{"@type" => "type.googleapis.com/google.firebase.fcm.v1.FcmError", "errorCode" => code} ->
        code

      _ ->
        nil
    end)
  end

  defp extract_fcm_error_code(_), do: nil
end
