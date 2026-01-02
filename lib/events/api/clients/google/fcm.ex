defmodule Events.Api.Clients.Google.FCM do
  @moduledoc """
  Firebase Cloud Messaging (FCM) HTTP v1 API client.

  Thin wrapper around `OmGoogle.FCM` with Events-specific defaults.

  See `OmGoogle.FCM` for full documentation.
  """

  # Configuration
  defdelegate scopes(), to: OmGoogle.FCM
  defdelegate config(opts), to: OmGoogle.FCM
  defdelegate config_from_env(env_var \\ "GOOGLE_APPLICATION_CREDENTIALS"), to: OmGoogle.FCM
  defdelegate credentials_from_env(env_var \\ "GOOGLE_APPLICATION_CREDENTIALS"), to: OmGoogle.FCM

  # Sending messages
  defdelegate push(config, opts), to: OmGoogle.FCM
  defdelegate push_to_topic(config, topic, opts), to: OmGoogle.FCM
  defdelegate push_to_condition(config, condition, opts), to: OmGoogle.FCM
  defdelegate push_with_server(token_server, project_id, opts), to: OmGoogle.FCM
  defdelegate push_batch(config, messages, opts \\ []), to: OmGoogle.FCM
end
