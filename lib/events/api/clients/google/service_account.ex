defmodule Events.Api.Clients.Google.ServiceAccount do
  @moduledoc """
  Google Service Account authentication using JWT.

  Thin wrapper around `OmGoogle.ServiceAccount` with Events-specific defaults.

  See `OmGoogle.ServiceAccount` for full documentation.
  """

  # Re-export types
  @type credentials :: OmGoogle.ServiceAccount.credentials()
  @type token :: OmGoogle.ServiceAccount.token()

  # Credential loading
  defdelegate from_json_file(path), to: OmGoogle.ServiceAccount
  defdelegate from_env(env_var), to: OmGoogle.ServiceAccount
  defdelegate from_json(json), to: OmGoogle.ServiceAccount
  defdelegate from_map(data), to: OmGoogle.ServiceAccount

  # Token generation
  defdelegate get_access_token(credentials, scopes), to: OmGoogle.ServiceAccount
  defdelegate token_valid?(token), to: OmGoogle.ServiceAccount
  defdelegate project_id(credentials), to: OmGoogle.ServiceAccount
  defdelegate build_jwt(credentials, scopes), to: OmGoogle.ServiceAccount

  # Re-export TokenServer module
  defmodule TokenServer do
    @moduledoc """
    GenServer for caching Google service account tokens.

    See `OmGoogle.ServiceAccount.TokenServer` for full documentation.
    """

    defdelegate start_link(opts), to: OmGoogle.ServiceAccount.TokenServer
    defdelegate get_token(server), to: OmGoogle.ServiceAccount.TokenServer
    defdelegate refresh_token(server), to: OmGoogle.ServiceAccount.TokenServer
    defdelegate child_spec(opts), to: OmGoogle.ServiceAccount.TokenServer
  end
end
