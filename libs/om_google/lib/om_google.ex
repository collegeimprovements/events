defmodule OmGoogle do
  @moduledoc """
  Google API clients with service account authentication.

  This library provides clients for various Google APIs:

  - `OmGoogle.ServiceAccount` - Google Service Account authentication
  - `OmGoogle.FCM` - Firebase Cloud Messaging

  ## Quick Start

      # Load service account credentials
      {:ok, creds} = OmGoogle.ServiceAccount.from_env()

      # Send a push notification
      config = OmGoogle.FCM.config(credentials: creds)
      {:ok, _} = OmGoogle.FCM.push(config,
        token: "device_token",
        title: "Hello",
        body: "World"
      )

  ## Service Account Authentication

  All Google API clients use service account authentication:

      # From environment variable (path or JSON content)
      {:ok, creds} = OmGoogle.ServiceAccount.from_env("GOOGLE_APPLICATION_CREDENTIALS")

      # From JSON file
      {:ok, creds} = OmGoogle.ServiceAccount.from_json_file("/path/to/creds.json")

      # From JSON string
      {:ok, creds} = OmGoogle.ServiceAccount.from_json(json_string)

  ## Token Management

  For production use, use the TokenServer for automatic token refresh:

      # Add to your supervision tree
      children = [
        {OmGoogle.ServiceAccount.TokenServer,
          credentials: creds,
          scopes: OmGoogle.FCM.scopes(),
          name: :google_token_server}
      ]

      # Use with FCM
      OmGoogle.FCM.push_with_server(:google_token_server, project_id, opts)

  See individual module documentation for more details.
  """

  # Re-export common modules for convenience
  defdelegate credentials_from_env(env_var \\ "GOOGLE_APPLICATION_CREDENTIALS"),
    to: OmGoogle.ServiceAccount,
    as: :from_env

  defdelegate credentials_from_json(json), to: OmGoogle.ServiceAccount, as: :from_json

  defdelegate credentials_from_file(path), to: OmGoogle.ServiceAccount, as: :from_json_file
end
