defmodule OmMigration.FieldBuilders.Authentication do
  @moduledoc """
  Builds authentication fields for migrations.

  Supports multiple authentication strategies:
  - Password-based authentication
  - OAuth providers
  - Magic link (passwordless)

  ## Options

  - `:type` - Authentication type (`:password`, `:oauth`, `:magic_link`)
  - `:with_lockout` - Include account lockout fields (default: true for password)
  - `:with_confirmation` - Include email confirmation fields (default: true for password)

  ## Password Fields

  - `:password_hash` - Hashed password
  - `:confirmed_at` - Email confirmation timestamp
  - `:confirmation_token` - Email confirmation token
  - `:reset_password_token` - Password reset token
  - `:failed_attempts` - Failed login attempt counter
  - `:locked_at` - Account lockout timestamp

  ## OAuth Fields

  - `:provider` - OAuth provider name
  - `:provider_id` - Provider-specific user ID
  - `:provider_token` - Access token
  - `:provider_refresh_token` - Refresh token
  - `:provider_token_expires_at` - Token expiration

  ## Magic Link Fields

  - `:magic_token` - One-time login token
  - `:magic_token_sent_at` - When token was sent
  - `:magic_token_expires_at` - Token expiration

  ## Examples

      create_table(:users)
      |> Authentication.add()                      # Password auth
      |> Authentication.add(type: :oauth)          # OAuth
      |> Authentication.add(type: :magic_link)     # Magic link
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @impl true
  def default_config do
    %{
      type: :password,
      with_lockout: true,
      with_confirmation: true
    }
  end

  @impl true
  def build(token, config) do
    case config.type do
      :password -> build_password_auth(token, config)
      :oauth -> build_oauth_auth(token, config)
      :magic_link -> build_magic_link_auth(token, config)
      _ -> token
    end
  end

  @impl true
  def indexes(config) do
    case config.type do
      :password -> password_indexes(config)
      :oauth -> oauth_indexes()
      :magic_link -> magic_link_indexes()
      _ -> []
    end
  end

  # ============================================
  # Password Authentication
  # ============================================

  defp build_password_auth(token, config) do
    token
    |> Token.add_field(:password_hash, :string, null: false, comment: "Hashed password")
    |> maybe_add_confirmation_fields(config.with_confirmation)
    |> maybe_add_lockout_fields(config.with_lockout)
  end

  defp maybe_add_confirmation_fields(token, false), do: token

  defp maybe_add_confirmation_fields(token, true) do
    token
    |> Token.add_field(:confirmed_at, :utc_datetime_usec, null: true, comment: "Email confirmed at")
    |> Token.add_field(:confirmation_token, :string, null: true, comment: "Email confirmation token")
    |> Token.add_field(:confirmation_sent_at, :utc_datetime_usec,
      null: true,
      comment: "Confirmation email sent at"
    )
    |> Token.add_field(:reset_password_token, :string,
      null: true,
      comment: "Password reset token"
    )
    |> Token.add_field(:reset_password_sent_at, :utc_datetime_usec,
      null: true,
      comment: "Password reset email sent at"
    )
  end

  defp maybe_add_lockout_fields(token, false), do: token

  defp maybe_add_lockout_fields(token, true) do
    token
    |> Token.add_field(:failed_attempts, :integer, default: 0, comment: "Failed login attempts")
    |> Token.add_field(:locked_at, :utc_datetime_usec, null: true, comment: "Account locked at")
  end

  defp password_indexes(config) do
    base = []

    confirmation =
      if config.with_confirmation do
        [
          {:confirmation_token_unique_index, [:confirmation_token], [unique: true]},
          {:reset_password_token_unique_index, [:reset_password_token], [unique: true]}
        ]
      else
        []
      end

    base ++ confirmation
  end

  # ============================================
  # OAuth Authentication
  # ============================================

  defp build_oauth_auth(token, _config) do
    token
    |> Token.add_field(:provider, :string, null: true, comment: "OAuth provider name")
    |> Token.add_field(:provider_id, :string, null: true, comment: "Provider user ID")
    |> Token.add_field(:provider_token, :text, null: true, comment: "OAuth access token")
    |> Token.add_field(:provider_refresh_token, :text, null: true, comment: "OAuth refresh token")
    |> Token.add_field(:provider_token_expires_at, :utc_datetime_usec,
      null: true,
      comment: "Token expiration"
    )
  end

  defp oauth_indexes do
    [{:provider_unique_index, [:provider, :provider_id], [unique: true]}]
  end

  # ============================================
  # Magic Link Authentication
  # ============================================

  defp build_magic_link_auth(token, _config) do
    token
    |> Token.add_field(:magic_token, :string, null: true, comment: "Magic link token")
    |> Token.add_field(:magic_token_sent_at, :utc_datetime_usec,
      null: true,
      comment: "Magic link sent at"
    )
    |> Token.add_field(:magic_token_expires_at, :utc_datetime_usec,
      null: true,
      comment: "Magic link expires at"
    )
  end

  defp magic_link_indexes do
    [{:magic_token_unique_index, [:magic_token], [unique: true]}]
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds authentication fields to a migration token.

  ## Options

  - `:type` - Authentication type: `:password`, `:oauth`, `:magic_link` (default: `:password`)
  - `:with_lockout` - Include lockout fields (default: true for password)
  - `:with_confirmation` - Include confirmation fields (default: true for password)

  ## Examples

      Authentication.add(token)
      Authentication.add(token, type: :oauth)
      Authentication.add(token, type: :password, with_lockout: false)
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
