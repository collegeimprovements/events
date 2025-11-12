defmodule Events.Errors.Mappers.Business do
  @moduledoc """
  Error mapper for business logic errors.

  Handles normalization of domain-specific errors that aren't covered
  by technical error types (validation, HTTP, database, etc.).

  These are errors that represent business rule violations, domain
  constraints, and application-specific conditions.

  ## Usage

      # Define custom business errors in your domains
      defmodule MyApp.Accounts.Errors do
        def insufficient_balance(current, required) do
          {:business_error, :insufficient_balance,
            message: "Insufficient balance",
            details: %{current: current, required: required}}
        end

        def subscription_expired(expires_at) do
          {:business_error, :subscription_expired,
            message: "Subscription has expired",
            details: %{expired_at: expires_at}}
        end
      end

      # Normalize in your handlers
      case Accounts.withdraw(user, amount) do
        {:error, {:business_error, code, opts}} ->
          Business.normalize(code, opts)
        result ->
          result
      end
  """

  alias Events.Errors.Error

  @doc """
  Normalizes a business error tuple.

  ## Examples

      iex> Business.normalize(:insufficient_balance, details: %{current: 10, required: 100})
      %Error{type: :unprocessable, code: :insufficient_balance}

      iex> Business.normalize(:quota_exceeded)
      %Error{type: :rate_limit, code: :quota_exceeded}
  """
  @spec normalize(atom(), keyword()) :: Error.t()
  def normalize(code, opts \\ []) when is_atom(code) do
    {type, message} = map_business_code(code)

    Error.new(type, code,
      message: Keyword.get(opts, :message, message),
      details: Keyword.get(opts, :details, %{}),
      source: :business,
      metadata: Keyword.get(opts, :metadata, %{})
    )
  end

  @doc """
  Normalizes a business error tuple format.

  ## Examples

      iex> Business.normalize({:business_error, :insufficient_balance, message: "Not enough funds"})
      %Error{type: :unprocessable, code: :insufficient_balance}
  """
  @spec normalize_tuple({:business_error, atom(), keyword()}) :: Error.t()
  def normalize_tuple({:business_error, code, opts}) do
    normalize(code, opts)
  end

  ## Business Error Mappings

  # Account & Balance
  defp map_business_code(:insufficient_balance),
    do: {:unprocessable, "Insufficient balance to complete transaction"}

  defp map_business_code(:account_suspended),
    do: {:forbidden, "Account has been suspended"}

  defp map_business_code(:account_closed),
    do: {:forbidden, "Account has been closed"}

  defp map_business_code(:account_locked),
    do: {:forbidden, "Account is temporarily locked"}

  defp map_business_code(:pending_verification),
    do: {:forbidden, "Account verification pending"}

  # Subscription & Billing
  defp map_business_code(:subscription_expired),
    do: {:forbidden, "Subscription has expired"}

  defp map_business_code(:subscription_cancelled),
    do: {:forbidden, "Subscription has been cancelled"}

  defp map_business_code(:payment_required),
    do: {:forbidden, "Payment required to access this feature"}

  defp map_business_code(:trial_expired),
    do: {:forbidden, "Trial period has expired"}

  defp map_business_code(:upgrade_required),
    do: {:forbidden, "Upgrade required to access this feature"}

  # Quota & Limits
  defp map_business_code(:quota_exceeded),
    do: {:rate_limit, "Usage quota exceeded"}

  defp map_business_code(:storage_limit_exceeded),
    do: {:unprocessable, "Storage limit exceeded"}

  defp map_business_code(:user_limit_exceeded),
    do: {:unprocessable, "User limit exceeded"}

  defp map_business_code(:api_limit_exceeded),
    do: {:rate_limit, "API rate limit exceeded"}

  defp map_business_code(:concurrent_limit_exceeded),
    do: {:rate_limit, "Concurrent operation limit exceeded"}

  # Workflow & State
  defp map_business_code(:invalid_state_transition),
    do: {:conflict, "Invalid state transition"}

  defp map_business_code(:operation_not_allowed),
    do: {:forbidden, "Operation not allowed in current state"}

  defp map_business_code(:already_processed),
    do: {:conflict, "Request has already been processed"}

  defp map_business_code(:stale_data),
    do: {:conflict, "Data has been modified by another request"}

  defp map_business_code(:concurrent_modification),
    do: {:conflict, "Concurrent modification detected"}

  # Business Rules
  defp map_business_code(:minimum_not_met),
    do: {:validation, "Minimum requirement not met"}

  defp map_business_code(:maximum_exceeded),
    do: {:validation, "Maximum limit exceeded"}

  defp map_business_code(:invalid_combination),
    do: {:validation, "Invalid combination of values"}

  defp map_business_code(:dependency_required),
    do: {:unprocessable, "Required dependency missing"}

  defp map_business_code(:precondition_failed),
    do: {:unprocessable, "Precondition not satisfied"}

  # Inventory & Stock
  defp map_business_code(:out_of_stock),
    do: {:unprocessable, "Item is out of stock"}

  defp map_business_code(:insufficient_inventory),
    do: {:unprocessable, "Insufficient inventory"}

  defp map_business_code(:reservation_expired),
    do: {:conflict, "Reservation has expired"}

  defp map_business_code(:item_discontinued),
    do: {:unprocessable, "Item has been discontinued"}

  # Scheduling & Availability
  defp map_business_code(:slot_unavailable),
    do: {:conflict, "Time slot is no longer available"}

  defp map_business_code(:booking_conflict),
    do: {:conflict, "Booking conflicts with existing reservation"}

  defp map_business_code(:outside_business_hours),
    do: {:unprocessable, "Operation outside business hours"}

  defp map_business_code(:deadline_passed),
    do: {:unprocessable, "Deadline has passed"}

  # Geography & Restrictions
  defp map_business_code(:region_restricted),
    do: {:forbidden, "Service not available in your region"}

  defp map_business_code(:country_blocked),
    do: {:forbidden, "Access blocked for your country"}

  defp map_business_code(:ip_restricted),
    do: {:forbidden, "Access restricted from your IP address"}

  # Age & Eligibility
  defp map_business_code(:age_restriction),
    do: {:forbidden, "Age requirement not met"}

  defp map_business_code(:eligibility_not_met),
    do: {:forbidden, "Eligibility criteria not met"}

  # Document & Verification
  defp map_business_code(:document_expired),
    do: {:unprocessable, "Document has expired"}

  defp map_business_code(:verification_failed),
    do: {:unprocessable, "Verification failed"}

  defp map_business_code(:incomplete_profile),
    do: {:unprocessable, "Profile information incomplete"}

  # Integration & External
  defp map_business_code(:external_service_unavailable),
    do: {:service_unavailable, "External service temporarily unavailable"}

  defp map_business_code(:integration_disabled),
    do: {:forbidden, "Integration has been disabled"}

  defp map_business_code(:feature_disabled),
    do: {:forbidden, "Feature is currently disabled"}

  # Fallback
  defp map_business_code(code) when is_atom(code) do
    message =
      code
      |> Atom.to_string()
      |> String.replace("_", " ")
      |> String.capitalize()

    {:unprocessable, message}
  end
end
